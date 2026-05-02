# {{PROJECT}}

{{DESCRIPTION}}

## Project context

- **Primary language**: {{LANGUAGE}}
- **Remote**: {{REMOTE}}

## Build / test / lint

Run these from the project root unless otherwise noted.

- **Build**: `{{BUILD_CMD}}`
- **Test**: `{{TEST_CMD}}`
- **Lint**: `{{LINT_CMD}}`

If a command above is `<...>`, fill it in or delete the line — Claude treats committed CLAUDE.md content as authoritative and will follow it literally.

## Project-specific conventions

<!--
Add things that **differ from or extend** the user's global CLAUDE.md.
Examples:
- Domain glossary / acronyms specific to this codebase.
- File-layout rules (`src/` vs `lib/`, where tests live, etc.).
- Code style overrides (e.g., this project uses tabs even though the user prefers spaces).
- Performance-sensitive paths and the bar they need to clear.
- Database / external-service URLs for dev vs prod.
- Branch naming conventions if they differ from the global rule.
- Domain-specific testing rules ("integration tests must hit the real Postgres, not pgmock").

Delete this comment block once you've added real content.
-->

## Ongoing initiatives

<!--
Track active migrations, refactors, deprecations, or feature flags. Example:

- **Auth middleware rewrite** — replacing legacy session-token storage to meet
  compliance requirements. Touching auth code? See `docs/adr/0007-auth-rewrite.md`.
- **Postgres 14 → 16 migration** — in flight; new code should use the new JSONB
  helpers in `src/db/jsonb.py`, not the deprecated ones in `src/db/legacy.py`.

Delete this comment block once you've added real content (or remove the section).
-->

## Useful commands beyond build/test/lint

<!--
- `make watch` — file-watching dev loop.
- `scripts/run-local.sh` — spin up local stack (DB + redis + app).
- `pytest -k <pattern>` — run a subset of tests; CI uses the full suite.

Delete this comment block once filled in.
-->

## What's out of scope for Claude in this repo

<!--
- Don't touch `vendored/`. It's a checked-in dependency snapshot.
- Don't run schema migrations. Surface the SQL change; the user runs migrations.
- Don't push or open PRs from this assistant unless explicitly told.

Delete this comment block once filled in.
-->
