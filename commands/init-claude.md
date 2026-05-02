---
description: Initialize a project-level CLAUDE.md from the template, with light substitutions.
argument-hint: [optional one-line project description]
allowed-tools: Bash(git:*), Bash(test:*), Read, Write, Edit
---

# /init-claude — bootstrap a project-level CLAUDE.md

The user's **global** `CLAUDE.md` (this template's top-level one) covers operating principles, skills, and slash commands. A **project-level** `CLAUDE.md` adds project-specific context that overrides or extends the global rules: build commands, domain glossary, repo-specific conventions, ongoing initiatives, deploy/test commands, etc.

This command bootstraps that file from `templates/CLAUDE.md.tpl`.

Argument: `$ARGUMENTS` — optional one-line project description. If empty, leave the placeholder for the user to fill in.

## Procedure

1. **Refuse to clobber.** If `./CLAUDE.md` already exists at the project root, **stop and tell the user**. Suggest `/init-claude` is for new projects; for existing ones, edit by hand or ask the user how to proceed.

2. **Detect project context** in parallel:
   - Project name: basename of the cwd, or the `name` field of `package.json` / `pyproject.toml` / `Cargo.toml` if present.
   - Primary language: detect from common manifest files (`pyproject.toml` → Python, `Cargo.toml` → Rust, `go.mod` → Go, `CMakeLists.txt` → C/C++, `build.zig` → Zig, `package.json` → JS/TS, `Makefile` alone → C-ish). If unclear, ask.
   - Build / test commands: scan top-level scripts, `Makefile` targets, `package.json` scripts, `pyproject.toml [tool.poetry.scripts]` etc. Extract the obvious "build", "test", "lint" commands. **Do not invent** — if there's no obvious one, leave the placeholder blank.
   - Git remote URL (`git remote get-url origin 2>/dev/null`) for context, optional.

3. **Render `templates/CLAUDE.md.tpl`** with substitutions:
   - `{{PROJECT}}` — project name.
   - `{{DESCRIPTION}}` — `$ARGUMENTS` if given, else `<one-line description here>`.
   - `{{LANGUAGE}}` — detected primary language, else `<primary language>`.
   - `{{BUILD_CMD}}` — detected build command, else `<build command>`.
   - `{{TEST_CMD}}` — detected test command, else `<test command>`.
   - `{{LINT_CMD}}` — detected lint command, else `<lint command>`.
   - `{{REMOTE}}` — git remote URL, else `<no git remote>`.

4. **Write the rendered content** to `./CLAUDE.md`.

5. **Confirm** with a one-line acknowledgement plus a TODO list for the user: which placeholders are still `<...>` and need their attention. Surface assumptions inline (e.g., "I assumed the build command is `make` based on the Makefile — change if wrong").

## Don't

- Don't fabricate build/test/lint commands. Leave placeholders blank if unsure — a wrong command in CLAUDE.md is worse than a missing one.
- Don't overwrite an existing `CLAUDE.md`. Ever.
- Don't add per-project skills or commands here — those go in `.claude/skills/` and `.claude/commands/` at the project level, not the CLAUDE.md.
- Don't echo the global `CLAUDE.md`'s operating principles into the project file. The global rules are loaded automatically; the project file is for what's *different or additional*.

## After init

Suggest the user consider, depending on the project type:

- For a security research engagement: also run `/poc` and `/timeline init` to scaffold the research artifacts.
- For a production codebase: `/scaffold-docs` to drop the user's preferred `docs/` tree.
- Confirm `.claude/logs/` is in `.gitignore` if they don't want the command log committed.
