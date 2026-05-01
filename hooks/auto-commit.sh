#!/usr/bin/env bash
# Stop-hook: snapshot the working tree as a `wip(claude):` commit after every
# Claude turn. The commits are intentionally noisy and intended to be squashed
# later via the /squash slash command.
#
# Design rules:
#   * Never block. This hook must always exit 0; a Claude turn ending should
#     not be derailed by a commit failure.
#   * Never push.
#   * Never run hooks (--no-verify) — these are checkpoints, not real commits.
#     The squash step is where pre-commit hooks should run, on the clean
#     consolidated commit.
#   * Never touch a repo that is mid-rebase / mid-merge / mid-bisect.
#   * Skip when the only changes are inside .git/, or when the index is empty
#     after staging (e.g., everything is gitignored).
#
# Tunables via env (set in settings.json `env` if desired):
#   CLAUDE_AUTO_COMMIT_DISABLE=1   skip entirely
#   CLAUDE_AUTO_COMMIT_PREFIX      override the subject prefix (default wip(claude))

set -u

# Always succeed. Even if something below explodes, don't take the turn down.
trap 'exit 0' ERR

# Drain stdin (Claude Code passes hook context as JSON). We only need cwd.
input="$(cat 2>/dev/null || true)"

# Parse cwd out of the JSON without requiring jq if it's not installed.
cwd=""
if command -v jq >/dev/null 2>&1; then
    cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null || true)"
fi
if [ -z "$cwd" ]; then
    cwd="$(printf '%s' "$input" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
fi
cwd="${cwd:-$PWD}"

cd "$cwd" 2>/dev/null || exit 0

[ "${CLAUDE_AUTO_COMMIT_DISABLE:-0}" = "1" ] && exit 0

# Must be inside a git working tree.
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

# Don't auto-commit on top of an in-progress rebase / merge / cherry-pick / bisect.
git_dir="$(git rev-parse --git-dir 2>/dev/null)" || exit 0
for marker in rebase-merge rebase-apply MERGE_HEAD CHERRY_PICK_HEAD BISECT_LOG REVERT_HEAD; do
    if [ -e "$git_dir/$marker" ]; then exit 0; fi
done

# Bail early if there's nothing to commit (no tracked changes and no untracked
# files that would be staged by `git add -A`).
if git diff --quiet \
   && git diff --cached --quiet \
   && [ -z "$(git ls-files --others --exclude-standard 2>/dev/null)" ]; then
    exit 0
fi

prefix="${CLAUDE_AUTO_COMMIT_PREFIX:-wip(claude)}"
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Stage everything respecting .gitignore. -A picks up adds, mods, and deletes.
git add -A 2>/dev/null || exit 0

# After staging, the index might still be empty (e.g., all changes were
# gitignored). Re-check.
if git diff --cached --quiet; then
    exit 0
fi

stat_line="$(git diff --cached --shortstat 2>/dev/null | sed 's/^[[:space:]]*//')"
[ -z "$stat_line" ] && stat_line="changes"

git -c commit.gpgsign=false commit \
    --no-verify \
    --allow-empty-message \
    -m "${prefix}: ${ts} — ${stat_line}" \
    >/dev/null 2>&1 || true

exit 0
