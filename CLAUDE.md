# Global Instructions

This is the user's global `CLAUDE.md`. It applies to all projects unless a project-level `CLAUDE.md` overrides specific items.

## About the user

The user is a **senior software engineer** and a **security researcher** conducting authorized penetration tests. Treat them as an expert collaborator: skip basic explanations, don't hedge unnecessarily, and assume they want correctness over hand-holding.

Primary languages: **Python, C, x86 assembly, Zig, C++**. Also comfortable across the stack.

Common work modes:
- Building production software (libraries, tools, services)
- Reverse-engineering vendor binaries / hardware / firmware
- Exploit development for **authorized** security assessments — full proof-of-concept exploits intended for written reports
- Writing technical documentation, user guides, developer guides

## Operating principles (always on)

These are non-negotiable defaults. Skills below expand on them.

1. **Test-Driven Development by default.** Write or update tests *before or alongside* code changes. A change without a corresponding test is incomplete unless the user explicitly says otherwise.
2. **Defensive programming.** Check return values. Validate inputs at trust boundaries. Handle errors explicitly — never silently swallow them. Fail loud, fail early.
3. **Idiomatic code.** Write code the way the language's designers intend. Pythonic Python, modern C++, idiomatic Zig, clean ANSI/ISO C, AT&T or Intel syntax consistent with the surrounding asm. Don't paper over a language with another language's idioms.
4. **Read before you write.** Before editing a file, read it. Before adding a function, check whether one already exists. Before introducing a dependency, check what's already in the project.
5. **No fabrication.** If you don't know an API, a flag, a syscall number, or a struct layout — say so and look it up. Never guess at signatures, hex constants, or offsets.
6. **Match existing conventions.** Style, naming, structure, build system — match the project. The user's preferences (below) only apply to greenfield work or when explicitly invited to refactor.
7. **Plan, then execute.** For any non-trivial task, state the plan in 2–6 bullets before touching code. For trivial tasks (one-line fix, rename), just do it.
8. **Surface assumptions.** When making a judgment call, name it inline so the user can correct course early.
9. **Mark notable Bash calls for the log.** When a Bash command's output will inform a research decision or appear in a writeup, prefix the Bash tool's `description` with `[log]` or `[log: <reason>]`. The `PostToolUse` hook captures marked calls into `.claude/logs/commands.jsonl`. See `skills/command-logging/SKILL.md` for the decision rules — debuggers and dynamic-instrumentation tools are auto-logged; navigation noise is auto-skipped; everything else is your call.

## Skills available

Consult these skills when their topic comes up. They are lazy-loaded — the description tells you when to pull each one in.

**Engineering core (foundations):**
- `software-engineering-practices` — TDD workflow, defensive programming details, error handling, dependency hygiene, what "done" means for a code change
- `code-style-preferences` — language-specific preferences: Python (ABCs, pipx, type hints), C/C++ (Google Test, build conventions), Zig, x86 ASM
- `code-review` — checklist and tone for reviewing code, whether the user's or someone else's
- `project-documentation` — the user's preferred documentation layout: `Architecture and Design.md`, user guides, developer guides, ADRs, and README structure
- `git-workflow` — commit message style, branch naming, when to amend vs new commit, squash rules, force-push policy, integration with the auto-commit hook
- `build-systems` — modern CMake (target-based), Meson, Bazel, `build.zig`, plain Make, plus cross-compile and sanitizer toolchains
- `cli-tool-design` — CLI ergonomics, exit codes, stdin/stdout/stderr discipline, `--json` mode, pipx packaging
- `debugging-workflow` — gdb/lldb productivity, rr time-travel, sanitizer family (ASan/UBSan/MSan/TSan), core-dump triage, bisect
- `performance-analysis` — perf, flamegraphs, hyperfine, microbenchmarks, latency vs throughput, premature-optimization discipline

**Engineering depth:**
- `testing-strategy` — beyond TDD basics: test pyramid, fakes-vs-mocks, table-driven, property-based, snapshot, flake hunting, coverage as guardrail not goal
- `error-handling-strategies` — error models per language (exceptions, Result, error codes, Zig error unions), wrapping vs replacing, retryable vs terminal, panic vs recover discipline
- `concurrency-and-async` — model selection, GIL/asyncio/pthreads/atomics/Zig threads, memory orderings, deadlock/race/livelock/ABA, backpressure, cancellation
- `memory-management` — ownership rules per language, allocator selection, sanitizer family, the bug taxonomy, FFI lifetime discipline
- `refactoring` — when to refactor (and when not), under-tests discipline, technique catalog, Mikado method, strangler fig, refactor-PR hygiene
- `api-design` — surface minimization, signature discipline, error model, SemVer/CalVer, deprecation paths, Hyrum's law
- `dependency-management` — lockfiles, pinning strategy, supply-chain audit, vendoring, reproducible builds, update cadence
- `observability` — structured logging, metric type selection (counter/gauge/histogram), trace span hygiene, OTel, cardinality discipline, anti-patterns
- `language-interop` — FFI patterns, Python C-extension matrix (ctypes/cffi/Cython/pybind11/nanobind/PyO3), Zig `@cImport`, ABI discipline, GIL release, lifetimes across boundaries

**Security research:**
- `security-research-workflow` — conventions for exploit dev, PoC writeups, reverse engineering notes, and report-grade artifacts
- `protocol-and-format-reversing` — capture-then-grammar-then-parser flow, Kaitai/010/ImHex, Wireshark dissectors, scapy

**Tooling / process:**
- `command-logging` — when to flip the `[log]` marker on Bash calls so the `PostToolUse` hook captures the trace; how to phrase the reason

## Slash commands available

The `commands/` directory in this template ships these. Invoke with `/<name>`.

**Workflow / git:**
- `/squash` — consolidate the trailing `wip(claude):` checkpoints into clean commits
- `/recover` — restore HEAD from the safety tag `/squash` left behind
- `/scope` — read-only scope summary of the current change vs base
- `/dod` — definition-of-done audit (tests, linters, docs, hygiene)
- `/release-notes` — propose CHANGELOG entries from commits since the last tag

**Engineering scaffolding:**
- `/scaffold-docs` — drop the user's preferred `docs/` tree
- `/adr` — next-numbered ADR under `docs/adr/`
- `/test-first` — write the failing test, run it, confirm it fails for the right reason, then stop
- `/init-claude` — bootstrap a project-level `CLAUDE.md` from `templates/CLAUDE.md.tpl` (refuses to clobber an existing one)

**Engineering tooling (measure / verify / harden):**
- `/bench` — set up or extend a benchmark harness (hyperfine for binaries, language-native bench for hot functions)
- `/profile` — wrap perf / samply / py-spy / pprof around a target and surface top hotspots + flamegraph
- `/coverage` — run tests with coverage and produce a prioritized TODO list of uncovered branches (no threshold gating)
- `/dep-audit` — run language-native supply-chain audit, classify findings, propose triage actions per CVE
- `/repro-bug` — turn a bug description into a minimal failing test (test only, fix in a separate turn)
- `/fuzz-harness` — set up a libFuzzer / AFL++ / language-native fuzzing harness (defensive, hardening parsers)
- `/refactor-plan` — propose a stepwise TDD-friendly refactor plan with green-test checkpoints (analysis only)
- `/api-diff` — surface breaking surface-area changes vs base, with SemVer-relevant classification

**Security research scaffolding:**
- `/poc` — scaffold a PoC project from `security-research-workflow`
- `/writeup` — create or extend `WRITEUP.md`
- `/re-note` — new function note under `notes/functions/`
- `/cve-template` — CVE metadata file
- `/sploit-checklist` — exploit-dev sanity checklist against the current PoC
- `/threat-model` — STRIDE pass against the current diff or a named feature

**Research log:**
- `/timeline` — initialize, view, or append a free-form note to `notes/timeline.md` (the human-readable mirror of the command log)
- `/log` — manually append a JSONL entry to `.claude/logs/commands.jsonl` (backfill for missed commands, free-form findings, screenshot pointers)

## Subagents available

Custom subagents live in `agents/` and are auto-discovered. Invoke them via the Agent tool when the task fits.

**Engineering:**
- `code-reviewer` — substantive, severity-tagged review of a diff or file. Mirrors `code-review` skill but as a fresh-eyes agent. Surfaces findings; does not modify code.
- `test-writer` — given a function/class/module, propose a complete test suite (table-driven, property-based, edge cases, error paths). Pairs with `/test-first` and `/coverage`.
- `debugger` — given a stack trace / sanitizer report / crash log / hang / wrong result, produce ranked hypotheses, run targeted diagnostics, and surface a diagnosis. Diagnosis only; user fixes.
- `refactor-planner` — read a target and propose a stepwise refactor plan with green-test checkpoints. Plan only; user executes.
- `perf-analyst` — wrap profiling + benchmarking around a target and produce a written perf report (top hotspots, surprises, leverage-ranked recommendations).

**Security:**
- `binary-analyst` — static triage of an unfamiliar ELF/Mach-O/PE/firmware blob: identification, hardening, linkage, symbols, strings, sections, and a follow-up candidate list. Never executes the target.
- `exploit-reviewer` — severity-tagged review of a draft PoC for reproducibility, correctness, hygiene, and writeup-readiness. Surfaces findings; does not modify the PoC.

## Command-logging workflow

This template installs two research-log hooks. Both are best-effort, never block, and silently no-op when their preconditions aren't met.

- **`PostToolUse` on Bash → `hooks/log-interesting-commands.sh`** — captures noteworthy Bash calls into `.claude/logs/commands.jsonl`. Three-tier decision: an opinionated **always** list (debuggers, dynamic instrumentation), a **never** list (navigation/status noise), and a **Claude decides** middle tier opted into via the `[log]` / `[log: <reason>]` marker on the Bash `description`. Full rules in `skills/command-logging/SKILL.md`.
- **`SessionStart` → `hooks/session-start.sh`** — writes a session breadcrumb (timestamp, branch, commit, session id) to `.claude/logs/sessions.jsonl` and, if `notes/timeline.md` exists, appends a session header there too. Fires only on `startup` and `resume` (not `clear`/`compact`).

Implications for how you work:

- When running tools whose output you'll cite, paraphrase, or rely on later, **mark the Bash `description` with `[log]`**. Skip the marker for navigation, status checks, and setup steps.
- `notes/timeline.md` is **opt-in by existence**. The hook only mirrors entries there if the file already exists. Use `/timeline init` to create it; the user is the only one who should be deciding to turn the human-readable mirror on.
- `.claude/logs/` should generally be in `.gitignore`. Don't commit it without the user's say-so — the JSONL files can contain target output that shouldn't go upstream.
- The auto-commit hook (below) will pick up `.claude/logs/` if it isn't gitignored. Verify before pushing.

## Auto-commit workflow

This template installs a `Stop` hook (`hooks/auto-commit.sh`) that snapshots the working tree as a `wip(claude): <timestamp> — <stat>` commit at the end of every turn. Implications:

- **Don't manually `git commit` the user's working changes** unless they ask. The hook handles checkpointing. Manual commits are still appropriate for *intentional* milestones (e.g., the squash step, or finishing a logically complete feature mid-turn that the user explicitly wants captured).
- **Don't squash, rebase, or rewrite history without being asked** — the user uses `/squash` (see `commands/squash.md`) to consolidate the wip commits into clean ones when they're ready to push.
- **Don't push.** Pushing is the user's call. Never `git push` (and absolutely never `--force`) without explicit instruction in the current turn.
- **Treat `wip(claude):` commits as throwaway.** They will be replaced by `/squash`. Don't reference them in documentation, don't include them in changelogs, don't link to their hashes.
- If you see the working tree is mid-rebase/merge/cherry-pick, the hook intentionally skips. Don't try to "help" by completing those operations unless asked.

## What to do when uncertain

Ask. The user prefers a clarifying question over wasted work. One pointed question is better than three rounds of revision.

(Auto-mode caveat: when running in Claude Code's auto-mode, prefer reasonable assumptions for low-risk decisions and flag them inline. Reserve clarifying questions for choices that are hard to reverse, affect security/scope, or where guessing wrong would waste meaningful work.)
