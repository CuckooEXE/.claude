#!/usr/bin/env bash
# SessionStart hook: write a session breadcrumb to the research log.
#
# Fires only on `startup` and `resume` so the timeline isn't polluted by
# mid-session restarts (`clear`, `compact`).
#
# Never block. Always exit 0.
#
# Tunables (env):
#   CLAUDE_SESSIONLOG_DISABLE=1     skip entirely
#   CLAUDE_SESSIONLOG_FILE=path     sessions.jsonl path
#   CLAUDE_SESSIONLOG_TIMELINE=path timeline.md path (mirror only if file exists)

set -u
trap 'exit 0' ERR

[ "${CLAUDE_SESSIONLOG_DISABLE:-0}" = "1" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

input="$(cat 2>/dev/null || true)"
[ -z "$input" ] && exit 0

src="$(printf '%s' "$input" | jq -r '.source // empty')"
case "$src" in
    startup|resume) ;;
    *) exit 0 ;;
esac

session_id="$(printf '%s' "$input" | jq -r '.session_id // empty')"
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty')"
cwd="${cwd:-$PWD}"
cd "$cwd" 2>/dev/null || exit 0

ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
commit="$(git rev-parse --short HEAD 2>/dev/null || true)"

log_file="${CLAUDE_SESSIONLOG_FILE:-$cwd/.claude/logs/sessions.jsonl}"
mkdir -p "$(dirname "$log_file")" 2>/dev/null || exit 0

jq -cn \
   --arg ts "$ts" \
   --arg session "$session_id" \
   --arg src "$src" \
   --arg cwd "$cwd" \
   --arg branch "$branch" \
   --arg commit "$commit" \
   '{ts:$ts, session:$session, source:$src, cwd:$cwd, branch:$branch, commit:$commit}' \
   >> "$log_file" 2>/dev/null || true

timeline="${CLAUDE_SESSIONLOG_TIMELINE:-$cwd/notes/timeline.md}"
if [ -f "$timeline" ]; then
    {
        printf '\n---\n## Session %s @ %s\n' "$src" "$ts"
        printf -- '- branch: `%s` (`%s`)\n' "${branch:-?}" "${commit:-?}"
        printf -- '- cwd: `%s`\n' "$cwd"
        printf -- '- session: `%s`\n' "${session_id:-?}"
    } >> "$timeline" 2>/dev/null || true
fi

exit 0
