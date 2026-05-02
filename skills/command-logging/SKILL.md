---
name: command-logging
description: Selectively log noteworthy Bash commands and their output to a research timeline. Use this skill any time you are about to run a Bash command whose **output will inform a research decision** — symbol enumeration, format probing, version checks, configuration inspection, anything you'll cite or refer back to later. Do NOT use it for navigation, sanity checks, status queries, or commands you're running purely to set up the next step. Especially load this skill during reverse engineering, vulnerability research, exploit development, and any session where the user expects a paper trail of how findings were obtained.
---

# Command logging

This template installs a `PostToolUse` hook (`hooks/log-interesting-commands.sh`) that captures Bash calls into `.claude/logs/commands.jsonl`, mirroring to `notes/timeline.md` when that file exists. The user wants a **curated** trace of the investigation — not a transcript of every shell call. Your job is to drive that curation.

## How the hook decides

The hook applies a three-tier decision, in order:

1. **Always logged** — a small, opinionated list of high-value tools where the trace is essentially never noise: `gdb`, `lldb`, `strace`, `ltrace`, `frida`, `frida-trace`, `rr`, `r2`/`radare2`, `rabin2`, `rasm2`, `rax2`. You don't need to mark these.
2. **Never logged** — pure navigation/status noise: `ls`, `pwd`, `cd`, `which`, `cat`, `head`, `tail`, `wc`, `sort`, `uniq`, `less`, `more`, `echo`, `printf`, `mkdir`, `touch`, `clear`, `tee`, etc. The hook drops these silently even if you mark them.
3. **Everything else** — logged **only if you mark it** by prefixing the Bash tool's `description` field. The marker is stripped before storage, so the recorded description stays clean.

Two marker forms:

- `[log] <description>` — log this; the rest of the description is the reason.
- `[log: <reason>] <description>` — log this with an explicit reason that's separate from the user-facing description (useful when the description is short but the *why* is longer, or vice versa).

## When to flip the marker on

Flip it **on** any time the output will influence a research decision or appear (directly or paraphrased) in a writeup:

- **Reverse engineering**: `nm`, `objdump`, `readelf`, `strings`, `file`, `ldd`, `otool`, `checksec`, `binwalk`, `xxd`/`hexdump` against a target region, `ghidra-headless`, `objcopy`.
- **Vulnerability research**: probing inputs, fuzzer crash triage, ASan/MSan reports, coverage diffs, harness output you'll cite.
- **Exploit development**: gadget hunts (`ROPgadget`, `one_gadget`, `Ropper`), libc symbol lookups, `pwn checksec`, leak-sanity-check oneliners.
- **Network / protocol**: `tshark`, `tcpdump`, `nmap`, `curl`/`wget` against the target with response capture, `openssl s_client`, `dig`.
- **Build/test artifacts that prove or disprove a claim**: `make` output for a config-flag bisect, `objdump -d` to confirm the compiler emitted what you expected, `git bisect` results.
- **Anything you'll quote in a writeup** — even if the binary isn't on the lists above.

## When to leave it off

- Looking around the repo (`ls`, `find` for navigation, `cat` of source you're reading).
- Routine git: `git status`, `git diff`, `git log`, branch/remote checks.
- Running tests where you only care about pass/fail right now and won't cite the output.
- Building/installing dependencies (`pip install`, `apt install`, `cargo build` mid-iteration).
- One-off `mkdir`/`touch`/`mv` of scaffolding.
- Anything you're running to set up the *next* step rather than to learn something from this one.

## Writing a good reason

The reason is the "why I ran this." Future-you and the report reader rely on it. Be specific.

- Bad: `[log] running nm`
- OK: `[log] checking exported symbols`
- Good: `[log: enumerating exported symbols to find candidates for an LD_PRELOAD hook]`

If the reason is short and the rest of the description redundant, just put it after the bare marker:

- `[log] enumerating exported symbols to find LD_PRELOAD hook candidates`

If you find yourself running multiple related commands (e.g., `nm`, `readelf`, `strings` on the same target), make each reason specific to *what that command tells you* — not a copy-paste of the parent investigation.

## Pipelines

For pipelines like `nm libfoo.so | grep -i auth`, the **first** binary determines the decision. `nm` is on the always-list, so it'll be captured automatically with the full pipeline as the recorded `cmd`. You don't need to mark it.

For pipelines starting with a "neutral" tool (e.g., `xxd target.bin | grep -A2 'magic'`), `xxd` is *not* on either list, so you must mark with `[log]` if you want it captured.

## Backfilling and manual entries

If you forgot to mark something and it should have been logged, use `/log` to add a manual entry referencing the command and its output. `/log` also handles free-form thoughts, screenshots, and findings that aren't shell commands at all.

## Disabling

If the user asks to silence the log for a session, set `CLAUDE_CMDLOG_DISABLE=1` in the environment (or unset it later to resume). Don't disable globally without being asked — the user opted into this.

## What ends up where

- `.claude/logs/commands.jsonl` — one NDJSON record per logged call. Full stdout/stderr, no truncation. Source of truth.
- `notes/timeline.md` — human-readable mirror, only written if the file already exists. Truncated to roughly 40 lines / 4 KB per stream. Use `/timeline` to create the file or open it.
- `.claude/logs/sessions.jsonl` — session start/resume breadcrumbs from the `SessionStart` hook. Lets you correlate a `commands.jsonl` entry with which session produced it via `session_id`.
