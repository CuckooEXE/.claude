---
description: Set up a fuzzing harness (libFuzzer / AFL++ / language-native) for a target function — defensive use, for hardening parsers and decoders.
argument-hint: [target — function name + file, e.g., "parse_header in src/foo.c"]
allowed-tools: Read, Edit, Write, Glob, Grep, Bash(clang:*), Bash(afl-fuzz:*), Bash(cargo:*), Bash(go:*), Bash(zig:*), Bash(make:*), Bash(cmake:*), Bash(test:*), Bash(ls:*)
---

# /fuzz-harness — set up a fuzzing harness for hardening

This is the **defensive** counterpart to `/poc`. The goal is to harden parsers, decoders, deserializers, and other input-handling code by feeding them mutated inputs until they crash or assert. When fuzzing finds a crash, the next steps are: minimize the input → write a regression test (`/repro-bug`) → fix.

Argument: `$ARGUMENTS` — the target. Should be a function name plus its file, or a parser entry point. If empty, ask.

## Procedure

1. **Identify language and best-fit fuzzer**:

   | Language | Tool | Notes |
   |---|---|---|
   | C / C++ | **libFuzzer** (in-process, fast iteration). **AFL++** (broader, more mutators, covers harder targets) | libFuzzer is built into clang; trivial setup |
   | Rust | `cargo fuzz` (libFuzzer wrapper). Or `cargo afl` for AFL++ | `cargo fuzz init` scaffolds |
   | Go | Built-in `go test -fuzz=Fuzz<Name>` (1.18+) | Best path for Go targets |
   | Python | `atheris` (libFuzzer for Python). Or `hypothesis` for property-based (technically PBT, not fuzzing, but related) | Atheris needs the function to be hot enough that interpretation overhead is OK |
   | Zig | `std.testing.fuzz` (where available); else AFL++ against a small test driver | Zig's fuzzing story is evolving |

2. **Read the target function** to understand its inputs:
   - What's the input type — bytes, structured data, a struct?
   - What invariants should hold (no crash, no UB, output well-formed)?
   - Is there setup state (config, allocator) that the harness needs to provide?

3. **Scaffold the harness** in the project's conventional location:
   - C/C++ libFuzzer: `fuzz/<target>_fuzz.cc` with `LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)`.
   - Rust: `cargo fuzz add <name>` creates `fuzz/fuzz_targets/<name>.rs` with `fuzz_target!(|data: &[u8]| { ... })`.
   - Go: `func FuzzX(f *testing.F)` in a `_test.go` file, with `f.Fuzz(func(t *testing.T, data []byte) { ... })`.
   - Python (atheris): `fuzz_<target>.py` with `atheris.Setup(...)` and `atheris.Fuzz()`.

4. **Write the harness body**:
   - Convert raw input bytes into the target function's expected type (parse a length prefix, decode a struct, etc.) — or just pass the bytes if the target accepts bytes.
   - **Avoid trivial early-exit on length** unless the target itself does — you want the fuzzer to find length-related bugs.
   - **Catch only the specific exception types the target legitimately throws.** Letting unhandled exceptions propagate is what surfaces real bugs.
   - **Don't suppress sanitizer output.** The whole point is to crash loudly.

   Example (libFuzzer for a hypothetical `parse_header`):
   ```cpp
   #include <cstdint>
   #include <cstddef>
   #include "foo.h"

   extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
       parse_header(data, size);  // ASan/UBSan catches the crash if any
       return 0;
   }
   ```

5. **Build with sanitizers** — non-negotiable for memory-safety fuzzing:
   - `-fsanitize=fuzzer,address,undefined -fno-omit-frame-pointer -g`
   - For C++ also add `-fsanitize=vptr` and consider `-fsanitize=memory` (separate build, not combinable with ASan).
   - For Rust: `cargo fuzz` sets these by default.

6. **Seed corpus**:
   - Start with **valid example inputs**. Real protocol captures, real test fixtures, golden files.
   - libFuzzer / AFL++ both accept `-corpus_dir` / `-i input/` directories.
   - Without seeds, the fuzzer wastes hours discovering basic input structure. With good seeds, it finds bugs in minutes.

7. **Run** with `[log: starting fuzz run for <target>]`:
   ```bash
   # libFuzzer: in-process, fast inner loop
   ./parse_fuzz corpus/ -max_total_time=300

   # AFL++: harder targets, slower per-exec but better mutators
   afl-fuzz -i corpus -o output -- ./parse_target @@
   
   # cargo fuzz
   cargo fuzz run parse_target corpus/ -- -max_total_time=300

   # Go
   go test -fuzz=FuzzParse -fuzztime=5m
   ```

   Run for **at least 5 minutes** for an initial sanity check; for serious hardening, run hours-to-days. Save the corpus when you stop — it's reusable.

8. **On a crash**:
   - **Save the crashing input** — libFuzzer drops it as `crash-<hash>`, AFL++ in `output/crashes/`. Commit the input to the corpus.
   - **Minimize**: `./fuzz_target -minimize_crash=1 crash-<hash>` (libFuzzer), `afl-tmin -i in -o min -- ./target @@` (AFL++).
   - **Write a regression test** with `/repro-bug` against the minimized input.
   - **Fix**, separately.

## Hard rules

- **This is defensive use.** Fuzzing hardens parsers; that's distinct from `/poc` (offensive PoC against a vulnerable target).
- **Build with sanitizers.** Without ASan/UBSan, you'll only catch crashes that segfault on their own — missing many UB bugs.
- **Don't catch broad exceptions in the harness.** You'll mask real bugs.
- **Don't run long fuzz campaigns in CI without a budget.** Set `-max_total_time` or `-runs=N`. Otherwise CI hangs.
- **Don't commit crash inputs containing secrets.** Sanitize first if the input came from real production data.

## See also

- `testing-strategy` skill — fuzzing as property-based testing's brutalist cousin.
- `security-research-workflow` skill — when fuzzing finds a crash that turns out to be exploitable, this becomes a vulnerability.
- `/repro-bug` — turn a crashing input into a regression test.
- `/poc` — the offensive counterpart, for exploit development against a known-vulnerable target.
