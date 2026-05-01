---
name: performance-analysis
description: Methodology and tooling for performance work — perf, flamegraphs, cachegrind/callgrind, hyperfine for whole-program benchmarks, criterion / Google Benchmark / pytest-benchmark for microbenchmarks. Covers when to measure, how to avoid the standard pitfalls (premature optimization, benchmarking the wrong thing, ignoring noise), and how to write performance regressions into the test suite. Use this skill whenever the user asks about speed, memory use, profiling, hotspot analysis, or "is this fast enough."
---

# Performance Analysis

Performance work without measurement is fiction. This skill is about doing it right.

## The methodology

1. **State the goal.** "Make function X faster" is not a goal. "Reduce p99 latency of `parse_request` below 5ms on Linux x86_64 with input <= 4KB" is.
2. **Establish a baseline.** Measure the current state under a representative workload, on the hardware the workload actually runs on. Capture the number with units, environment, and command line.
3. **Find the hotspot.** Profile. Don't guess. Engineers' guesses about where time goes are wrong more often than not.
4. **Form a hypothesis about why it's slow.** Cache misses? Allocations? Lock contention? Algorithmic complexity? Syscall overhead?
5. **Make one change at a time.** Re-measure. Compare. If the change didn't help, revert. If it did, lock it in with a benchmark.
6. **Stop when the goal is met.** Not before, not after.

## Premature optimization

The user is a senior engineer and knows the line. Worth restating anyway:

- **Don't optimize before profiling.** Even on hot loops, your intuition about which line is slow is usually wrong.
- **Don't sacrifice readability for a 1% win.** Lock that in only if there's a good reason (it's actually a hot path *and* it shows up in your profiler).
- **Algorithmic wins beat micro-optimizations.** O(n²) → O(n log n) is worth more than every micro-optimization combined. Always look at complexity first.
- **Don't optimize for benchmarks alone.** A real workload mixes inputs, sizes, and timing in ways microbenchmarks miss.

## Tools by question

| Question | Tool |
|---|---|
| Where does CPU time go? | `perf record` + `perf report`, or flamegraph |
| Why is *this specific function* slow? | `perf annotate`, callgrind, vtune |
| Cache behavior? | `perf stat -e cache-misses,cache-references`, cachegrind |
| Branch prediction? | `perf stat -e branches,branch-misses` |
| Memory: leaks? | ASan + LeakSanitizer, valgrind/memcheck, heaptrack |
| Memory: allocation patterns? | heaptrack, jemalloc/tcmalloc profiler, massif |
| Whole-program latency? | `hyperfine` |
| Microbenchmark a function? | criterion (Rust), Google Benchmark (C++), pytest-benchmark (Py) |
| Latency tail (p50/p99/p999)? | Application-level histogram (HdrHistogram), `perf sched` for kernel-side |
| Lock contention? | `perf lock`, mutrace, TSan (also catches contention, with caveats) |
| Syscall cost? | `strace -c`, `perf trace` |
| GPU? | nsys (Nsight Systems), nvprof legacy, ROCm equivalents |

## perf

The Swiss Army knife of Linux performance. The user is on Linux.

Setup once:
```
sudo sysctl kernel.perf_event_paranoid=1   # or 0/-1 for full access during a session
sudo sysctl kernel.kptr_restrict=0          # to see kernel symbols
```

Capture a profile:
```
perf record -F 999 -g -- ./mybin --my-args
perf report --no-children --stdio | head -50
```

`-F 999` is the sample rate. Avoid powers of 2 (alignment with periodic timers). `-g` enables call graphs.

For C++ / Rust, demangling: `perf report --demangle`.

Frame pointers matter. Build with `-fno-omit-frame-pointer` or perf's stack walking falls apart. Modern perf can use DWARF (`--call-graph dwarf`) but it's slower and produces bigger captures.

## Flamegraphs

Brendan Gregg's flamegraph is still the best visual. Pipeline:

```
perf record -F 999 -g -- ./mybin --my-args
perf script | stackcollapse-perf.pl | flamegraph.pl > flame.svg
```

Or use the Rust port `inferno`:
```
perf script | inferno-collapse-perf | inferno-flamegraph > flame.svg
```

How to read one:
- **Width** = time on CPU (or whatever you sampled). Wide = expensive.
- **Height** = call depth. Tall doesn't mean expensive.
- **Plateaus at the top** = self-time hotspots. That's what you want to optimize.
- The y-axis order is alphabetical by default — that's fine, ignore the impulse to read it as time order.

## hyperfine

Best tool for "is version A faster than version B" at the whole-program level.

```
hyperfine --warmup 3 --min-runs 20 \
  './mybin --old-config input.bin' \
  './mybin --new-config input.bin'
```

It handles statistics, noise, outliers. It will warn if there's too much variance to draw conclusions — listen to it.

For tools that do I/O, use `--prepare` to clear the page cache between runs (`sync; echo 3 | sudo tee /proc/sys/vm/drop_caches`) if the goal is cold-start measurement.

## Microbenchmarks

| Language | Library |
|---|---|
| Python | `pytest-benchmark`, `timeit` for one-offs |
| C | Google Benchmark (yes, it's C++ but works for benchmarking C code) |
| C++ | Google Benchmark |
| Rust | `criterion` |
| Zig | `std.testing.benchmark` is rudimentary; consider rolling your own with `std.time.Timer` |

Microbenchmark pitfalls:
- **The optimizer might delete your test.** Use `benchmark::DoNotOptimize` (Google Bench) or `std::hint::black_box` (Rust) on the result.
- **Cold cache vs hot cache** matter. Most benchmark libs warm up; check that yours does.
- **Per-call overhead** can dwarf what you're measuring. If a function runs in nanoseconds, benchmark a batch.
- **Power management** changes results. Disable turbo (`cpupower frequency-set -g performance`) and pin to a core (`taskset -c 3`) for stable numbers.

## Cache analysis (cachegrind / callgrind)

When you suspect cache effects but `perf stat -e cache-misses` isn't precise enough:

```
valgrind --tool=cachegrind --cache-sim=yes ./mybin args
cg_annotate cachegrind.out.<pid>
```

Slow (10–50x runtime), but deterministic — same number every run. Useful for catching tiny improvements that get lost in `perf` noise.

Callgrind for callgraph + cache:
```
valgrind --tool=callgrind ./mybin args
kcachegrind callgrind.out.<pid>
```

## Memory profiling

- **heaptrack** — best Linux heap profiler. Records every allocation, lets you flamegraph by bytes-allocated and bytes-leaked. `heaptrack ./mybin args` then `heaptrack_gui heaptrack.mybin.<pid>.gz`.
- **massif** — older valgrind tool. Slower but works without rebuild. Visualize with `ms_print`.
- **jemalloc / tcmalloc profilers** — when the project links one of those allocators, their built-in profilers are excellent.

## Latency vs throughput

Don't conflate them.

- **Throughput** = work per unit time. Easy to measure: `total / elapsed`.
- **Latency** = time per request. Has a *distribution*. Measure as a histogram, report p50/p90/p99/p999/max.

A change that improves throughput can hurt p99 (e.g., adding batching). Always check both.

For latency: HdrHistogram is the standard. `perf sched` shows kernel-side scheduling latency, which is invisible to most app-level measurements.

## Performance regression tests

Once you've optimized something, lock it in:

- For library functions: a benchmark in the test suite that asserts a *floor* on speed (`assert duration < threshold`). Set the threshold with margin — say 2x the measured number — to absorb noise.
- For end-to-end latency: a CI job that runs `hyperfine` on representative workloads and fails if the mean exceeds the threshold.
- Always pin the hardware. CI runners vary; either run on dedicated hardware or use `--warmup` and a permissive threshold.

The goal: a future regression breaks the build, not production.

## Things to avoid

- Profiling debug builds. The hotspots are different.
- Profiling with sanitizers on. ASan in particular distorts everything.
- Drawing conclusions from a single run. Run at least 3 times; ideally 10+ for noisy workloads.
- Comparing across kernel versions / libc versions / hardware without saying so.
- Optimizing code that runs once at startup.
- "It feels faster." If you can't measure it, you didn't improve it.
- Premature SIMD / inline assembly. Compilers are usually better than your hand-rolled version.

## Reporting performance work

When the change is done, the commit message or PR description should say:

- **Workload:** what was measured.
- **Hardware:** CPU, RAM, kernel, governor.
- **Before:** number with units (e.g., `mean 124ms ± 4ms over 20 runs`).
- **After:** same.
- **Why it's faster:** root cause, in one paragraph.

Without those, the win is unaudited and will silently regress.
