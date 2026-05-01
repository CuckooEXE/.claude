---
description: Run the exploit-development sanity checklist against the current PoC — header metadata, mitigations documented, libc hash captured, success rate noted, defensive prints, no live target IPs, etc.
argument-hint: [optional path to the PoC file or directory; defaults to ./poc/]
allowed-tools: Bash(test:*), Bash(ls:*), Bash(file:*), Bash(grep:*), Bash(head:*), Bash(sha256sum:*), Read
---

# /sploit-checklist — exploit-dev sanity check

Pull in `security-research-workflow` for context. This is a *report*, not a fixer. Run the checks, present results, propose fixes; don't silently rewrite the PoC.

## Target

If `$ARGUMENTS` is given, treat it as a path (file or directory). Otherwise default to `./poc/`. If neither exists, ask the user where the PoC lives.

If a directory: enumerate `*.py`, `*.c`, `*.cpp`, `*.zig`, `*.s`, `*.asm` and run the checks against each. If a single file, against that file.

## Checks

For each PoC file, evaluate:

### Header metadata
- [ ] **Top-of-file docstring/header** present.
- [ ] States **target product + version**.
- [ ] States **OS + version + kernel + libc** the exploit was tested on.
- [ ] States **mitigations** in scope: ASLR (and `randomize_va_space` value), NX, CFI, CET, stack canaries, RELRO, Fortify.
- [ ] States the **bug class** in one phrase ("stack BOF", "UAF on close", "double-free in cleanup", "format-string in log", etc.).
- [ ] States the **author** and **date**.
- [ ] States **authorization context** (engagement, scope), at least via reference to `notes/target-overview.md`.

### Reproducibility
- [ ] **libc hash** captured if libc-dependent (`sha256sum /lib/x86_64-linux-gnu/libc.so.6` recorded).
- [ ] **Target binary hash** recorded somewhere in the project (often in `samples/manifest.txt`).
- [ ] **Compile flags** documented if the exploit is built (Makefile or top-of-file comment).
- [ ] **Probabilistic exploits**: success rate documented and what affects it.

### Defensive programming for offensive code
- [ ] **Leaks validated** — every leaked pointer is sanity-checked (looks like a heap/libc/stack address) before use.
- [ ] **Stage prints** — at least one `[+] ...` line per stage so the operator sees progress.
- [ ] **Bail-out on failure** — exits with a clear message rather than silently falling through into a dead shell.
- [ ] **No bare `except:` / `catch (...)`** that swallows errors.

### Hygiene
- [ ] **No hardcoded credentials** (search for `password`, `passwd`, `secret`, `token`, `api_key`, `BEGIN PRIVATE KEY`).
- [ ] **No live target IPs** unless explicitly intentional and documented (`# INTENTIONAL: live target IP`). Otherwise prefer `127.0.0.1` / placeholders.
- [ ] **No internal hostnames** (`*.corp.internal`, `*.local`, employee names) for PoCs that may end up published.
- [ ] **Magic numbers commented** — every offset, gadget address, padding length has a `# why this number` comment nearby.

### Build / run instructions
- [ ] A `README.md` or top-of-file block tells the reader exactly how to build and run.
- [ ] Dependencies listed (`pwntools`, specific versions, etc.).

## Output format

```
## Sploit checklist — <path>

### <file 1>
- [x] Header metadata complete
- [ ] libc hash missing
  - Suggestion: `sha256sum /lib/x86_64-linux-gnu/libc.so.6` and paste into the header
- [ ] Stage 3 has no `[+] ...` print
  - Location: line 142
- [x] No hardcoded credentials
- ...

### <file 2>
...

## Summary
N items missing across M files. Most critical: <one line>.
```

For each failed check, include the **file:line** if applicable, the issue, and a concrete fix suggestion. Don't be vague.

## Rules

- **Don't auto-fix.** Surface issues; let the user decide. The PoC is the centerpiece of the writeup; silent rewrites are unwelcome.
- **Don't run the exploit.** This command is static analysis only.
- If the PoC is in a language you don't have specific checks for, run the generic checks (header, hygiene, build instructions) and note the gap.
- Treat regex-based searches (e.g., for "password") as *signals*, not certainties. False positives are fine to flag with a question; don't claim a credential leak based on a string match alone.
