---
name: project-documentation
description: The user's preferred documentation layout and conventions for software projects — README, Architecture and Design.md, user guides, developer guides, ADRs, and inline doc style. Use this skill whenever creating a new project, adding a documentation file, scaffolding docs, writing a design doc, or when the user asks about documentation structure. Trigger even when the user just says "document this" or "set up the docs" without naming specific files.
---

# Project Documentation

The user cares deeply about documentation. A project without a clear documentation story is incomplete, regardless of how good the code is.

## The expected layout

For any non-trivial project (more than a single-file script), the documentation lives in a top-level `docs/` directory:

```
project-root/
├── README.md
├── docs/
│   ├── Architecture and Design.md
│   ├── user-guide/
│   │   ├── index.md
│   │   ├── installation.md
│   │   ├── getting-started.md
│   │   └── <feature-specific guides>.md
│   ├── developer-guide/
│   │   ├── index.md
│   │   ├── setup.md
│   │   ├── building.md
│   │   ├── testing.md
│   │   ├── contributing.md
│   │   └── <subsystem deep-dives>.md
│   ├── adr/
│   │   ├── 0001-record-architecture-decisions.md
│   │   └── 0002-...
│   └── diagrams/
│       └── <generated or source files for architecture diagrams>
└── ...
```

Use this exact structure unless the project already uses something different — in which case match what's there.

## README.md

The README is the front door. It is **not** the place for the full story. It should answer, in this order:

1. **What is this?** One paragraph, plain language. What problem does it solve, for whom.
2. **Status.** Stable / beta / experimental. Build status badge if there's CI.
3. **Quick install / quick start.** The shortest path from "git clone" to "it works on my machine."
4. **Where to go next.** Links to `docs/user-guide/`, `docs/developer-guide/`, `docs/Architecture and Design.md`.
5. **License.**

Keep it short. Anything longer than ~150 lines belongs in `docs/`.

## Architecture and Design.md

This is the document the user explicitly named. It lives at `docs/Architecture and Design.md` (yes, with the spaces and capitalization — that's the user's preference). It is the single source of truth for "why is this system shaped the way it is."

Required sections:

1. **Overview** — one or two paragraphs naming the system and its purpose.
2. **Goals and non-goals** — explicit. Non-goals are as important as goals.
3. **High-level architecture** — a diagram (ASCII or linked image from `docs/diagrams/`) showing the major components and how data flows between them.
4. **Components** — one subsection per major component. What it does, what it depends on, what depends on it. Internal interfaces.
5. **Data model** — schemas, important types, on-disk or on-wire formats.
6. **Key design decisions** — for each non-obvious choice, a short "we chose X over Y because Z." Link to the corresponding ADR if one exists.
7. **Operational concerns** — concurrency model, performance characteristics, failure modes, security considerations.
8. **Open questions / known limitations** — what we deliberately haven't solved yet.

Diagrams are required for any system with more than ~3 components. ASCII art is fine for simple cases; for anything more complex, prefer Mermaid (renders on GitHub) or D2, with the source committed to `docs/diagrams/`.

## User guide

Audience: someone who wants to *use* the project as-is, without modifying it.

Conventions:
- Task-oriented. Each page answers "how do I do X?"
- Examples are runnable. Copy-paste should work.
- Versioned where practical — note which version(s) the guide applies to.
- `index.md` is a table of contents, not prose.

Standard pages:
- `installation.md` — package manager instructions, building from source if relevant, verifying the install.
- `getting-started.md` — a 10-minute walkthrough of the most common use case.
- Feature-specific guides as needed.

## Developer guide

Audience: someone who wants to *contribute to* or *extend* the project.

Conventions:
- Assumes the reader has read `Architecture and Design.md`.
- Concrete: actual commands, actual file paths.
- Updated when the build/test/release process changes.

Standard pages:
- `setup.md` — dev environment, required tools, recommended editor config.
- `building.md` — build commands, build-time options, debugging the build.
- `testing.md` — how to run unit / integration / e2e tests, how to add a new test, how the CI runs them.
- `contributing.md` — branching model, commit conventions, code review process, release process.
- Subsystem deep-dives as needed (e.g., `developer-guide/parser-internals.md`).

## ADRs (Architecture Decision Records)

For decisions that are non-obvious, costly to reverse, or likely to be re-litigated by a future contributor: write an ADR.

Format (per file in `docs/adr/`):

```markdown
# ADR NNNN: <Short Title>

**Status:** proposed | accepted | superseded by ADR XXXX
**Date:** YYYY-MM-DD

## Context
What is the issue we're addressing? What forces are at play?

## Decision
What we decided.

## Consequences
What becomes easier or harder because of this decision.

## Alternatives considered
What else we looked at, and why we didn't pick it.
```

Number them sequentially (`0001-`, `0002-`, ...) and never renumber. Superseded ADRs stay in place; the new one references them.

The very first ADR, `0001-record-architecture-decisions.md`, is the meta-ADR explaining that this project uses ADRs.

## Inline documentation

- **Public APIs**: every public function, class, type has a docstring/doc-comment. State what it does, what its args mean, what it returns, what it raises.
- **Non-obvious internals**: comment the *why*, not the *what*. The code says what; the comment says why.
- **Invariants and assumptions**: name them at the top of the function or near the relevant block.
- **TODOs**: include a name and a date or issue reference. `# TODO(alex, 2025-11): switch to async once X lands` not `# TODO: fix this`.

Language-specific style — Python docstrings (Google or NumPy style, match what's there), Doxygen for C/C++, doc comments for Zig — see `code-style-preferences`.

## When to scaffold

If the user is starting a new project, proactively scaffold the docs structure above as part of the initial commit. Don't wait to be asked. It is much easier to fill in `docs/Architecture and Design.md` while the design is fresh than to reconstruct it later.

If the user is working in an existing project that lacks this structure, **don't** silently introduce it. Ask first — the project may have intentional reasons for its current layout.
