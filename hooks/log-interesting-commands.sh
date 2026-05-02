#!/usr/bin/env bash
# PostToolUse hook for Bash: append a structured record to
# .claude/logs/commands.jsonl when a command is "interesting."
#
# Three-tier decision:
#   1. NEVER list (deny) — pure navigation / status noise. Drop silently.
#   2. ALWAYS list (allow) — tools where the trace is always worth keeping
#      (debuggers, dynamic instrumentation). Log unconditionally.
#   3. Claude decides (default off) — Claude opts in by prefixing the Bash
#      tool `description` with `[log]` or `[log: <reason>]`. The marker is
#      stripped before the entry is recorded.
#
# Never block. Always exit 0. The hook never aborts a turn.
#
# Tunables (env):
#   CLAUDE_CMDLOG_DISABLE=1            skip entirely
#   CLAUDE_CMDLOG_NEVER_REGEX=...      override deny regex (matches binary basename)
#   CLAUDE_CMDLOG_ALWAYS_REGEX=...     override allow regex (matches binary basename)
#   CLAUDE_CMDLOG_FILE=path            override JSONL output path
#   CLAUDE_CMDLOG_TIMELINE=path        override timeline.md path (mirror only if file exists)
#   CLAUDE_CMDLOG_MAX_BYTES=4096       per-stream byte cap in markdown timeline (JSONL is full)
#   CLAUDE_CMDLOG_MAX_LINES=40         per-stream line cap in markdown timeline

set -u
trap 'exit 0' ERR

[ "${CLAUDE_CMDLOG_DISABLE:-0}" = "1" ] && exit 0

# Need jq. Without it, silently no-op rather than risk a corrupt log.
command -v jq >/dev/null 2>&1 || exit 0

input="$(cat 2>/dev/null || true)"
[ -z "$input" ] && exit 0

# Only react to Bash PostToolUse.
event="$(printf '%s' "$input" | jq -r '.hook_event_name // empty')"
tool="$(printf '%s' "$input" | jq -r '.tool_name // empty')"
[ "$event" = "PostToolUse" ] || exit 0
[ "$tool" = "Bash" ] || exit 0

cwd="$(printf '%s' "$input" | jq -r '.cwd // empty')"
cwd="${cwd:-$PWD}"
cd "$cwd" 2>/dev/null || exit 0

cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty')"
desc="$(printf '%s' "$input" | jq -r '.tool_input.description // empty')"
[ -z "$cmd" ] && exit 0

stdout="$(printf '%s' "$input" | jq -r '.tool_response.stdout // .tool_response.output // empty')"
stderr="$(printf '%s' "$input" | jq -r '.tool_response.stderr // empty')"
exit_code="$(printf '%s' "$input" | jq -r '.tool_response.exit_code // .tool_response.exitCode // empty')"
session_id="$(printf '%s' "$input" | jq -r '.session_id // empty')"

# Identify the "first binary": skip leading VAR=value tokens and sudo/-flags.
first_binary="$(printf '%s' "$cmd" | awk '
    {
        i = 1
        while (i <= NF && $i ~ /^[A-Za-z_][A-Za-z0-9_]*=/) i++
        if (i <= NF && $i == "sudo") {
            i++
            while (i <= NF && $i ~ /^-/) i++
        }
        if (i <= NF) {
            tok = $i
            n = split(tok, parts, "/")
            print parts[n]
        }
    }
')"

never_regex="${CLAUDE_CMDLOG_NEVER_REGEX:-^(ls|pwd|cd|which|whoami|id|echo|printf|mkdir|touch|true|false|exit|clear|tput|stty|cat|head|tail|wc|sort|uniq|less|more|column|tee)$}"
always_regex="${CLAUDE_CMDLOG_ALWAYS_REGEX:-^(gdb|lldb|strace|ltrace|frida|frida-trace|rr|r2|rabin2|radare2|rasm2|rax2)$}"

# Parse [log] / [log: reason] marker.
desc_clean="$desc"
marker_present=0
marker_reason=""
re_with='^\[log:[[:space:]]*([^]]*)\][[:space:]]*(.*)$'
re_bare='^\[log\][[:space:]]*(.*)$'
if [[ "$desc" =~ $re_with ]]; then
    marker_present=1
    marker_reason="${BASH_REMATCH[1]}"
    desc_clean="${BASH_REMATCH[2]}"
elif [[ "$desc" =~ $re_bare ]]; then
    marker_present=1
    desc_clean="${BASH_REMATCH[1]}"
fi

# Decide: marker > always-list > drop.
should_log=0
trigger=""
if [ "$marker_present" = "1" ]; then
    should_log=1
    trigger="marker"
elif [ -n "$first_binary" ] && [[ "$first_binary" =~ $always_regex ]]; then
    should_log=1
    trigger="always"
elif [ -n "$first_binary" ] && [[ "$first_binary" =~ $never_regex ]]; then
    exit 0
fi
[ "$should_log" = "1" ] || exit 0

# Reason: explicit marker reason > cleaned description > auto-stub.
if [ -n "$marker_reason" ]; then
    reason="$marker_reason"
elif [ -n "$desc_clean" ]; then
    reason="$desc_clean"
elif [ "$trigger" = "always" ]; then
    reason="(always-log tool: ${first_binary})"
else
    reason="(no reason given)"
fi

ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
log_file="${CLAUDE_CMDLOG_FILE:-$cwd/.claude/logs/commands.jsonl}"
mkdir -p "$(dirname "$log_file")" 2>/dev/null || exit 0

jq -cn \
   --arg ts "$ts" \
   --arg session "$session_id" \
   --arg cwd "$cwd" \
   --arg branch "$branch" \
   --arg trigger "$trigger" \
   --arg reason "$reason" \
   --arg binary "$first_binary" \
   --arg cmd "$cmd" \
   --arg stdout "$stdout" \
   --arg stderr "$stderr" \
   --arg exit_code "$exit_code" \
   '{
      ts:$ts, session:$session, cwd:$cwd, branch:$branch,
      trigger:$trigger, reason:$reason, binary:$binary,
      cmd:$cmd, exit:$exit_code, stdout:$stdout, stderr:$stderr
    }' >> "$log_file" 2>/dev/null || true

# Optional human-readable mirror to notes/timeline.md (only if file exists).
timeline="${CLAUDE_CMDLOG_TIMELINE:-$cwd/notes/timeline.md}"
if [ -f "$timeline" ]; then
    max_lines="${CLAUDE_CMDLOG_MAX_LINES:-40}"
    max_bytes="${CLAUDE_CMDLOG_MAX_BYTES:-4096}"
    truncate_stream() {
        local s="$1"
        [ -z "$s" ] && return 0
        local out
        out="$(printf '%s' "$s" | head -c "$max_bytes" | head -n "$max_lines")"
        printf '%s' "$out"
        if [ "${#out}" -lt "${#s}" ]; then
            printf '\n... (truncated; full output in commands.jsonl) ...'
        fi
    }
    out_trunc="$(truncate_stream "$stdout")"
    err_trunc="$(truncate_stream "$stderr")"
    {
        printf '\n### %s — %s\n' "$ts" "$reason"
        printf -- '- **branch**: `%s`  **trigger**: %s  **exit**: %s\n' \
            "${branch:-?}" "$trigger" "${exit_code:-?}"
        printf -- '- **cmd**: `%s`\n' "$cmd"
        if [ -n "$out_trunc" ]; then
            printf '<details><summary>stdout</summary>\n\n```\n%s\n```\n</details>\n' "$out_trunc"
        fi
        if [ -n "$err_trunc" ]; then
            printf '<details><summary>stderr</summary>\n\n```\n%s\n```\n</details>\n' "$err_trunc"
        fi
    } >> "$timeline" 2>/dev/null || true
fi

exit 0
