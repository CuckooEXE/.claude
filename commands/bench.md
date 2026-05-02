---
description: Set up or extend a benchmark harness for the project — language-native bench framework or hyperfine for whole-binary timing.
argument-hint: [target — function/module/binary to benchmark, optional]
allowed-tools: Bash(hyperfine:*), Bash(python:*), Bash(pytest:*), Bash(cargo:*), Bash(go:*), Bash(zig:*), Bash(make:*), Bash(cmake:*), Bash(ls:*), Bash(test:*), Read, Edit, Write, Glob
---

# /bench — set up or extend a benchmark

Goal: produce **trustworthy, reproducible timing numbers** for the named target. Microbenchmarks for hot functions; whole-binary benchmarks for end-to-end latency.

Argument: `$ARGUMENTS` — the target. May be a function name, file, module, or binary path. If empty, ask what to benchmark.

## Procedure

1. **Identify the language and existing harness** in parallel:
   - Detect via manifest files (`pyproject.toml`, `Cargo.toml`, `go.mod`, `build.zig`, `CMakeLists.txt`).
   - Check for existing benchmark infra: `benches/` (Rust), `tests/bench_*.py` (Python), `_test.go` with `func Benchmark`, `benchmark/` directories.
   - If a harness exists, **extend it** rather than starting fresh.

2. **Pick the right tool** — match the granularity to the target:

   | Target | Tool |
   |---|---|
   | Hot Python function | `pytest-benchmark`, or `timeit` for one-offs |
   | Hot Rust function | `criterion` (statistical), or `cargo bench` (built-in, simpler) |
   | Hot Go function | `go test -bench=.` with `testing.B` |
   | Hot C/C++ function | Google Benchmark (`benchmark::DoNotOptimize`, `benchmark::ClobberMemory`) |
   | Hot Zig function | `std.time.Timer` in a function tagged with `test`, or roll a small loop with `std.time.nanoTimestamp()` |
   | Whole binary / CLI | `hyperfine --warmup 3 --runs 20 -- '<cmd>'` |

3. **Scaffold or extend**:
   - For a new harness, create the conventional file (`benches/<target>.rs`, `tests/bench_<target>.py`, `<target>_bench.cc`, etc.) using the project's existing style.
   - For an existing harness, add a new benchmark function next to the others.
   - For a binary-level benchmark, write a small `bench.sh` or add a `Makefile` target that invokes `hyperfine` with the right warmup/run counts.

4. **Microbenchmark hygiene** (lean on `performance-analysis` skill):
   - **Disable optimizer dead-code elimination**: feed inputs from `volatile` reads or `benchmark::DoNotOptimize` (Google Bench), `black_box` (criterion / Rust nightly), `_ = result` is *not* enough in C/C++.
   - **Vary inputs across iterations** when measuring algorithms with branch-prediction sensitivity.
   - **Pin CPU governor** if the user is on Linux and chasing < 1% noise: `sudo cpupower frequency-set -g performance`. State this as a recommendation, not a forced action.
   - **Disable turbo and SMT** for sub-percent-noise work — same caveat about user permission.
   - **Warmup** runs aren't optional. 3–5 warmup iterations before the timed run.
   - **Collect at least 20 samples** so percentiles mean something.

5. **Run the benchmark** with the marker `[log: baseline benchmark for <target>]` so the result lands in the command log. The output (best/median/p95/p99) is exactly the kind of artifact the user wants in the timeline.

6. **Report** with:
   - The numbers, plain.
   - The setup (CPU model, governor, runs, warmup).
   - A baseline note if this is the first run, or a delta vs the previous run if history exists.
   - Any noise concerns flagged ("variance is 12%, noise floor too high to detect <10% regressions — consider pinning CPU").

## Don't

- Don't claim a perf win without a confidence interval. "5% faster on n=20 with 4% std-dev" is not a real win; "20% faster on n=100 with 1% std-dev" is.
- Don't benchmark with debug builds. Always release/optimized builds.
- Don't rely on `time(1)` for sub-ms measurements. Use `hyperfine` or a real harness.
- Don't add a benchmark that takes > a few seconds without an explicit `--quick` mode for inner-loop dev.
- Don't commit benchmark output as test fixtures — it changes per machine. Commit the harness and a recent results file in `bench/results/<date>.txt` if you want history.

## See also

- `performance-analysis` skill — methodology, tools, when timing is misleading.
- `/profile` — profile rather than benchmark when you need to know *where* the time is going.
- The `perf-analyst` agent — wraps benchmarking + profiling and produces a written report.
