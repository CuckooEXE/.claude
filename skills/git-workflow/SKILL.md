---
name: git-workflow
description: The user's git conventions — commit message style, branch naming, when to amend vs new commit, when to squash vs not, force-push policy, tagging, and the auto-commit-then-/squash workflow. Use this skill whenever writing commit messages, naming a branch, deciding whether to rewrite history, or when the user asks anything git-related. Trigger before any `git commit`, `git rebase`, `git push`, or `git tag` operation.
---

# Git Workflow

The user runs the auto-commit `Stop` hook from this template, which produces a stream of `wip(claude):` checkpoint commits. Real, reviewable history is created by the `/squash` slash command at push time. This skill describes the conventions for that final, clean history — and the rules for getting there safely.

## The two-tier commit model

There are two kinds of commits in this workflow:

| Tier | Subject prefix | Created by | Purpose | Pre-commit hooks? |
|---|---|---|---|---|
| Checkpoint | `wip(claude): <ts> — <stat>` | `hooks/auto-commit.sh` | Don't lose work mid-session | **Skipped** (`--no-verify`) |
| Clean | conventional / project style | `/squash`, or the user manually | Reviewable history, push targets | **Run** |

Never confuse the two. Checkpoint commits exist to be deleted. Clean commits are the actual record.

## Commit messages (clean tier)

**Default style:** Conventional Commits.

```
<type>(<optional scope>): <subject>

<optional body — wrap at 72>

<optional footer: BREAKING CHANGE, Refs, Co-Authored-By>
```

**Types** the user uses:
- `feat` — new user-visible behavior
- `fix` — bug fix
- `refactor` — internal restructuring with no behavior change
- `perf` — performance change
- `test` — tests only
- `docs` — documentation only
- `build` — build-system, deps, tooling
- `ci` — CI configuration
- `chore` — anything not above (housekeeping)
- `re` — reverse-engineering note / RE artifact
- `poc` — exploit-development PoC progress
- `writeup` — security writeup edits

**Subject rules:**
- Imperative mood. "Add parser" not "Added parser" or "Adds parser."
- ≤ 72 chars including the prefix. Most should land at 50.
- No trailing period.
- Lowercase after the colon, unless the first word is a proper noun or acronym (`fix(ssl): handle X.509...`).

**Body rules** (skip the body if the subject is self-evident):
- Explain *why*, not *what*. The diff says what.
- Note risk, alternatives considered, and anything the reviewer might wonder.
- Reference issues / CVEs / ADRs by id, not by URL: `Refs: #142`, `Refs: ADR-0007`, `Refs: CVE-2024-12345`.

**Footer rules:**
- `BREAKING CHANGE: <description>` on a line by itself if the change is breaking.
- `Co-Authored-By:` lines for genuine pair-work — not for tooling.

If the existing repo uses a different convention, **mirror it.** Run `git log -n 30 --pretty='%s'` and match.

## Branch naming

Format: `<type>/<short-kebab-description>` or `<type>/<ticket>-<short-kebab>`.

| Prefix | When |
|---|---|
| `feat/` | new feature work |
| `fix/` | bug fix |
| `refactor/` | non-behavior-changing internal cleanup |
| `re/` | reverse-engineering work on a target |
| `poc/` | exploit-development PoC |
| `writeup/` | report writing |
| `spike/` | exploratory throwaway — not expected to merge |
| `release/` | release prep |

Keep names short — under ~40 chars. Avoid dates in branch names; the commit metadata already has them.

## When to amend vs new commit

| Situation | Action |
|---|---|
| Caught a typo in the *very last* commit, and it has not been pushed | `git commit --amend --no-edit` (or with edit if message was wrong) |
| Forgot to stage a file, and the commit has not been pushed | `git add <file> && git commit --amend --no-edit` |
| Anything else | **New commit.** |
| Pushed already | **Always new commit, never amend.** Amending pushed commits requires force-push and breaks anyone else's checkout. |

The default is **new commit**. Amend is the rare exception.

## When to squash vs not

Squash:
- The `wip(claude):` checkpoint stream → run `/squash`.
- A messy local feature branch with many "fix typo / oops / wip" commits → squash before merge.
- A fixup commit that addresses review feedback on its parent → use `git commit --fixup=<sha>` then `git rebase -i --autosquash`.

Don't squash:
- A series of *intentional, logically distinct* commits. Reviewability beats tidiness.
- Anything already on a shared / pushed branch.
- Across merge commits — don't flatten merge topology unless the user asks.

## Force-push policy

- **Never** to `main`, `master`, `develop`, `release/*`, or any branch with an open PR that someone else has reviewed.
- **Allowed** on personal feature branches that you own, *with* `--force-with-lease` (never bare `--force`).
- The `/squash` command intentionally leaves pushing to the user — it never pushes itself.
- If the user asks for a force-push, confirm the branch and remind them of `--force-with-lease`.

## Tagging

- Releases: `v<MAJOR>.<MINOR>.<PATCH>`, signed if the project signs (`git tag -s`).
- Pre-releases: `v1.2.3-rc.1`, `v1.2.3-beta.2`.
- Safety tags from `/squash`: `claude-presquash-<ts>`. These are local, never pushed. Delete with `git tag -d` once you're confident in the squashed result. Don't push them.
- Never re-use a tag name. If a release has to be redone, bump the version.

## Bisect

When debugging a regression: `git bisect start && git bisect bad && git bisect good <known-good>`. Provide a script with `git bisect run <script>` for any non-trivial bisect — manual bisects on long ranges waste time. The script must exit 0 for "good", non-zero for "bad", and 125 for "skip / can't test."

## Things to actively avoid

- `git push --force` (use `--force-with-lease` if you must).
- `git reset --hard` without first stashing or tagging the current state.
- `git rebase -i` on commits that have been pushed and reviewed.
- `git commit -am` — it skips the staging review step, which is where you catch unintended files.
- `git add .` from the project root — prefer naming files. `.env`, build artifacts, and editor swap files love to sneak in.
- Committing generated files, lockfiles excepted (lockfiles *should* be committed).
- Committing secrets, API keys, internal hostnames, private CA material. If it happens, treat it as an incident: rotate first, then `git filter-repo` second.

## Interaction with the auto-commit hook

- The hook runs after **every Claude turn** that touches files. Expect a lot of wip commits.
- Don't manually `git commit` in the middle of a turn unless the user asks — the hook handles it.
- If you need to make an *intentional* milestone commit mid-task, that's fine, but say so explicitly so the user can distinguish it from a wip checkpoint.
- Before running `/squash`, the working tree must be clean. If you have uncommitted changes when `/squash` is invoked, the command will refuse — let the hook (or a manual commit) capture them first.
