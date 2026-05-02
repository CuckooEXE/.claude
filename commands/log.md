---
description: Manually append an entry to the research command log (backfill or free-form note).
argument-hint: [reason / freeform note — what happened, what you learned, or which command to backfill]
allowed-tools: Bash(jq:*), Bash(git:*), Bash(date:*), Bash(mkdir:*), Bash(test:*), Bash(printf:*), Read
---

# /log — manual append to the research log

The `PostToolUse` hook (`hooks/log-interesting-commands.sh`) captures most interesting Bash calls automatically. This command is the manual escape hatch.

Use it when:

- You ran a command earlier in the conversation **without** the `[log]` marker and now realize it should be captured.
- You want to log a **finding, hypothesis, or screenshot reference** that isn't a command at all.
- The user explicitly asks you to log something.

Argument: `$ARGUMENTS` — free-form text. Treat as the reason / note body.

## Procedure

1. **Resolve context** in parallel:
   - `date -u +%Y-%m-%dT%H:%M:%SZ` for the timestamp.
   - `git rev-parse --abbrev-ref HEAD 2>/dev/null` for branch (best-effort).
   - `git rev-parse --short HEAD 2>/dev/null` for commit (best-effort).
   - `pwd` for cwd.

2. **Decide what kind of entry this is**:
   - **Backfill of a specific recent command**: scan back through this conversation's tool calls. If `$ARGUMENTS` clearly references one (e.g., "log that nm I just ran" or it includes a command snippet), include the literal `cmd`, `exit_code` if known, and the (truncated) `stdout` you observed. Mark `trigger: "manual-backfill"`.
   - **Free-form note** (no specific command): include only the `note` field with the user's text and your context. Mark `trigger: "manual-note"`.
   - If ambiguous, ask the user which one they want.

3. **Append to `.claude/logs/commands.jsonl`** using `jq -cn` so escaping is correct:

   ```bash
   mkdir -p .claude/logs
   jq -cn \
      --arg ts "$ts" \
      --arg cwd "$cwd" \
      --arg branch "$branch" \
      --arg trigger "manual-backfill" \
      --arg reason "$reason" \
      --arg cmd "$cmd" \
      --arg stdout "$stdout" \
      '{ts:$ts, cwd:$cwd, branch:$branch, trigger:$trigger, reason:$reason, cmd:$cmd, stdout:$stdout}' \
      >> .claude/logs/commands.jsonl
   ```

   For free-form notes, swap `cmd`/`stdout` for a single `note` field.

4. **Mirror to `notes/timeline.md` if it exists**:
   - Format the same way the hook does: a `### <ts> — <reason>` heading, a metadata bullet, and `<details>`-wrapped output blocks if applicable.
   - Truncate output to ~40 lines / 4 KB to match the hook.
   - If `notes/timeline.md` does **not** exist, do not create it. Suggest `/timeline init` if the user wants the human-readable mirror.

5. **Confirm** with a one-line acknowledgement: which file(s) you appended to and the entry's reason.

## Don't

- Don't backfill more than the most recent few commands without the user asking. This is an escape hatch, not a transcript dumper.
- Don't write secrets to the log (real creds, session tokens, internal hostnames not on the engagement scope). If the captured output may contain any, **sanitize first or ask**.
- Don't fabricate `cmd` or `stdout` values. If you can't recall the literal command/output, mark the entry as a free-form note instead.
- Don't create `notes/timeline.md` from this command — that's `/timeline`'s job.

## Examples

- `/log forgot to mark the readelf -a I ran on libauth.so — it confirmed RELRO is partial, not full` — backfill referencing a recent `readelf`.
- `/log hypothesis: the parse_header function trusts the length field without bounds-checking. need to verify with a crafted input.` — free-form research note.
- `/log screenshot saved to artifacts/heap-state-after-uaf.png` — pointer to an artifact.
