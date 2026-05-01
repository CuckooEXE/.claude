---
name: cli-tool-design
description: Conventions for designing and packaging CLI tools — flag and argument design, exit codes, stdin/stdout/stderr discipline, --json output, subcommand layouts (git/docker style), Python packaging via pyproject.toml + entry_points for pipx, plus equivalents in C/Zig/Rust. Use this skill when designing a new CLI, adding flags or subcommands to an existing one, packaging a Python tool for pipx distribution, or reviewing CLI ergonomics.
---

# CLI Tool Design

The user installs Python CLI tools globally with `pipx`. They expect a CLI to feel like a UNIX citizen, not a hand-rolled toy.

## The five-minute test

A CLI passes the five-minute test if a competent stranger can:

1. Run `--help` and understand what the tool does.
2. Run `<tool> --version` and get a sane answer.
3. Pipe its output into another tool without escaping anything.
4. Pipe input *into* it (when that makes sense).
5. Tell from the exit code whether it succeeded.

Most home-grown CLIs fail one or more of these. Don't.

## Argument vs flag — which to use

| Concept | Form | When |
|---|---|---|
| Subcommand | `tool verb` | Distinct modes ("docker run", "git commit") |
| Positional argument | `tool <file>` | The required, primary input(s). Few in number. |
| Long flag | `--output FILE` | Optional configuration, named clearly |
| Short flag | `-o FILE` | Long flag's frequent-use shortcut. Don't invent shorts that don't have a long form. |
| Boolean flag | `--verbose` / `--no-verbose` | True/false toggles. Pair with `--no-` form when default is on. |

Rules:
- Long flags are `--kebab-case`, never `--camelCase` or `--snake_case`.
- Short flags are single letters. `-vv` should mean increase-verbosity-twice if you support `-v`.
- Don't use one-letter long flags (`-v` good, `--v` bad).
- Don't make required things into flags. If `--input` is required to do anything, it's a positional argument, not a flag.

## POSIX conventions to follow

- `--` ends flag parsing. `tool -- -file-starting-with-dash`.
- `-` as a filename means stdin/stdout. Most tools take `-` for input; many accept it for output. Implement at least the input case.
- `--help` and `-h` both exist.
- `--version` exists and prints just the version, ideally with build metadata (`mytool 0.4.2 (commit abc1234, built 2024-11-30)`).
- `--quiet`/`-q` and `--verbose`/`-v` are the standard verbosity controls. Don't invent new names.

## Stdin / stdout / stderr discipline

This is where most homegrown tools fall apart.

- **stdout** is for *the result*. Only the result. If your tool prints "OK done!" to stdout, it cannot be piped.
- **stderr** is for diagnostics: progress, warnings, errors. Never the result.
- **stdin** is read for input when the user passes `-` as the input filename, or when no input is given and stdin is a pipe (`isatty() == false`). Don't read stdin when it's a TTY — the user just forgot an argument.
- Detect TTY-ness with `sys.stdin.isatty()`, `isatty(0)` in C, etc. Tailor behavior:
  - Color output: only if stdout is a TTY (or `--color=always`). Honor `NO_COLOR=1` env var.
  - Progress bars: only if stderr is a TTY.
  - Pretty-printing JSON: only if stdout is a TTY (or `--pretty`).

## Exit codes

Pick one convention and document it:

**Minimal:**
- `0` — success
- non-zero — failure

**Better, for non-trivial tools:**
- `0` — success
- `1` — generic failure (exception, unexpected error)
- `2` — user error (bad flags, missing required input). Most argparse libs use `2` for argument errors, so embrace it.
- `64–78` — sysexits.h codes if your tool fits the categories (`64` EX_USAGE, `66` EX_NOINPUT, `74` EX_IOERR). Optional but professional.

For tools that classify results (e.g., a linter): `0` clean, `1` issues found, `2` tool error. Document explicitly.

## --json mode

Any non-trivial tool benefits from a `--json` flag that emits machine-parseable output. Conventions:

- **NDJSON for streams.** One JSON object per line. Easy to grep, easy to `| jq -c .`. Don't emit a giant array if the data is streaming.
- **Single object for atomic results.** Fine when there's one logical result.
- **Schema versioning.** Include `"version": 1` (or similar) in the top-level. Future-you will thank you.
- **Don't break the contract.** Once `--json` output has a documented shape, treat it like API.
- **Errors in JSON mode** still go to stderr as JSON: `{"level":"error","msg":"..."}` — not a half-text-half-JSON output.

## Subcommands (git / docker style)

For tools that do more than one thing, subcommands beat a flag-soup. Layout:

```
tool <subcommand> [flags] [args]
```

Conventions:
- Subcommands are short verbs: `add`, `list`, `run`, `init`, `status`.
- Common flags work *before* or *after* the subcommand (`tool -v list` and `tool list -v`). The CLI library usually supports this; pick one for docs.
- `tool` with no args prints help (exit code 0 or 2 — you decide and document).
- `tool help <subcommand>` and `tool <subcommand> --help` both work.
- Each subcommand has its own `--help` listing only its flags.

## Python: argparse vs click vs typer

| Tool | When |
|---|---|
| `argparse` | stdlib, no deps, fine for small CLIs. Verbose for subcommands. |
| `click` | Best when you want subcommands, plugins, config files. Stable, mature. |
| `typer` | Best when type-hint-driven CLIs are appealing. Builds on click. |
| `argparse` + `argcomplete` | When shell completion matters and you want stdlib-only. |

The user's default: `click` for tools with subcommands, `argparse` for simple ones. `typer` is fine if you like it; document the choice.

## Packaging a Python CLI for pipx

A pipx-installable tool needs a `pyproject.toml` with an entry point:

```toml
[project]
name = "mytool"
version = "0.1.0"
description = "Does the thing."
readme = "README.md"
requires-python = ">=3.11"
authors = [{name = "..."}]
dependencies = [
    "click>=8.1",
]

[project.scripts]
mytool = "mytool.cli:main"

[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"
```

Then `pipx install .` from the repo root, or `pipx install <package>` from PyPI.

Rules:
- The entry-point function (`main` here) should accept no args (click handles argv).
- Don't write to `~/.local/share/...` without `XDG_DATA_HOME` respect.
- Never write next to the installed package — it's read-only-ish under pipx.
- Print actionable errors when env vars / config files are missing. "Set `MYTOOL_TOKEN` or run `mytool login`." — not a stack trace.

## C / Zig / Rust CLIs

- **C**: `getopt_long` from `<getopt.h>` is fine for simple cases. For anything with subcommands, write a small dispatcher rather than reaching for a library. Document the parser at the top of the file.
- **Zig**: `std.process.argsWithAllocator`. There are community libs (`zig-clap`) but the stdlib is enough for most cases.
- **Rust**: `clap` is the standard. Use derive-style for ergonomics.

## Configuration files

- **Don't** require a config file to run. `--help` should still work, the tool should still be useful with sensible defaults.
- **Do** support an optional config file when a tool has many tunable knobs. `~/.config/<tool>/config.toml` (XDG) on Linux, equivalent on macOS/Windows.
- **Precedence (highest wins):** flag > env var > config file > built-in default. Document this.
- TOML > YAML > JSON for human-edited configs. JSON has no comments; that's a deal-breaker.

## Environment variables

- `<TOOL>_<VAR>` for tool-specific (`MYTOOL_TOKEN`, `MYTOOL_LOG_LEVEL`).
- Honor existing community standards: `NO_COLOR`, `XDG_*`, `DEBUG`, `EDITOR`, `PAGER`.
- Document every env var the tool reads. Hidden env vars are surprise bugs.

## Logging vs printing

Once a CLI does more than ~200 lines, switch from `print` to a real logger:

- Python: `logging` module, configured at startup. `--verbose`/`-v` raises the level by one step (default WARNING → INFO → DEBUG).
- C: a tiny logger with level + timestamp. Don't reach for log4c.
- Rust: `tracing` or `log` + `env_logger`.

Logs go to stderr. Always.

## Shell completion

For tools you'll use a lot, ship completions. `click` and `argcomplete` can emit them; commit them to `completions/` and document the install step in `installation.md`.

## What to test on a CLI

- `--help` runs, exits 0, mentions every subcommand.
- `--version` runs, prints version, exits 0.
- Argument parsing failures exit 2 with a useful message.
- Each subcommand with `--help` lists its flags.
- Reading from stdin (`-` or piped) works for any documented case.
- Output to a pipe (`tool ... | cat`) doesn't break (no ANSI in non-TTY mode).
- `--json` output round-trips through `jq -c .`.

## Things to avoid

- Interactive prompts in a tool that's supposed to be scriptable. Provide a `--yes` / `--non-interactive` mode.
- Silent network calls. Tools that phone home without a flag are a footgun.
- Mixing log output and result output on stdout.
- "Helpful" defaults that surprise: auto-creating directories, auto-deleting files.
- ANSI escapes in non-TTY output.
- `--force` flags that make destructive operations easier without making them safer.
