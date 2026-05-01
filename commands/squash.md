---
description: Squash the trailing `wip(claude):` auto-commits at HEAD into one or more clean commits, ready to push.
argument-hint: [optional one-line subject for a single squashed commit]
allowed-tools: Bash(git:*), Read, Edit
---

# /squash — consolidate the wip(claude) checkpoint commits

The user runs the auto-commit Stop hook (`hooks/auto-commit.sh`), which produces a `wip(claude): <timestamp> — <stat>` commit after every turn. They are now ready to push and want those checkpoints replaced with a clean, reviewable commit history.

Argument: `$ARGUMENTS` — if non-empty, treat it as a subject hint for a **single** squashed commit (do not propose splitting).

## Procedure

1. **Locate the wip range.**
   - Run `git log --pretty='%h %s' -n 50` to inspect the recent history.
   - Walk from HEAD backward and find the longest run of commits whose subject starts with `wip(claude):`. Call the first non-wip commit `BASE`.
   - If there are zero `wip(claude):` commits at HEAD, tell the user and stop.
   - If `BASE` cannot be determined (e.g., wip commits go all the way back to the root), ask the user how far back to squash.

2. **Refuse to operate on a published range.**
   - Run `git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null` to find the upstream.
   - If an upstream exists, run `git merge-base --is-ancestor BASE @{u}` to verify the wip commits are still local.
   - If any wip commit has been pushed already, **stop and warn the user** — squashing would require a force-push.

3. **Bail on dirty trees and in-progress operations.**
   - `git status --porcelain` must be empty (no unstaged changes).
   - `.git/rebase-merge`, `.git/rebase-apply`, `.git/MERGE_HEAD`, `.git/CHERRY_PICK_HEAD` must not exist.
   - If any check fails, stop and tell the user what to clean up first.

4. **Inspect the cumulative change.**
   - `git log BASE..HEAD --stat`
   - `git diff BASE..HEAD` — read it. This is what the squashed commit(s) will contain.

5. **Decide the split.**
   - If `$ARGUMENTS` is set: one commit with that subject.
   - Otherwise: read the diff and judge whether the work is **one logical change** or **multiple unrelated changes** (e.g. a feature + an unrelated docs fix + a tooling tweak). Default to one commit unless the split is obvious. If you propose splitting, **list the proposed commits and ask the user to confirm before executing**.

6. **Match the project's commit style.**
   - Run `git log BASE -n 20 --pretty='%s'` to see the repo's actual convention. Mirror it (Conventional Commits / sentence-case / ticket-prefixed / whatever is there). Do not impose a style the project does not use.

7. **Execute the squash.**
   - Create a safety tag: `git tag claude-presquash-$(date -u +%Y%m%dT%H%M%SZ)` so the user can recover if needed.
   - `git reset --soft BASE` to bring all the diff back into the index without losing it.
   - For a single-commit squash: `git reset` (unstage), `git add -A`, then `git commit -m "<subject>" -m "<body>"`. Let pre-commit hooks run — these are real commits now.
   - For a multi-commit split: `git reset`, then for each group `git add <files>` + `git commit`. Verify nothing is left over with `git status` at the end.
   - If a pre-commit hook fails, do **not** retry with `--no-verify`. Surface the failure to the user, leave the index staged, and stop.

8. **Report.**
   - `git log --oneline BASE^..HEAD` — show the new history.
   - Remind the user of the safety tag and how to recover (`git reset --hard <tag>`) if they don't like the result.
   - Do **not** push. The user pushes themselves.

## Hard rules

- Never `git push`. Never `git push --force`.
- Never operate on commits that exist on the upstream branch.
- Never `--no-verify` on the clean commits — the whole point of squashing is to run hooks on the consolidated change.
- Never delete the safety tag automatically.
