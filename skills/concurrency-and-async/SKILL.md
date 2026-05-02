---
name: concurrency-and-async
description: Concurrency models, primitives, and bug patterns across Python, C, C++, and Zig. Use when introducing or reviewing threads, async/await, atomics, locks, channels, futures, coroutines, or signal handlers — or when triaging a hang, deadlock, race, or "works on my machine" intermittent. Pairs with `debugging-workflow` (race-detection tooling) and `memory-management` (memory orderings sit at the boundary of both). Trigger on questions like "do I need a lock here", "why is this hanging", "is this thread-safe", "should I use threads or async", or any code change that touches `pthread_*`, `std::thread`, `asyncio`, `await`, `@async`, `Mutex`, `atomic`, etc.
---

# Concurrency and async

Concurrency is the area where *correct yesterday* doesn't imply *correct today*. The bugs are timing-dependent, the test signal is noisy, and the cost of "looks fine, ship it" is years of intermittent oncall. This skill is the working set of patterns and pitfalls per language.

## Pick the right model first

Before reaching for primitives, pick a model. Picking wrong is the most common root cause.

| Model | Use when | Don't use when |
|---|---|---|
| **Single-threaded + select/poll/epoll/io_uring** | Lots of I/O, little CPU per request | CPU-bound work blocks the loop |
| **Async/await (asyncio, anyio, Zig async)** | Same as above, but you want function-coloring discipline | You need to call sync libraries that block — they'll wedge the loop |
| **Threads + locks** | CPU-bound *and* shared mutable state | The shared state is large; favor message passing |
| **Threads + channels (message passing)** | Concurrent work with logical pipelines, no shared mutable state | You need synchronous request/response with shared cache |
| **Multiprocessing** | CPU-bound, GIL-constrained Python, or strong isolation | Sharing large state — copying dominates |
| **Lock-free / atomic-only** | Hot path, contention measured, primitive correctness verified | First implementation. Always start with a lock and only go lock-free under pressure with proof. |

State the chosen model in a comment at the top of the module. Future readers (and reviewers) need to know which rules apply.

## Python

- **GIL**: one thread runs Python bytecode at a time (CPython). Threads still help for I/O and for releasing the GIL inside C extensions. Free-threaded CPython (3.13+ `--disable-gil`) changes this — confirm Python version before relying on GIL guarantees.
- **`asyncio`**: cooperative. A blocking call (sync `requests.get`, `time.sleep`, big CPU) **stalls the entire loop**. Wrap with `loop.run_in_executor` or use `anyio.to_thread.run_sync` if unavoidable.
- **Structured concurrency**: prefer `asyncio.TaskGroup` (3.11+) or `anyio` over loose `asyncio.create_task`. Loose tasks are how you leak coroutines and swallow exceptions silently.
- **Cancellation**: `CancelledError` is a real exception; it propagates. Don't catch `Exception` and ignore — you'll mask cancellation. Catch `Exception` then re-raise `CancelledError`.
- **`threading.Lock` vs `asyncio.Lock`**: not interchangeable. The former blocks the OS thread; the latter yields to the loop. Mixing them is a deadlock vector.
- **Queues**: `queue.Queue` is for threads, `asyncio.Queue` is for the loop. Bridge with thread-pool executors.

## C

- **`pthread_*`**: still the lingua franca. Default mutex is `PTHREAD_MUTEX_NORMAL` — recursive lock from the same thread *deadlocks*. Use `PTHREAD_MUTEX_ERRORCHECK` while developing.
- **Memory orderings (C11 `<stdatomic.h>`)**: `memory_order_relaxed` is fine for counters that no one else reads-then-acts. `memory_order_acquire`/`release` is the standard pair for lock-free producer-consumer. `seq_cst` is the safe default; only weaken with proof. Don't invent your own ordering — model the access pattern after a known one.
- **Signal handlers**: only **async-signal-safe** functions. No `printf`, no `malloc`, no most-of-libc. The portable safe set is in `signal-safety(7)`. Set a `volatile sig_atomic_t` flag and check it from the main loop instead.
- **`fork()` + threads**: only async-signal-safe between fork and exec. The child has the parent's locks in their post-fork state — many of them are now held by ghosts. If you must `fork` after threads exist, `_exit` quickly or `execve` immediately.
- **TLS (thread-local storage)**: `__thread` (GCC/Clang) or `_Thread_local` (C11). Cheap to read, but constructors don't run for it — initialize on first use.

## C++

- **`std::thread`**: must be `join()`'d or `detach()`'d before destruction or `std::terminate` runs. Wrap with `std::jthread` (C++20) — auto-joins, supports cooperative cancellation.
- **`std::async(std::launch::async, ...)`**: launches a thread and returns a future. The future's destructor *blocks until the thread finishes* if the launch was async — silent serialization. Pin the policy explicitly; don't use the default.
- **`std::atomic<T>`**: same memory-ordering semantics as C11. `std::atomic<T>::is_lock_free()` may be false for big T — check before assuming.
- **Coroutines (C++20)**: stackless, function-coloring, requires a promise type. Almost always you want a library (`cppcoro`, `unifex`, the Asio coroutine integration) — hand-rolling is a footgun.
- **`std::shared_mutex`**: writer-starvation is implementation-dependent. Don't use for high-contention writes.
- **Singletons**: `static T instance;` inside a function gives you Meyers singleton — thread-safe initialization since C++11. Don't roll your own with double-checked locking.

## Zig

- **No async right now (post-0.11 reverted)**: as of recent versions, async/await is being redesigned. Use threads via `std.Thread` and explicit polling via `std.posix` (`poll`, `epoll`, `kqueue`) until the new async model lands.
- **`std.Thread.Mutex`**: standard recursive-unsafe mutex. There's `RwLock`, `Semaphore`, `Condition`.
- **Atomics**: `std.atomic.Atomic(T)` with explicit ordering parameters. Same semantics as C11 — `.acquire`, `.release`, `.acq_rel`, `.seq_cst`, `.monotonic` (== relaxed).
- **No GC + explicit allocators**: cancellation/cleanup discipline matters. A panicking goroutine-equivalent leaks any allocated state unless you `errdefer` correctly. See `memory-management`.

## Memory orderings — quick reference

If you're *not* writing lock-free code, use a lock and skip this section. The fact that `seq_cst` is "slow" doesn't matter unless profiling says it does.

- **Relaxed**: no ordering, just atomicity. Fine for counters where nobody reads-then-acts on the value.
- **Acquire**: pairs with release. Reads after acquire-load see writes before the matching release-store on the same atomic. Standard pattern: load-acquire on a "ready" flag, then read the data the producer wrote.
- **Release**: write the data, then release-store the "ready" flag. Pairs with acquire on the consumer side.
- **Acq_rel**: for read-modify-write where both sides matter. CAS loops typically use this.
- **Seq_cst**: a single global order. Slowest, but you can reason about it without modeling the hardware. Default if unsure.

## Common bugs and how to spot them

### Deadlock

- **Lock-ordering violation**: thread A holds L1, wants L2; thread B holds L2, wants L1. Fix: define a global lock order and document it.
- **Recursive deadlock**: same thread re-acquires a non-recursive lock. Fix: don't, or use recursive mutex (sparingly).
- **Self-wait**: thread waits on a condition only it can fulfill. Fix: separate the producer from the consumer.

Detection: gdb thread dump (`thread apply all bt`), `ps -L`, ThreadSanitizer.

### Race condition

- **Read-modify-write of shared state without synchronization**: classic counter race. Fix: atomic, or lock.
- **TOCTOU (time-of-check-to-time-of-use)**: `if (file_exists(p)) open(p)`. The file can vanish between the check and the open. Fix: try the action and handle the error, don't pre-check.
- **Publish-before-init**: writing the pointer to a partially-constructed object. Fix: release-store the pointer *after* the data, acquire-load on the reader side.

Detection: ThreadSanitizer (Clang/GCC), race-detector mode in your runtime.

### Livelock / starvation

- Two threads back off into each other's path forever (no progress). Fix: randomized backoff or give one priority.
- Reader-heavy `shared_mutex` starves writers. Fix: writer-preference policy or queue both.

### ABA

- CAS on a pointer/value that was changed and changed back. Looks unchanged to the CAS, but the world moved. Fix: tagged pointers, hazard pointers, RCU.

### Double-checked locking (the classic broken pattern)

```c
if (instance == NULL) {                  // unsynchronized read
    pthread_mutex_lock(&lock);
    if (instance == NULL) instance = ...; // store may be reordered
    pthread_mutex_unlock(&lock);
}
```

Broken on most architectures without explicit memory ordering. Use `pthread_once` / `std::call_once` / `std::atomic` with acquire-release semantics. Or: just initialize at startup and skip the dance.

## Backpressure

Unbounded queues are the silent killer of "this scaled fine in load test."

- **Bounded queue + block on full** — flow control propagates upstream automatically.
- **Bounded queue + drop on full** — explicit drops (with a counter), graceful when correctness allows.
- **Bounded queue + reject** — return an error to the producer; let it retry or shed load.

Pick one. Document the choice. An unbounded `Queue` that "just hasn't filled in production yet" is a future incident.

## Cancellation

- **Cooperative**: the cancelled task checks a flag/token. Standard for async (`asyncio.CancelledError`), Zig (`errdefer`), `std::stop_token`.
- **Preemptive**: rare and dangerous in user-space. `pthread_cancel` exists but interacts badly with C++ destructors. Avoid.

Always **document where cancellation can land**. A function that says "cancellation-safe" should describe what state is guaranteed at cancellation points (pre-X, post-X, atomic on X).

## Testing concurrent code

- **Stress + repeat**: run the test 1000× in a loop. If it fails 1/1000, that's not flake — that's a bug.
- **TSan**: build with `-fsanitize=thread` and run the test suite. Don't ignore warnings.
- **Permutation harness**: for short critical sections, exhaust the legal interleavings (loom in Rust, `std.Thread.simulate` in some Zig, manual instrumentation in C/C++).
- **Fault injection**: inject delays at suspect points to widen the race window. `usleep(1)` after the unlock to make racy code fail fast.

## Document the invariant, not the lock

Comment what the lock *protects*, not just that it exists. Future-you needs to know what's safe to read without it.

```c
// Protected by `state_lock`:
//   - active_sessions
//   - last_seen
// Atomic, no lock needed:
//   - request_count (relaxed-ordering)
```

Without this comment, every reader has to grep for the lock and reverse-engineer the policy.
