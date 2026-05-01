---
description: Drop the user's preferred `docs/` tree into the current project (README + Architecture and Design + user-guide + developer-guide + adr + diagrams).
argument-hint: [no arguments]
allowed-tools: Bash(mkdir:*), Bash(test:*), Bash(ls:*), Read, Write
---

# /scaffold-docs — drop the docs/ tree

Pull in `project-documentation` — its layout is the source of truth.

## Procedure

1. **Sanity-check the project.**
   - If `docs/` already exists with content beyond `index.md`, **stop** and ask whether to merge or skip. Don't silently overwrite a real docs tree.
   - If a `README.md` exists, **don't replace it**. Offer to add a "Where to go next" section pointing at `docs/`.

2. **Create the directories:**

   ```
   docs/
   ├── Architecture and Design.md      # note the spaces and capitalization
   ├── user-guide/
   │   ├── index.md
   │   ├── installation.md
   │   └── getting-started.md
   ├── developer-guide/
   │   ├── index.md
   │   ├── setup.md
   │   ├── building.md
   │   ├── testing.md
   │   └── contributing.md
   ├── adr/
   │   └── 0001-record-architecture-decisions.md
   └── diagrams/
       └── .gitkeep
   ```

3. **Populate templates** — each file gets a minimal skeleton, not a long template. The user fills the substance.

   - `docs/Architecture and Design.md` — H1 + H2 stubs for the required sections from `project-documentation` (Overview, Goals and non-goals, High-level architecture, Components, Data model, Key design decisions, Operational concerns, Open questions). Each section has a one-line `<!-- describe ... -->` comment.

   - `docs/user-guide/index.md` — table of contents listing `installation.md` and `getting-started.md`.
   - `docs/user-guide/installation.md` — H1 + a stub paragraph + `## From package manager`, `## From source`, `## Verifying the install`.
   - `docs/user-guide/getting-started.md` — H1 + 10-minute walkthrough placeholder.

   - `docs/developer-guide/index.md` — TOC + line saying "assumes you have read `Architecture and Design.md`".
   - `docs/developer-guide/setup.md` — required tools, recommended editor config (`.editorconfig`, language servers), how to bootstrap dev environment.
   - `docs/developer-guide/building.md` — build commands (placeholder), debug builds, release builds.
   - `docs/developer-guide/testing.md` — how to run unit / integration / e2e tests, how the CI runs them.
   - `docs/developer-guide/contributing.md` — branching model (link to `git-workflow` skill if applicable), commit conventions, code review process.

   - `docs/adr/0001-record-architecture-decisions.md` — the meta-ADR. Status `accepted`, today's date. Body explains the project will use ADRs for non-obvious / costly-to-reverse decisions, and where they live.

4. **README.md.** If it doesn't exist, create one with the structure from `project-documentation` (one-paragraph what-is-this, status, quick install, links to docs, license placeholder). If it does exist, leave it alone — only offer to add a `## Where to go next` section.

5. **Print the tree** of what was created.

## Rules

- **Don't fabricate content.** Every section is a stub the user fills. Don't invent a system architecture for them.
- **Use today's date** for the meta-ADR (`date -u +%Y-%m-%d`).
- **Don't introduce a doc generator** (mkdocs, Sphinx) without asking — bare markdown renders fine on GitHub and is the user's default.
- Don't commit; auto-commit hook handles it.
