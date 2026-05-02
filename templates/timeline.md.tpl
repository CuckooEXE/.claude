# Research timeline — {{PROJECT}}

Started: {{DATE}} on `{{BRANCH}}`.

This file is the human-readable mirror of the research log. The
`PostToolUse` hook (`hooks/log-interesting-commands.sh`) appends entries
here automatically when a Bash command is captured. Use `/log` for
manual backfill and `/timeline <note>` for free-form prose entries.

## How to read this file

- Sessions are delimited by `---` and a `## Session ...` header (added by the `SessionStart` hook).
- Each captured command is a `### <ts> — <reason>` heading with `<details>`-wrapped output.
- The full, untruncated record of every entry is in `.claude/logs/commands.jsonl`. Cross-reference by timestamp + session id.

## Target / scope

<!-- One paragraph: what is being researched, what version, on what platform.
     Pin the libc / kernel / firmware version here so it survives in the writeup. -->

## Open questions

<!-- A running list. Cross out as they're resolved. -->

---
