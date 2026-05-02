---
name: dependency-management
description: Hygiene for third-party dependencies — lockfiles, pinning strategy, supply-chain audit, vendoring, reproducible builds, and update cadence. Use when adding a new dependency, updating existing ones, triaging an audit finding, deciding between lockfile and vendoring, or critiquing the dependency hygiene of a project. Pairs with `build-systems` (where lockfiles integrate) and `security-research-workflow` (when auditing for malicious packages). Trigger on changes to `requirements.txt` / `pyproject.toml` / `Cargo.toml` / `package.json` / `go.mod` / `build.zig.zon`, `pip install` / `cargo add` / `npm install`, audit reports, vulnerability disclosures, or questions like "should I pin this", "is this dep safe", "what's the right way to update X".
---

# Dependency management

Every dependency is a **transitive risk surface and a permanent maintenance commitment.** This skill is about minimizing both without becoming the team that won't add a single library.

## The first decision: should this be a dependency at all?

Before adding a dep, ask:

1. **Could I write this myself in <100 lines?** Often the answer is yes for small utilities. The dep adds versioning headache, audit surface, and a transitive tree. The 100-line ad-hoc version is sometimes the right answer.
2. **Is this dep maintained?** Last commit > 2 years ago, single author with no replies on issues, abandoned `npm` package — *especially* in JavaScript — is a smell. Dependencies stop being free when they need a fork.
3. **What's the transitive cost?** Run `pip install --dry-run X` / `cargo tree` / `npm ls` *before* adding. A small package that pulls 47 transitive deps is not a small package.
4. **Does my license allow it?** GPL in a proprietary product, no LICENSE file, "by using this you agree to..." — check before committing.
5. **Does this need to be in production, or only in dev?** Build/test/lint deps should be separate from runtime deps. Don't ship pytest to production.

The user's CLAUDE.md says "Read before you write... Before introducing a dependency, check what's already in the project." Adopt the same bias against new deps.

## Lockfiles

A lockfile pins **every** transitive dependency to an exact version. Without it, `pip install foo==1.2.3` can resolve different transitive deps on different machines.

| Ecosystem | Lockfile |
|---|---|
| Python | `poetry.lock`, `uv.lock`, `pipenv` `Pipfile.lock`, or `requirements.txt` with hashes |
| Rust | `Cargo.lock` |
| Node | `package-lock.json`, `yarn.lock`, `pnpm-lock.yaml` |
| Go | `go.sum` (paired with `go.mod`) |
| Zig | `build.zig.zon` (with hash field) |
| C/C++ | None standard; consider `vcpkg.json` lockfile, Conan lockfile, or vendored submodules |

**Rules:**

- **Commit the lockfile.** Yes, even for libraries (Cargo's stance) — it pins the dev-environment versions. CI installs from it.
- **Regenerate, don't hand-edit.** Use the tooling (`poetry update`, `cargo update`, `npm update`).
- **Review lockfile diffs.** A 1000-line lockfile diff for a "small dep update" is suspect — what got pulled in?

## Pinning strategy

### For applications (the thing being deployed)

**Pin everything to exact versions.** The lockfile does most of this; the manifest should also be tight.

```toml
# pyproject.toml — application
dependencies = [
    "fastapi==0.110.1",
    "sqlalchemy==2.0.29",
]
```

Reasons: reproducible deploys, no surprise breakage on a redeploy, security audit can trust the lockfile.

### For libraries (the thing being depended on)

**Allow ranges**, but bound them.

```toml
# pyproject.toml — library
dependencies = [
    "requests>=2.31,<3",
    "click>=8,<9",
]
```

Reasons: consumers need to compose your library with their other deps. Over-tight pins cause unsolvable resolutions.

### Conventions per ecosystem

- **Python**: `>=2.31,<3` is the standard range form. Avoid `^` (Poetry-specific). Avoid `~=` unless you really mean "compatible release."
- **Rust**: `^2.31` (caret, the default) means `>=2.31, <3.0`. Cargo handles the SemVer math.
- **Node**: `^2.31.0` means the same. Tilde `~` is patch-only.
- **Go**: SemVer required for v2+ via the import path (`pkg/v2`). Pinning is in `go.mod`.

## Vendoring

Vendoring = checking the dep's source code into your repo.

**When to vendor:**

- The dep is unlikely to change and you want zero supply-chain surprise.
- The dep has been forked with local patches that you can't upstream (yet).
- You need to ship to environments without network access (air-gapped, embedded).
- Reproducibility is paramount (security-critical builds, regulated environments).

**When NOT to vendor:**

- Casually. Vendored code rots — security patches don't reach you.
- For convenience. Lockfiles do the same job with less repo bloat.

If you vendor, **commit a clear pointer** to the upstream version (commit hash, tag) in a `VENDORED.md` or per-vendor README, and **document the patch set** if you have local diffs.

## Supply-chain audit

Run an auditor regularly. Default tools:

- **Python**: `pip-audit`, `safety check`, `osv-scanner`.
- **Rust**: `cargo audit` (uses RustSec advisory DB).
- **Node**: `npm audit`, `pnpm audit`. `socket.dev` for typo-squatting and behavior anomalies.
- **Go**: `govulncheck`. Includes path-of-use analysis (only flags vulns reachable from your code).
- **Multi-ecosystem**: `osv-scanner`, `trivy fs`, `grype`.

`govulncheck`'s reachability analysis is the gold standard — most other auditors flag vulnerabilities by package version, not actual code path. Many `npm audit` warnings are unreachable in practice.

### Triaging an audit finding

When the auditor reports a CVE:

1. **Check reachability.** Is the vulnerable function actually called from your code? `govulncheck` does this; for others, grep manually.
2. **Check exposure.** Even if reachable, is the input attacker-controlled? A `regex DoS` in a function only called with literal regex is not exploitable.
3. **Check fix availability.** Is there a patched version? If yes, update. If no, decide whether to pin to the unaffected version, fork, or accept.
4. **Document the decision** in a tracking file (`security/audit-decisions.md` or similar) so the next audit doesn't redo the work.

A "false positive" you didn't document is a "true positive" you'll re-investigate next quarter.

## Update cadence

Two failure modes:

- **Update never**: deps rot, security patches missed, jumping forward N major versions becomes a nightmare.
- **Update on every release**: constant churn, no time to investigate any one update, breakage from minor versions of half the tree.

A reasonable middle:

- **Patch updates**: weekly, automated. Renovate, Dependabot, or `cargo update` in CI. Auto-merge if tests pass.
- **Minor updates**: monthly. Read changelogs. Run the full test suite, including integration. Don't auto-merge.
- **Major updates**: scheduled. One major version bump per dep at a time. Read the migration guide. Allocate days, not minutes.
- **Security patches**: out-of-band. As soon as the audit reports them.

Pin Renovate / Dependabot config to grouping that matches this — `pin: never` for major, `automerge: true` for patch.

## Reproducible builds

A reproducible build means the same source + same dep tree produces bit-identical output.

Concerns:

- **Lockfile** ensures the same dep versions.
- **Hashes in lockfile** ensure the same *bytes* of those versions (not just the version number — the same package can be republished under a different hash).
- **Build environment** (OS, compiler version, locale, timestamps) should be controlled. Containers help.
- **No timestamps embedded in artifacts.** Use `SOURCE_DATE_EPOCH` for reproducible-builds-aware tools.

For Python, `pip install --require-hashes` enforces the lockfile's hashes. Always use this in production install paths.

## Sigstore / signed packages

The supply-chain attack surface is "I uploaded a malicious package matching the name." Mitigations:

- **PyPI** supports signed releases via Sigstore (recent). Verify signatures when available.
- **npm** has provenance attestations.
- **Container images**: cosign, sigstore.
- **Operating system packages**: GPG signed by default on most distros.

When integrating a new dep, prefer one with signed releases. When publishing your own, sign with sigstore.

## License hygiene

For each dep, know the license. Tooling:

- **Python**: `pip-licenses`, `license-checker`.
- **Rust**: `cargo deny check licenses`.
- **Node**: `license-checker`, `licensee`.

Set a project-level allowlist (MIT, BSD, Apache-2.0, ISC, MPL-2.0, often). Block GPL-family if you're shipping proprietary; require commercial-use review for licenses that demand it.

A dep with no LICENSE file or an unrecognized license is a flag to investigate — *not* a default-allow.

## Vulnerability disclosure for your own libraries

If you publish, expect to receive vulnerability reports. Have:

- A `SECURITY.md` describing how to report (private channel, expected response time).
- A coordinated disclosure timeline (typically 90 days from report to public fix).
- A CVE process — request a CVE for confirmed vulns. Many ecosystems will assign one for you (rust-sec, GitHub Security Advisory).
- Patched releases for affected versions, not just the latest. Backport if possible.

## Adding a new dep — checklist

Before `pip install foo` lands in main:

1. ✅ Could we do this without a dep?
2. ✅ Is the dep maintained (recent commits, responsive maintainers, sane test suite)?
3. ✅ What's the transitive tree size?
4. ✅ License acceptable?
5. ✅ Audit clean (no open advisories)?
6. ✅ Pinned to a specific version (apps) or a bounded range (libs)?
7. ✅ Lockfile updated?
8. ✅ CI passes against the lockfile?
9. ✅ A short note in the PR description explaining *why this dep* (which alternatives were considered).

The note in the PR description matters. Three years from now, someone will ask "why are we using foo and not bar" and the answer should be retrievable from `git log`.

## Removing a dep

Removing is easier than adding but has its own discipline:

1. Find all usages (`grep -r`, language tooling).
2. Replace or inline.
3. Remove from manifest.
4. Regenerate lockfile.
5. Verify the lockfile no longer pulls the removed dep transitively.
6. Run the full test suite — CI alone isn't enough; some deps register import-time hooks that work in some contexts and not others.

## When a dep is broken

The dep has a bug that affects you. Options, in order of preference:

1. **Workaround in your code** + open an issue upstream.
2. **Patch via monkey-patch / shim** + open a PR upstream.
3. **Pin to a known-good older version** + track the upstream fix.
4. **Fork**. Last resort — you now own the maintenance.

Forking should always be temporary, with a clear plan to upstream and unfork. A long-lived fork is a maintenance commitment few projects can sustain.

## The fundamental tension

The discipline tension: **fewer deps → more code to maintain. More deps → more supply-chain surface.** There's no globally correct answer. Per-project, per-ecosystem, the bias differs:

- For a security-critical service: fewer deps wins.
- For a CLI tool that needs to work today: more deps wins.
- For a library others depend on: minimize transitive impact.

Default to *fewer deps* unless you have a specific reason. The user's principle of "Don't add features beyond what the task requires" extends to dependencies.
