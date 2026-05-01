---
description: Generate a STRIDE-style threat model against the current diff (or a named feature/component), to a markdown file.
argument-hint: [feature or component name — used as the title; defaults to "current diff"]
allowed-tools: Bash(git:*), Bash(test:*), Bash(date:*), Read, Write, Glob, Grep
---

# /threat-model — STRIDE pass on a feature

This is a *prompted* threat model: the command sets up the structure and pre-fills what it can from the diff, then asks the user to confirm or correct. It does not pretend to be a substitute for a human security review.

## Procedure

1. **Establish scope.**
   - If `$ARGUMENTS` is non-empty, treat it as the feature/component name.
   - Else use the current branch's diff against its upstream (or `main`) as the scope. Title: `<branch> changes`.
   - If the diff is empty *and* `$ARGUMENTS` is empty, stop and ask the user what to model.

2. **Find an output location.**
   - If `docs/threat-models/` exists, use it.
   - Else if `docs/` exists, create `docs/threat-models/`.
   - Else create `threat-models/` at the project root.
   - File: `<dir>/<YYYY-MM-DD>-<slug>.md`.

3. **Pre-fill scope from the diff.** For each changed file, briefly note its role: parser? authentication path? FFI boundary? UI? Test? Skip files that are clearly noise (lockfiles, generated). This becomes the **In scope** section.

4. **Template:**

   ```markdown
   # Threat Model: <title>

   **Date:** <YYYY-MM-DD>
   **Author:** <user>
   **Status:** draft

   ## In scope
   <!-- bulleted list of components / files / interfaces this model covers -->

   ## Out of scope
   <!-- explicit non-goals — what we are not modeling here, and why -->

   ## Assets
   <!-- what we are protecting: data, capabilities, availability -->

   ## Trust boundaries
   <!-- where data crosses from one trust domain to another -->

   ## Adversary model
   <!-- who the attacker is, what they can do, what they know -->

   ## STRIDE

   ### Spoofing
   <!-- can someone impersonate a user/service/component? -->

   ### Tampering
   <!-- can someone modify data in transit, at rest, or in memory? -->

   ### Repudiation
   <!-- can someone deny having performed an action? what audit trail exists? -->

   ### Information disclosure
   <!-- can someone read what they shouldn't? side channels? error messages? -->

   ### Denial of service
   <!-- can someone exhaust resources, lock out users, crash the system? -->

   ### Elevation of privilege
   <!-- can someone gain more privilege than they should have? -->

   ## Findings

   | # | Category | Description | Severity | Mitigation | Owner |
   |---|----------|-------------|----------|------------|-------|
   | 1 |          |             |          |            |       |

   ## Open questions
   <!-- things the model is uncertain about and needs human input -->

   ## Out-of-scope risks (acknowledged)
   <!-- things we know are issues but are deliberately not addressing here -->
   ```

5. **Pre-populate where evidence allows.**
   - From file contents, point at trust boundaries you can identify (network handlers, deserializers, FFI calls, syscall wrappers, anything reading user input).
   - Suggest STRIDE categories that are likely in play. Don't fabricate findings — write `<!-- candidate: ... -->` placeholders, not invented vulns.
   - Cross-reference `security-research-workflow` if the project is research-flavored, and `protocol-and-format-reversing` if the change touches a parser.

6. **Print the path** so the user can open it.

## Rules

- **Don't claim a finding without evidence.** "Likely candidate" placeholders are fine; assertion-grade entries are not, unless you can quote the file:line that demonstrates the issue.
- **Don't conflate severity with confidence.** Severity is "if this were real, how bad?"; confidence is "do we know it's real?". Capture both if you flag a candidate finding.
- **Don't replace an existing threat model.** If the file exists, refuse and ask whether to create a versioned successor (`<basename>-v2.md`) or amend in place.
- Don't commit; auto-commit handles it.
