---
description: Create a new function note in `notes/functions/` following the RE convention from `security-research-workflow`.
argument-hint: <hex-address> <name>   e.g. 0x401a30 parse_header
allowed-tools: Bash(mkdir:*), Bash(test:*), Bash(date:*), Read, Write
---

# /re-note — new function note

Pull in `security-research-workflow`. Function notes live at `notes/functions/0xADDR-name.md`.

## Procedure

1. **Parse `$ARGUMENTS`.**
   - First token: hex address. Accept with or without `0x` prefix; canonicalize to `0xLOWER`.
   - Remaining tokens: function name (snake_case preferred; if user gave camelCase or PascalCase, keep as-is).
   - If `$ARGUMENTS` is empty or malformed, ask the user for both pieces. Don't guess.

2. **File path.** `notes/functions/<addr>-<name>.md`. Create `notes/functions/` if it doesn't exist.

3. **Refuse to overwrite.** If the file already exists, stop and ask. Offer to *open it for editing* instead of replacing it.

4. **Template:**

   ```markdown
   # <addr> — <name>

   **Address:** <addr>
   **Module:** <!-- module name / binary -->
   **Symbol:** <!-- "stripped" / actual symbol if known -->
   **Calling convention:** <!-- sysv-amd64 / cdecl / fastcall / etc. -->
   **First seen:** <YYYY-MM-DD>

   ## Signature

   ```c
   <return-type> <name>(<args>);
   ```

   ## What it does

   <!-- One paragraph. -->

   ## Arguments

   | # | Type | Name | Notes |
   |---|------|------|-------|
   |   |      |      |       |

   ## Return value

   <!-- What it returns and what each value means. -->

   ## Side effects

   <!-- Globals touched, state mutated, syscalls made. -->

   ## Callers

   - <!-- addr — caller name -->

   ## Callees

   - <!-- addr — callee name -->

   ## Anomalies

   <!-- Anti-debug, obfuscation, suspicious constants, anything the reader should know. -->

   ## Annotated disassembly

   ```asm
   <!-- paste relevant snippet here, with comments explaining each block -->
   ```

   ## Open questions

   - [ ] <!-- ... -->
   ```

5. **Append to timeline.** Add a one-line entry to `notes/timeline.md` if it exists: `- <YYYY-MM-DD> note opened for <addr> <name>`.

6. Don't commit. The auto-commit hook handles it.

## Rules

- Use today's date in `**First seen:**` and the timeline. Read it from `date -u +%Y-%m-%d`.
- Don't invent a calling convention, return type, or argument count from nothing. Leave placeholders.
- The address goes in the filename **and** the H1 — both are search hooks for future-you.
