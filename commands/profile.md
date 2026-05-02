---
description: Wrap a profiler around a target binary or function and produce a flamegraph / top-N hotspot summary.
argument-hint: [target — binary path, function name, or test command]
allowed-tools: Bash(perf:*), Bash(samply:*), Bash(py-spy:*), Bash(cargo:*), Bash(go:*), Bash(make:*), Bash(test:*), Bash(ls:*), Bash(file:*), Read, Glob
---

# /profile — profile a target

Goal: identify where the time is actually going. The default suspect is wrong; the profiler tells the truth.

Argument: `$ARGUMENTS` — the target. May be a binary path, a test command, or a function name. If empty, ask.

## Procedure

1. **Identify the right tool** for the language/runtime:

   | Target | Tool | Notes |
   |---|---|---|
   | Native (C / C++ / Zig / Rust release) | `perf record` + `perf report` (Linux), `samply` (cross-platform, modern) | `perf` needs `-fno-omit-frame-pointer` or DWARF unwinding |
   | Python (CPython) | `py-spy` (sampling, no instrumentation) or `cProfile` (deterministic) | `py-spy` runs against a live process; doesn't need code changes |
   | Go | `go test -cpuprofile`, `go tool pprof` | First-class profiling support |
   | Java / JVM | `async-profiler` | Works for hybrid Java/native frames |

   On macOS: `samply` or Instruments. `perf` is Linux-only.

2. **Build correctly**:
   - **Release / optimized build** with **frame pointers retained** (`-fno-omit-frame-pointer`) or DWARF debug info present (`-g`).
   - For Rust: `[profile.release] debug = true`. Don't profile a debug build — the hotspots will be wrong.
   - Verify the binary has symbols: `file <bin>` should not say "stripped".

3. **Capture a representative workload**. The single most important step.
   - Whatever the user says is the bottleneck — run the workload that exercises it.
   - Run for **long enough**: at least 30 seconds for stable sampling, longer for bursty workloads.
   - If the bottleneck is on a cold path, find a way to trigger it repeatedly.
   - For sub-second issues, profile a benchmark loop, not the production workload.

4. **Run the profiler** with the `[log]` marker:
   ```bash
   # Native, perf
   perf record --call-graph=fp -F 999 -- ./target_binary <args>
   perf report --stdio | head -60
   
   # Native, samply (cross-platform, friendlier UI)
   samply record ./target_binary <args>
   
   # Python
   py-spy record -o profile.svg --pid <pid>
   py-spy top --pid <pid>     # live top-style view
   
   # Rust release, with criterion's pprof
   cargo bench --bench <name> -- --profile-time 30
   
   # Go
   go test -cpuprofile cpu.prof -bench=. <pkg>
   go tool pprof -top cpu.prof | head -30
   go tool pprof -http=:8080 cpu.prof   # interactive
   ```
   Mark with `[log: profiling <target> for <suspected hot path>]`.

5. **Generate a flamegraph** if the user has the tooling:
   ```bash
   # perf → folded → flamegraph.pl
   perf script | inferno-collapse-perf | inferno-flamegraph > flame.svg
   # samply already shows one in its UI
   # py-spy --format flamegraph -o flame.svg ...
   ```

6. **Interpret the output**:
   - Look at **inclusive time** (self + descendants) for "where to start digging".
   - Look at **exclusive time** (self only) for "what's actually slow at this level".
   - Top 10 functions by inclusive time → these get attention. Below the top 10, ignore unless the user has a specific question.
   - Lots of time in `__memcpy_avx_unaligned` / `memmove` / allocator → it's not the allocator's fault, it's whoever's calling it. Look at the caller.
   - Lots of time in lock acquire → contention. Different problem; see `concurrency-and-async`.

7. **Report**:
   - Top 5 hotspots with self time, inclusive time, % of total.
   - Surprises ("expected X to dominate, actually Y does").
   - Concrete next-step recommendations — *which function* to look at, not "optimize the algorithm."
   - Where the flamegraph SVG was saved.

## Hard rules

- **Never claim X is slow without a profile.** Your intuition is wrong as often as right.
- **Always profile release builds.** Debug-build hotspots are misleading.
- **Don't optimize anything below the noise floor.** A function at 0.3% of total isn't worth touching.
- **Don't profile in CI/under-load environments without isolating.** Noisy neighbors corrupt the signal.

## See also

- `performance-analysis` skill — fundamentals, methodology.
- `/bench` — measure timing of a target, not its breakdown.
- The `perf-analyst` agent — runs profile + bench together and produces a written report.
