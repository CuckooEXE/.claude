---
description: Open, initialize, or append to the project's research timeline (notes/timeline.md).
argument-hint: [init | <free-form note to append>]
allowed-tools: Bash(mkdir:*), Bash(test:*), Bash(date:*), Bash(git:*), Read, Write, Edit
---

# /timeline — manage the project research timeline

`notes/timeline.md` is the human-readable mirror of the research log. The `PostToolUse` hook (`hooks/log-interesting-commands.sh`) and the `SessionStart` hook both append to it **only if it already exists** — so the user opts in by initializing the file once.

This command:
- Initializes the file if it doesn't exist (`/timeline init`).
- Appends a free-form note if given non-empty arguments.
- With no arguments, opens the file for the user (read it back to them with the most recent few entries).

Argument: `$ARGUMENTS` — see Procedure.

## Procedure

1. **Resolve `notes/timeline.md` path** under the current working directory. Determine whether it exists.

2. **Dispatch on `$ARGUMENTS`:**

   - **`init`** (or empty + file does not exist + user clearly wants to create):
     - If the file already exists, do **not** clobber. Read it back and tell the user it's already initialized.
     - Otherwise, create `notes/` if needed and write the template from `templates/timeline.md.tpl`. Substitute:
       - `{{PROJECT}}` — the basename of the cwd.
       - `{{DATE}}` — UTC date `YYYY-MM-DD`.
       - `{{BRANCH}}` — current git branch, or `(no git)`.
     - Append a first `## Session manual @ <ts>` heading so the file has at least one anchor.
     - Tell the user: file is created, future hook output will mirror to it automatically.

   - **Empty args + file exists**: read the last ~80 lines and present them. This is "show me where we are."

   - **Empty args + file does not exist**: tell the user the file isn't initialized and offer `/timeline init`.

   - **Anything else**: treat `$ARGUMENTS` as a free-form note. If the file does not exist, refuse and suggest `/timeline init` first. If it exists, append:

     ```
     
     ### <ts> — manual note
     - **branch**: `<branch>`  **trigger**: manual
     
     <the note body, verbatim>
     ```

     (One blank line before the heading. `<ts>` is `date -u +%Y-%m-%dT%H:%M:%SZ`.)

3. **Confirm** with a one-line acknowledgement of what you did and the file path.

## Don't

- Don't initialize automatically without the user asking — the file's existence is the opt-in signal for the hooks. Surprise-creating it would change hook behavior the user didn't request.
- Don't rewrite or reformat existing entries.
- Don't append commands' raw output through this command — that's the hook's job. Use this for prose notes, decisions, hypotheses, and headings that organize phases of work.

## See also

- `/log` — append a structured JSONL entry (with command + output) to `.claude/logs/commands.jsonl`. Backfills the machine-readable log.
- `templates/timeline.md.tpl` — the initialization template.
- `skills/command-logging/SKILL.md` — when and how the automated hook captures commands.
