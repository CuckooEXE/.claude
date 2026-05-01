---
name: debugging-workflow
description: Systematic debugging methodology for native code, Python, and exploit-dev contexts — gdb/lldb productivity, rr time-travel, core-dump triage, the sanitizer family (ASan, UBSan, MSan, TSan), strace/ltrace, git bisect for regressions, and when to reach for which tool. Use this skill whenever the user is hunting a bug, investigating a crash, triaging a core dump, dealing with a sanitizer report, or asking "why is this happening."
---

# Debugging Workflow

The user is comfortable with the standard debugging kit. This skill is about *methodology* and tool selection, not tutorials.

## The first five minutes

Before reaching for any tool:

1. **Reproduce.** A bug you can't reproduce is a bug you can't fix. Capture the *exact* command, input, environment, version, and output. If repro is flaky, that itself is the first clue (race? heap layout? uninitialized memory?).
2. **Read the error.** The actual error message, not your assumption of what it means. Read the stack trace from the bottom up.
3. **Form a hypothesis.** State it explicitly. "I think the bug is in X because Y." A debugging session without a hypothesis is just poking.
4. **Pick the cheapest test of that hypothesis.** A `print` is faster than a debugger; a debugger is faster than a sanitizer rebuild; a sanitizer rebuild is faster than rr. Don't escalate prematurely.
5. **Update or discard the hypothesis based on what you actually saw, not what you expected to see.**

## When `print` is the right answer

- The bug is reproducible in seconds.
- You roughly know where it is.
- The data you need is small and easily formatted.

A targeted print at the right line is often faster than five minutes of fiddling with breakpoints. Senior engineers print without shame.

## When to reach for a debugger

- The bug is in compiled code without good logging.
- You need to inspect memory, registers, or call frames.
- You're looking at a core dump.
- You need conditional breakpoints (`break X if cond`).

### gdb productivity

- Use a config: `~/.gdbinit` with `set history save on`, `set print pretty on`, `set pagination off`, `set confirm off`.
- Install **pwndbg** or **GEF** for exploit work — `context`, `vmmap`, `checksec`, `heap` are huge.
- For Python-augmented inspection, write a `gdb` Python script rather than typing the same commands repeatedly.
- `rbreak <regex>` for breakpoints across many functions.
- `commands <bp>` to attach scripts to breakpoints (`silent; printf "hit X with rax=%p\n", $rax; cont`).
- `watch <expr>` for data breakpoints when you don't know who's writing to a variable.

### lldb

- Same model, different syntax. `b -n func`, `frame variable`, `expression`.
- On macOS, lldb is the native choice; on Linux, gdb has more tooling around it.

## When to reach for rr (time-travel)

The single best tool for "how did we get into this state" bugs.

- **Free**, open source, replay debugging for Linux x86/x86_64.
- Record once with `rr record ./bin args`. Replay with `rr replay`. Now `reverse-cont`, `reverse-step`, `reverse-finish` work.
- Pairs with pwndbg: `rr replay -- -x ~/.gdbinit-pwndbg`.
- Best for: heisenbugs, "what wrote this value", bugs that take many seconds to reproduce, threading bugs (rr serializes execution, so it removes the race — useful but also a caveat).
- Caveats: requires hardware perf counters (CAP_PERFMON or root or `perf_event_paranoid` tuned). Not for code that uses certain CPU features (RDTSC quirks, AVX-512 in some configs).

## Sanitizers — when to rebuild

Building with the right sanitizer often pinpoints a bug instantly that would take hours in a debugger.

| Sanitizer | Catches | Cost | When |
|---|---|---|---|
| **ASan** (`-fsanitize=address`) | Heap/stack/global overflow, UAF, double-free | ~2x slower, 3x memory | First reach for any C/C++ memory bug |
| **UBSan** (`-fsanitize=undefined`) | Signed overflow, shift OOB, null deref, alignment, bad enum | ~10% slower | Always-on for dev builds |
| **MSan** (`-fsanitize=memory`) | Use of uninitialized memory | 3x slower; needs *all* deps instrumented | When you suspect uninit reads (libc-friendly variants exist; check) |
| **TSan** (`-fsanitize=thread`) | Data races | 5–15x slower, 5–10x memory | Threading bugs, but expect false positives if the code uses lockfree algorithms |
| **LeakSanitizer** (built into ASan) | Leaks at exit | Negligible | Free with ASan, leave it on |

Compile with `-g -O1 -fno-omit-frame-pointer` plus the sanitizer flag. `-O0` makes ASan stack frames less useful; `-O1` is the sweet spot.

ASan + UBSan in dev builds should be the default for C/C++ projects. Add a `make asan` / `cmake -DSANITIZE=address` target if the build doesn't have one.

## Core-dump triage

```
ulimit -c unlimited
echo "core.%e.%p" | sudo tee /proc/sys/kernel/core_pattern
```

Then, after a crash:

```
gdb <binary> <core>
(gdb) bt full
(gdb) info threads
(gdb) thread apply all bt
(gdb) info registers
(gdb) x/40i $pc-40
```

Capture the binary's exact build (commit hash, build flags) alongside the core. Without that, the addresses in the core are meaningless. If reproducing on a different machine, also capture `ldd <binary>` output and the relevant `.so` files.

## strace / ltrace

When the bug is at a boundary you don't own:
- `strace -f -e trace=openat,read,write,connect <cmd>` — what is the program *actually* doing at the syscall level.
- `strace -e raw=open` to see the int flag values rather than the symbolic names.
- `ltrace` for libc/library calls. Less reliable on stripped or static binaries.

Useful as a first step on "the program isn't doing what I think" before opening a debugger.

## Python debugging

- `pdb` / `breakpoint()` for interactive. Modern Python sets `PYTHONBREAKPOINT=ipdb.set_trace` if you prefer.
- `python -X tracemalloc=25 ...` to find leaks.
- `faulthandler.enable()` at startup so segfaults in C extensions get a Python traceback.
- `pytest --pdb` to drop into a debugger on the first test failure.
- For perf-shaped bugs, `cProfile` then `snakeviz` is the cheapest path.

## Bisecting regressions

If a bug "used to work":

1. Find a known-good commit. Confirm it actually works there.
2. `git bisect start && git bisect bad && git bisect good <commit>`.
3. Write a test script that exits 0 on good, non-zero on bad, 125 on skip.
4. `git bisect run <script>`.
5. When done, `git bisect reset` and read the commit it found. Don't blindly trust — sometimes bisect lands on a refactor that exposed a pre-existing bug.

## Methodology checklist when stuck

If 30 minutes pass without progress, stop and ask:

- Have I actually reproduced the bug, or am I debugging my assumption of it?
- Am I looking at the right binary / version / commit?
- Did I rebuild after my last change?
- Is my hypothesis falsifiable, or am I confirmation-biasing?
- Have I read the error message word for word?
- Am I treating a symptom (a print value) as the cause?
- What would I tell another engineer if they came to me with this bug? (rubber-duck)

## Exploit-dev specific

When debugging an exploit that "should work":

- Confirm the bug actually fires (set a breakpoint at the vulnerable function, watch the corruption happen).
- Confirm each leak before using it. Print every value you derive an address from.
- Verify ASLR state on the target. `cat /proc/sys/kernel/randomize_va_space`. A successful test against `0` means nothing if the target runs at `2`.
- If shellcode "doesn't pop a shell," step through it instruction by instruction. Don't assume the syscall returned what you expect.
- Run under `strace` to see if the syscall even happened (often a sign that `RIP` didn't land where you thought).

See `security-research-workflow` for the broader exploit-dev conventions.

## Tools to know exist

- **AddressSanitizer**, **UBSan**, **MSan**, **TSan**, **LeakSanitizer** — see table above.
- **rr** — reverse debugging.
- **valgrind / memcheck** — older, slower than ASan, but works without rebuild. Useful for closed-source binaries.
- **valgrind / helgrind** — race detector alternative to TSan, no rebuild.
- **valgrind / cachegrind / callgrind** — see `performance-analysis`.
- **eBPF / bpftrace** — production-safe tracing. `bpftrace -e 'tracepoint:syscalls:sys_enter_openat { printf("%s\n", str(args->filename)); }'`.
- **SystemTap**, **DTrace** — older alternatives, still useful.
- **perf trace** — strace-shaped output via perf, lower overhead.
- **sysdig** — strace + tcpdump fusion, container-aware.

## Things to actively avoid

- "It works now" — without understanding *why* it works now. The bug isn't fixed; it's hiding.
- Adding a try/except to make the symptom go away.
- "Maybe it's a race" without evidence.
- Debugging in production. Repro locally first.
- Long debugging sessions without notes. Write the timeline as you go — same discipline as RE.
