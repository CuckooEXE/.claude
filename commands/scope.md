---
description: Summarize the scope of the current change against a base ref — files touched, tests added/modified, docs touched, public-API hits, suspected leftovers. Useful as a sanity check before /squash and /dod.
argument-hint: [optional base ref; defaults to upstream tracking branch or main]
allowed-tools: Bash(git:*), Bash(test:*), Bash(grep:*), Bash(wc:*), Read, Glob, Grep
---

# /scope — what's in this change

A read-only snapshot of the in-flight change. Pairs with `/dod` (audits the change) and `/squash` (consolidates the change).

## Procedure

1. **Determine the base ref.**
   - `$ARGUMENTS` if non-empty.
   - Else upstream: `git rev-parse --abbrev-ref --symbolic-full-name @{u}`.
   - Else `main` (or `master`).
   - If none of the above resolve, stop and ask.

2. **Compute changed files.** Combine staged + unstaged + committed-since-base. Exclude `wip(claude):` checkpoint commit noise from the *commit list* by counting them separately, but include the file effects (the auto-commit hook stages everything anyway).

3. **Bucket the files.** Heuristics — adapt to the project's actual layout:
   - `src/`, `lib/`, top-level `*.{c,cpp,h,hpp,py,zig,rs,go}` → **code**
   - `tests/`, `*_test.*`, `test_*.*`, `*Tests.cpp` → **tests**
   - `docs/`, `*.md`, `README*`, `CHANGELOG*` → **docs**
   - `CMakeLists.txt`, `Makefile`, `pyproject.toml`, `build.zig`, `*.bazel`, `BUILD`, `meson.build` → **build**
   - `.github/`, `.gitlab-ci*`, `Jenkinsfile` → **ci**
   - `samples/`, `notes/`, `poc/`, `scripts/` (security project layout) → **research**
   - Everything else → **other**

4. **Detect notable signals.**
   - **Public API surface touched?** Heuristic: changed lines in headers (`*.h`, `*.hpp`), exported Python (anything in `__all__` or top-level `def`/`class` not prefixed `_`), public Rust (`pub`), Zig public decls. Mention which symbols changed.
   - **New TODOs / FIXMEs introduced?** `git diff <base>..HEAD -- '*' | grep -E '^\+.*\b(TODO|FIXME|XXX)\b'` — count and list locations.
   - **Debug leftovers?** `print(`, `console.log(`, `dbg!`, `printf("DEBUG`, `dbg(` in changed code lines.
   - **Possible secrets?** Pattern match against changed lines: `BEGIN PRIVATE KEY`, `aws_access_key_id`, `api[_-]?key\s*=\s*["']`, `password\s*=\s*["']`. Mark hits as *suspicious* — don't claim leaks; ask.
   - **Test coverage gap?** For each changed file in **code**, check whether a sibling/mirror file in **tests** is also changed. List the gaps.

5. **Summarize commits.**
   - Total commits since base.
   - Of those, how many are `wip(claude):` checkpoints vs clean.
   - If any are wip, recommend running `/squash` before push.

## Output template

```
## Scope — <branch> vs <base>

### Files
- code:     <count>  (<list, abbreviated>)
- tests:    <count>  (<list>)
- docs:     <count>  (<list>)
- build:    <count>  (<list>)
- ci:       <count>  (<list>)
- research: <count>  (<list>)
- other:    <count>  (<list>)

### Commits
- Total since base: <N>
- wip(claude) checkpoints: <M>
- Clean commits: <N - M>
<!-- if M > 0 -->
- Recommendation: run `/squash` before pushing.

### Public API
- <symbol/file:line — what changed>   (or "no public API changes detected")

### Test coverage gaps
- <code file without a sibling test change>   (or "none")

### Signals
- TODO/FIXME introduced: <count>  (<file:line list>)
- Debug print leftovers: <count>  (<file:line list>)
- Suspicious string matches: <count>  (<file:line list, marked SUSPICIOUS not CONFIRMED>)

### Diffstat
<output of `git diff --stat <base>..HEAD` plus working tree>

### Suggested next step
<one sentence — usually "/dod" if signals exist, "/squash" if clean, "/release-notes" if on a release branch>
```

## Rules

- **Read-only.** Never modify files, never commit, never push.
- **Don't claim things you don't know.** Heuristics produce false positives; flag them as *suspect*, not *confirmed*.
- **Don't run the test suite or linters here.** That's `/dod`'s job. Keep this command fast.
- If the base ref resolves to a commit that isn't in the local repo (rare), stop and ask the user to fetch.
