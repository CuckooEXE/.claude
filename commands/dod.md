---
description: Run the "Definition of Done" checklist from `software-engineering-practices` against the current branch. Reports gaps; does not auto-fix.
argument-hint: [optional base branch; defaults to the upstream tracking branch or "main"]
allowed-tools: Bash(git:*), Bash(test:*), Bash(ls:*), Bash(grep:*), Bash(find:*), Read, Glob, Grep
---

# /dod — definition-of-done audit

Pull in `software-engineering-practices` for the canonical list. This command is read-only — it surveys, reports, and proposes. It does not commit, push, or modify code.

## Procedure

1. **Determine the base.**
   - If `$ARGUMENTS` is non-empty, use it.
   - Else `git rev-parse --abbrev-ref --symbolic-full-name @{u}` for the upstream — use that.
   - Else fall back to `main` (or `master` if `main` doesn't exist).
   - If none of those exist, stop and ask the user.

2. **Diff scope.** Compute the set of changed files: `git diff --name-only <base>...HEAD` plus `git diff --name-only` for unstaged and `git diff --name-only --cached` for staged. Deduplicate. This is the *blast radius* of the in-flight change.

3. **Run the checklist.** For each item, report PASS / FAIL / N/A with evidence:

   ### Tests
   - [ ] Files in the changed set under `src/` (or equivalent) have a corresponding test file changed in the same diff. Heuristic: for `src/foo/bar.py` look for `tests/**/test_bar.py` or `tests/**/bar_test.*`. Mismatch = FAIL with the file pair.
   - [ ] No file *only* contains code (no test) unless its purpose is purely declarative (config, schemas, docs). Flag suspicious cases.
   - [ ] The test suite passes. Detect the runner from the project (pytest, ctest, `cmake --build . --target test`, `zig build test`, `go test`, etc.) and run it. If you can't determine the runner, ask. Don't skip this step silently.

   ### Linters / type checkers
   - [ ] If the project has a linter config (`.ruff.toml`, `pyproject.toml`'s `[tool.ruff]`, `.clang-tidy`, `mypy.ini`, etc.), run it on the changed files. PASS only on clean output.
   - [ ] Warnings are explicitly justified in a comment, or absent.

   ### Documentation
   - [ ] If a public function/class/type was added or changed, its docstring/doc-comment exists and is current.
   - [ ] If the change touches user-visible behavior, `docs/user-guide/` has a corresponding update.
   - [ ] If the change touches build / test / contributing flow, `docs/developer-guide/` has a corresponding update.
   - [ ] If the change touches architecture, `docs/Architecture and Design.md` reflects it.
   - [ ] If a non-obvious / costly-to-reverse decision was made, an ADR exists in `docs/adr/`.

   ### Public API / changelog
   - [ ] If the change touches public API, `CHANGELOG.md` (or equivalent) has an entry.
   - [ ] Breaking changes are flagged in the changelog.

   ### Reviewability
   - [ ] The diff is small enough to review (heuristic: < ~400 lines of non-test changes). If larger, suggest splits.

   ### Hygiene
   - [ ] No `TODO` / `FIXME` / `XXX` introduced without a name and date.
   - [ ] No commented-out code introduced.
   - [ ] No leftover `print` / `console.log` / `dbg!` debug statements.
   - [ ] No new files containing secrets (regex check on common patterns: `BEGIN PRIVATE KEY`, `aws_access_key_id`, `api[_-]?key\s*=`, etc.). Treat any hit as suspicious; don't claim a leak from a single match.

4. **Output format:**

   ```
   ## Definition of Done — <branch> vs <base>

   ### PASS
   - <item>
   - <item>

   ### FAIL (blockers)
   - <item> — evidence: <file:line or command output>

   ### N/A
   - <item> — reason: <one line>

   ### Suggestions
   - <one-line suggestions for any FAILs that have an obvious fix>

   ## Next step
   <one sentence — usually "run X to fix Y" or "the change is ready to /squash">
   ```

## Rules

- **Read-only.** Never `git commit`, never modify code, never edit configs to silence warnings. The command's value is the audit.
- **Don't run the test suite if it would take more than ~2 minutes.** Ask first. Surfacing the question is fine.
- **Don't lie.** If a check is "I don't know how to run this project's tests," say so explicitly under N/A. False PASS is worse than honest N/A.
- The auto-commit hook produces `wip(claude):` commits — these aren't part of the DoD review. Compare against `<base>`, not against the most recent commit.
