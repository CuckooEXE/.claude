---
description: Run language-native supply-chain audit, summarize findings, and propose triage actions per CVE.
argument-hint: [optional — focus on a single ecosystem if the project is polyglot]
allowed-tools: Bash(pip-audit:*), Bash(safety:*), Bash(cargo:*), Bash(npm:*), Bash(pnpm:*), Bash(govulncheck:*), Bash(osv-scanner:*), Bash(trivy:*), Bash(grype:*), Bash(jq:*), Read, Glob
---

# /dep-audit — supply-chain audit

Goal: surface known vulnerabilities in the project's dependency tree, classified by reachability and severity, with a concrete next-action per finding.

Argument: `$ARGUMENTS` — optional ecosystem name (`python`, `rust`, `go`, `node`) to scope a polyglot project. If empty, audit everything detected.

## Procedure

1. **Detect ecosystems** present in the project:
   - Python: `pyproject.toml`, `requirements*.txt`, `Pipfile`, `poetry.lock`, `uv.lock`.
   - Rust: `Cargo.toml`, `Cargo.lock`.
   - Go: `go.mod`, `go.sum`.
   - Node: `package.json`, `package-lock.json`, `pnpm-lock.yaml`.
   - C/C++: `vcpkg.json`, Conan config (rare).

2. **Run the right auditor per ecosystem** — mark all with `[log]`:

   ```bash
   # Python — pip-audit reads requirements / poetry / pip-tools
   pip-audit --format json
   # or, more strict:
   pip-audit --strict --vulnerability-service osv

   # Rust — cargo audit reads Cargo.lock
   cargo audit --json
   # cargo deny — broader (advisories + licenses + bans)
   cargo deny check advisories

   # Go — govulncheck does reachability analysis (gold standard)
   govulncheck ./...
   # JSON for parsing
   govulncheck -json ./...

   # Node
   npm audit --json
   # or pnpm audit --json

   # Cross-ecosystem fallback
   osv-scanner --recursive .
   trivy fs --scanners vuln .
   ```

   **Prefer `govulncheck` for Go projects** — its reachability analysis filters findings to "actually called from your code." Other auditors flag by version, which produces noise.

3. **Parse and classify findings**. For each finding:

   | Field | What to record |
   |---|---|
   | CVE / advisory ID | `GHSA-xxxx-xxxx-xxxx`, `RUSTSEC-2024-...`, etc. |
   | Affected dep + version | `pkg@1.2.3` |
   | Severity | `critical / high / medium / low` (per the auditor or NVD) |
   | Fixed version | If a patched version exists |
   | Reachability | If the auditor reports it (govulncheck does); otherwise mark "unknown" |
   | Description | One-line summary |

4. **Triage each finding** with one of these actions:

   - **Update**: a fixed version exists and the upgrade is non-breaking. Recommend `cargo update -p <pkg>` / `pip install --upgrade <pkg>` / etc., and offer to run it.
   - **Pin to safe version**: the latest is broken or breaking, but an older patched version exists. Recommend the pin.
   - **Mitigate in code**: vuln is in a function not called by your code (verify via grep). Document and ignore.
   - **Mitigate at runtime**: vuln requires attacker control of an input that's not exposed externally. Document and ignore.
   - **Fork / patch**: no upstream fix; project is critical. Last resort.
   - **Accept**: low-severity, low-impact, no fix available. Document the decision in `security/audit-decisions.md` (create if missing).

5. **Report**:
   - Summary line: "X advisories: Y critical, Z high, ...".
   - Per-finding: severity, dep@version, CVE id, reachability, recommended action, one-line rationale.
   - Sort by severity desc, then reachable-first.
   - At the end: a list of recommended commands to apply the easy fixes (the "update" cases). **Don't run them automatically** — let the user approve.

6. **Documentation**:
   - For findings classified as "Mitigate" or "Accept", suggest writing the decision to `security/audit-decisions.md` so the next audit doesn't re-investigate.
   - Format suggestion: `## <CVE-id> — <pkg>@<version> — <decision> (<date>)` followed by a short rationale.

## Don't

- **Don't auto-update** without showing the diff and getting confirmation. A "patch" version bump can ship behavior changes.
- **Don't dismiss low-severity findings reflexively.** A low-severity vuln on a high-trust path matters more than a critical on a sandboxed extension.
- **Don't run `--force` or `--audit-level=critical` flags** to silence findings without recording the decision.
- **Don't audit only the lockfile** — also check that the manifest's range still admits the patched version. If not, the manifest needs a bump.

## See also

- `dependency-management` skill — broader hygiene around adding/removing/updating deps.
- `security-research-workflow` skill — when the audit finding turns out to be exploitable in *your* product.
- `/scope` — see what dep changes are pending in the current branch before running the audit.
