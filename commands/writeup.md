---
description: Create or extend `WRITEUP.md` for the current security research project, using the section template from `security-research-workflow`.
argument-hint: [optional title hint]
allowed-tools: Bash(test:*), Bash(ls:*), Bash(date:*), Bash(git:*), Read, Write, Edit
---

# /writeup — scaffold or extend the security writeup

Pull in `security-research-workflow` for the canonical structure.

## Procedure

1. **Locate.** If `WRITEUP.md` exists in the current directory, work with it. Otherwise create it at the project root.

2. **Title.** Use `$ARGUMENTS` as the title hint if provided; otherwise ask the user for a one-line title (target + bug class — e.g., "Acme Router CVE-2025-XXXX: stack overflow in `parse_lan_request`").

3. **Sections to ensure exist** (don't duplicate; if already present, skip):

   ```markdown
   # <title>

   **Target:** <product> <version>
   **Tested on:** <OS, kernel, libc>
   **Mitigations:** <ASLR / NX / CFI / CET state>
   **Author:** <name>
   **Date:** <YYYY-MM-DD>
   **Status:** draft

   ## Summary
   <!-- TL;DR. One paragraph: bug, capability, why it matters. -->

   ## Background
   <!-- What is the target, what threat model applies, what mitigations are in play. -->

   ## Vulnerability
   <!-- The technical bug. Code excerpt with file/line. Why it's a bug. -->

   ## Trigger
   <!-- Minimal input that demonstrates the bug. Often much smaller than the full exploit. -->

   ## Exploitation
   <!-- Stage by stage from trigger to RCE / escalation. Match the stages to your PoC code. -->

   ## Impact
   <!-- What an attacker can actually do. Be specific. -->

   ## Mitigations / fix
   <!-- What the vendor should do, or did do. -->

   ## Timeline
   <!-- Disclosure dates, vendor responses. -->

   ## Appendix
   <!-- Full PoC, build/run instructions, screenshots, memory dumps. Diagrams welcome. -->
   ```

4. **Cross-link.** Add a line at the bottom of `README.md` (if it exists) pointing to `WRITEUP.md`. Don't silently rewrite README content beyond that one link.

5. **Diagrams placeholder.** Create `diagrams/` if it doesn't exist; mention it in the Appendix section. Diagram source must be committed (Mermaid or D2 are the user's defaults — see `project-documentation`).

## Rules

- If the writeup already has substantive content, **do not overwrite it.** Only add missing sections, and ask before reorganizing existing material.
- Pre-fill metadata fields with placeholders (`<TODO>`), never with guesses. Don't invent CVE IDs, dates, or library versions.
- Don't include real target identifiers (live IPs, customer names) without confirmation. Use `<redacted>` placeholders.
- Don't `git commit`. The auto-commit Stop hook will pick this up at end of turn.

## When the user is mid-writeup

If they ask for `/writeup` and `WRITEUP.md` already exists with content, default to a *gap analysis*: list which template sections are present, which are stub, and which are missing — then ask which they want to fill next. Don't just append boilerplate to a real document.
