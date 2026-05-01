---
description: Create the next-numbered Architecture Decision Record under `docs/adr/`, pre-populated with the user's ADR template.
argument-hint: <short title>   e.g. "use SQLite for local cache"
allowed-tools: Bash(ls:*), Bash(mkdir:*), Bash(test:*), Bash(date:*), Read, Write
---

# /adr — create a new ADR

Pull in `project-documentation`. ADRs live at `docs/adr/NNNN-kebab-title.md`.

## Procedure

1. **Read the title.** `$ARGUMENTS` is the title (e.g. "use SQLite for local cache"). If empty, ask the user. Don't make one up.

2. **Find the right directory.**
   - Default: `docs/adr/`.
   - If the project keeps ADRs elsewhere (`adr/` at root, or `docs/adrs/`), match what's already there.
   - Create the directory if missing. If creating fresh, also create the meta-ADR (`0001-record-architecture-decisions.md`) using the same template, with status `accepted`, before this new one.

3. **Compute the next number.** List `<adr-dir>/*.md`, parse the leading 4-digit numbers, take `max + 1`. Format as 4 zero-padded digits. If there are gaps, **don't fill them** — keep numbering monotonic.

4. **Compute the slug.** Lowercase the title, replace runs of non-alphanumeric chars with `-`, strip leading/trailing `-`, cap at ~60 chars. Filename: `<NNNN>-<slug>.md`.

5. **Write the file** with this template (do not deviate — the format is part of the user's convention):

   ```markdown
   # ADR <NNNN>: <Title>

   **Status:** proposed
   **Date:** <YYYY-MM-DD>

   ## Context

   <!-- What is the issue we're addressing? What forces are at play? -->

   ## Decision

   <!-- What we decided. -->

   ## Consequences

   <!-- What becomes easier or harder because of this decision. -->

   ## Alternatives considered

   <!-- What else we looked at, and why we didn't pick it. -->
   ```

6. **Refuse to overwrite.** If `<NNNN>-<slug>.md` already exists, stop.

7. **Print the path** so the user can open it.

## Rules

- Status is **always** `proposed` for a new ADR. The user moves it to `accepted` (or `superseded by ADR XXXX`) when the decision is real.
- Use today's UTC date (`date -u +%Y-%m-%d`).
- **Never renumber existing ADRs.** Even if there are gaps. Even if one was deleted. ADR numbers are stable references.
- Don't pre-fill Context / Decision / Consequences with guesses. The user writes the substance.
- Don't commit; auto-commit hook handles it.
