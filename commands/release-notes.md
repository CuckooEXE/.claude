---
description: Diff against the last tag (or a specified ref), classify changes, and propose changelog entries in the project's style.
argument-hint: [base ref; defaults to the latest tag matching v*]
allowed-tools: Bash(git:*), Bash(test:*), Read, Edit
---

# /release-notes — propose changelog entries

## Procedure

1. **Determine the base ref.**
   - If `$ARGUMENTS` is non-empty, use it.
   - Else `git describe --tags --abbrev=0 --match 'v*'` for the latest semver tag.
   - Else `git tag --sort=-creatordate | head -1` for any latest tag.
   - Else stop and ask the user — there's no sensible default.

2. **Pull the commit list.**
   ```
   git log <base>..HEAD --pretty='%h %s%n%b' --reverse
   ```
   Filter out `wip(claude):` checkpoints. They should already have been squashed; if any leak through, warn the user that `/squash` should be run first before generating release notes.

3. **Detect the project's changelog conventions.**
   - If `CHANGELOG.md` exists, read the most recent release entry. Match its structure (Keep a Changelog, sentence-case, ticket-prefixed, etc.).
   - If no changelog exists, default to **Keep a Changelog** sections: `Added`, `Changed`, `Deprecated`, `Removed`, `Fixed`, `Security`.

4. **Classify each commit.** Map Conventional Commit types to changelog sections:

   | Type | Section |
   |---|---|
   | `feat:` | Added |
   | `fix:` | Fixed |
   | `perf:` | Changed (note as "performance: ...") |
   | `refactor:` | Changed (only if user-visible) |
   | breaking change footer | Changed (mark **BREAKING**) |
   | `docs:` / `test:` / `build:` / `ci:` / `chore:` | omit by default; include if the user asks |
   | `re:` / `poc:` / `writeup:` | omit; these are research artifacts, not user-facing |

   For non-Conventional commits, infer from subject text. If you can't classify confidently, leave it under `Uncategorized` and ask.

5. **Rewrite each entry for the changelog.**
   - User-facing language. Drop internal jargon.
   - Imperative or past tense to match the existing changelog (Keep a Changelog uses past-tense / noun phrases).
   - Reference issue / PR / CVE numbers if present in the commit body.
   - Drop noise: "WIP", "fix typo", "rebase", "merge".

6. **Propose the diff.** Show the user what you'd add to `CHANGELOG.md` (or create it). Pre-fill the version header — but **don't pick the version number for them**. Use a placeholder like `## [Unreleased]` (or `## [vX.Y.Z] — YYYY-MM-DD`) and ask.

7. **On user confirmation**, prepend the new entry to `CHANGELOG.md`. Don't reorder existing entries. Don't reformat the rest of the file.

## Output template (before the user confirms)

```
Base: <ref> (<sha>)
Range: <commit count> commits

## Proposed CHANGELOG entry

## [vX.Y.Z] — YYYY-MM-DD <!-- pick a version -->

### Added
- ...

### Changed
- **BREAKING** ...
- ...

### Fixed
- ...

### Uncategorized (need human decision)
- <commit subject> (<sha>) — reason: <why we couldn't classify>

Confirm to write to CHANGELOG.md, or tell me what to change.
```

## Rules

- **Don't write to CHANGELOG.md without explicit confirmation.** The version number choice and entry wording matter.
- **Don't push.** Don't tag. Don't `git commit`. The auto-commit hook handles staging; tagging and pushing are the user's call.
- **Don't invent CVE numbers or PR links** that don't appear in the commits.
- If a `wip(claude):` commit slips through (the user forgot to `/squash`), stop and recommend they squash first — release notes generated against unsquashed history are noise.
