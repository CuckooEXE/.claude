---
description: Recover from a /squash that went sideways by restoring HEAD to the safety tag the squash created.
argument-hint: [optional tag name; defaults to the most recent claude-presquash-* tag]
allowed-tools: Bash(git:*), Bash(test:*), Read
---

# /recover — undo the last /squash

`/squash` always creates a `claude-presquash-<timestamp>` tag before rewriting history. This command restores HEAD to that tag.

## Procedure

1. **Find the target tag.**
   - If `$ARGUMENTS` is non-empty, treat it as the tag name. Verify it exists with `git rev-parse --verify <tag>`.
   - Else: `git tag --list 'claude-presquash-*' --sort=-creatordate | head -1`. If none, stop and tell the user — there's no recovery point.

2. **Show what's about to happen.**
   ```
   git log --oneline <tag>..HEAD            # commits that will be lost
   git log --oneline HEAD..<tag>            # commits that will be restored
   git status --short                        # uncommitted changes
   ```
   Print this clearly. The user must see the consequences before confirming.

3. **Refuse on unsafe state.**
   - Working tree dirty (`git status --porcelain` non-empty)? Stop. Tell the user to commit or stash first. The auto-commit hook will checkpoint at the end of the next turn anyway.
   - In-progress rebase / merge / cherry-pick? Stop.
   - HEAD already points at the tag (no-op)? Stop and say so.

4. **Confirm.** Even in auto-mode, this is a `git reset --hard` — explicit confirmation required. Print:
   > Reset HEAD from `<current sha>` to `<tag sha>`. This will discard the commits listed above. Proceed? (yes/no)

   Do not proceed without an explicit "yes" / "y" / equivalent.

5. **Execute.**
   - Make a *second* safety tag at current HEAD before the reset: `git tag claude-prerecover-$(date -u +%Y%m%dT%H%M%SZ)`. Belt-and-suspenders — if the user changes their mind about *recovering*, they can undo this too.
   - `git reset --hard <tag>`.

6. **Report.**
   - Print the new `git log --oneline -n 5`.
   - Remind the user the recovery tag is in place if they need to undo: `git reset --hard <prerecover-tag>`.
   - Note that the original `claude-presquash-*` tag is **kept**, not deleted.

## Rules

- **`git reset --hard` is destructive.** Always require explicit confirmation. Always create a recovery tag of the *current* state first.
- **Never push.** Recovery is local. If the bad squash was already pushed, this command can't help — that's a "force-push or revert" decision that needs human judgment, not a slash command.
- **Never delete the safety tags automatically.** They cost nothing and they're insurance.
- If the tag list is dense (the user `/squash`-es often), default to the most recent and surface the others in case they meant to recover further back.
