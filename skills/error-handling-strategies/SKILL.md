---
name: error-handling-strategies
description: How to model, propagate, and handle errors across Python, C, C++, and Zig — without swallowing bugs or producing 50-line stack traces nobody reads. Use when designing the error model for a new module/library, deciding between exceptions and error returns, wrapping/contextualizing errors, classifying retryable vs terminal failures, or critiquing existing error handling. Pairs with `software-engineering-practices` (the "fail loud, fail early" principle) and `observability` (errors as a primary metric/log signal). Trigger on questions like "should this throw or return", "how do I add context to this error", "is this retryable", "why is this `except` suspicious", on `try`/`except`/`raise`, `Result`, `errno`, `error` returns, Zig error sets, or C++ exceptions.
---

# Error handling strategies

The user's first principle is "fail loud, fail early — never silently swallow." This skill translates that principle into language-specific patterns and the design decisions you make at module boundaries.

## The four error models

Every language uses a mix of these. Pick *one* per module and use it consistently.

| Model | Languages | Strengths | Weaknesses |
|---|---|---|---|
| **Exceptions** | C++, Python | Cheap on success path, automatic propagation, rich type | Hidden control flow, tax on exception-unsafe code, RTTI cost |
| **Result/Either** | Rust, Zig (error union), C++ via `std::expected` (C++23) / `tl::expected`, `Result<T, E>` libs in Python | Explicit, exhaustive, type-checked | Verbose at call site (mitigated by `?`/`try`) |
| **Error codes + out-param** | C, syscalls | Universal, no hidden costs | Easy to ignore, no destructor cleanup |
| **Sentinel value** | C string functions, `read()` returning -1 | Fits in one return slot | Only works when one value is unambiguously "error" |

## Pick by language idiom

- **Python**: exceptions. Don't return `None` for failures unless the failure is truly an absence-of-value (Optional). Don't smuggle `Result` types unless the codebase is already committed to that style.
- **C**: error codes + out-param, or a per-module error enum + `errno`-style thread-local. Use a small set of codes. Document which functions set errno.
- **C++**: pre-C++17, exceptions. Post-C++23, `std::expected<T, E>` is the modern choice for *predictable* errors (parse failures, lookup misses). Reserve exceptions for truly exceptional. Be consistent within a module.
- **Zig**: error unions (`!T`) end of story. The compiler enforces handling; lean into it.

## The principle: never silently swallow

The user's hard rule. Every error must do **one** of:

1. **Be propagated** to the caller (with context).
2. **Be handled** with documented intent (retry, fall back, default value, log + continue).
3. **Crash the program loudly** when invariants have been violated and recovery is dangerous.

A bare `except: pass`, an ignored return value, a `_ = some_fallible_call()`, or a `try { ... } catch (...) {}` is a code-review blocker unless accompanied by a comment explaining *why* swallowing is the right answer.

## Wrapping vs replacing

When propagating an error up the stack, you almost always want to **wrap** (preserve the cause + add context) rather than **replace** (lose the cause).

### Python

```python
try:
    config = json.loads(raw)
except json.JSONDecodeError as e:
    raise ConfigError(f"failed to parse {path}") from e   # `from e` preserves chain
```

The `from e` idiom is non-negotiable. Without it, the original traceback is lost and the consumer sees "ConfigError" with no cause.

### C++

```cpp
try {
    parse(raw);
} catch (const std::exception& e) {
    std::throw_with_nested(ConfigError("failed to parse " + path));
}
```

The receiver uses `std::rethrow_if_nested` to walk the chain. Verbose; consider whether your codebase has a richer error type that handles this for you.

### C

C has no built-in chaining. Roll a `struct error { int code; char *msg; struct error *cause; }` if the project needs it. Or maintain a per-thread error context buffer that callees append to. Either way, document the convention at the project level.

### Zig

```zig
fn parseConfig(allocator: std.mem.Allocator, path: []const u8) !Config {
    const raw = std.fs.cwd().readFileAlloc(allocator, path, 1 << 20) catch |err| {
        std.log.warn("read failed for {s}: {s}", .{ path, @errorName(err) });
        return error.ConfigReadFailed;  // wraps by replacing — Zig's error sets are flat
    };
    ...
}
```

Zig error unions are flat (no payload). For richer chains, attach context to a separate diagnostic struct (`std.zig.ErrorBundle` style) and return both.

## The error message is the API

When a user (or an oncall) sees the error, they need to:

1. Know **what** was being attempted ("loading config from /etc/foo/bar.json").
2. Know **what failed** ("file not found", "invalid JSON at line 47").
3. Have enough context to **act** (path, version, request id).

Bad: `"error: -1"`, `"failed"`, `"oops"`, `"can't connect"`, `"invalid input"`.

Good: `"failed to load config from /etc/foo/bar.json: file not found"`, `"refusing to write to /var/lib/foo: permission denied (running as uid=1000)"`.

**No stack-trace-as-error-message.** A 40-line stack trace shoved into a single error string is a sign the chaining is broken. Use the language's chaining.

## Trust boundaries: validate at the edge

Validate inputs at the boundary they enter your system. Once validated, **trust internally**.

- HTTP handler / RPC entry point: validate every field. Range, length, allowed values, schema.
- File loader: validate format and size *before* allocating proportional to it.
- FFI boundary: validate pointers (non-null), lengths, alignment.

Once a value has been validated and converted to a stronger type (`Username` instead of `str`, `NonNegativeInt` instead of `int`), don't re-validate at every internal call. The type *is* the validation.

## Retryable vs terminal

Classify errors into two buckets at the boundary:

- **Terminal**: the operation will not succeed if retried. Bad input, missing permission, resource not found, version mismatch. Surface immediately, don't retry.
- **Retryable**: transient — could succeed on retry. Network timeout, 5xx, lock contention, "EAGAIN", "EBUSY". Retry with backoff and a budget.

Retry hygiene:

- **Cap retries** (count or total time budget). Infinite retry is a stampede waiting to happen.
- **Exponential backoff with jitter** — `sleep(min(cap, base * 2^attempt) * uniform(0.5, 1.5))`. Without jitter, retries cluster and hammer the dependency.
- **Idempotency**: only retry idempotent operations, or attach an idempotency key. Retrying a non-idempotent POST is how you double-charge cards.
- **Circuit breaker** for repeated failures — after N retryable errors, fail fast for a cooldown period.

## Panic vs recover

A *panic* (Zig `unreachable`, Rust `panic!`, C++ `assert` / `std::terminate`, Python `raise SystemExit` / unhandled exception in entry, C `abort()`) is the right response when:

- An invariant has been violated. Recovery is undefined.
- Continuing risks data corruption.
- The bug is in *your* code, not the input.

A panic is the **wrong** response when:

- The input was bad. (Return an error; the input is bad, the program isn't broken.)
- The network failed. (Return an error; retry or surface.)
- A file didn't exist. (Return an error; tell the user.)

Distinguish bugs (panic) from valid-but-failed operations (errors). Conflating the two is the most common error-design mistake.

## Logging and errors

- **Log + propagate** is fine *if* you do it once. Logging at every layer of the stack produces the dreaded "the same error six times in the log."
- **Log + swallow** is the cardinal sin unless you're at a boundary that explicitly says "best-effort, don't fail."
- **Log + return default** can be right for non-critical paths (telemetry submission, optional cache fill). Always document.
- **Don't log the same error at WARN here and ERROR three frames up.** Pick one log site per error.

The log message should match the error message — different wording for the same condition is confusing in postmortem.

## Don't `except Exception`

In Python, catching the bare `Exception` class catches everything except `KeyboardInterrupt` and `SystemExit`. Consequences:

- Catches `MemoryError`, `RecursionError`, programming bugs (typos, attribute errors).
- Catches `asyncio.CancelledError` — masking cancellation.
- Hides the actual exception from logs unless you re-raise.

Catch the **specific** exception types your code actually expects. Add a narrow `except Exception` only at boundaries (top of an HTTP handler, top of a task runner) and **always** with logging + re-raise (or a controlled, documented swallow).

## C-specific: errno

- `errno` is thread-local on POSIX. Stash it immediately after the failing call — any subsequent libc call may overwrite it.
- Don't rely on `errno` after a function that doesn't document setting it.
- `strerror_r` / `strerror_l` for thread-safe descriptions; `strerror` is not thread-safe.

## C++-specific: exception safety

Three levels, from weak to strong:

1. **Basic guarantee**: invariants hold; resources don't leak; some state may be modified.
2. **Strong guarantee**: operation is atomic — succeeds or has no effect.
3. **No-throw guarantee**: operation cannot throw. Required for destructors, swap, move ctors of types stored in STL containers.

The standard pattern for strong guarantee is "copy-and-swap." Mark `noexcept` on functions that genuinely can't throw; the compiler relies on it for optimizations and STL containers fall back to slower paths if move-ctors aren't `noexcept`.

## Error model for libraries

When designing a library:

1. **Pick one error type** for the whole library. Don't mix `int` returns, `enum` returns, exceptions, and `Result` in one API surface.
2. **Document every error** the function can produce. List them in the docstring/header.
3. **Don't leak internal error types** unless they're part of the contract. A SQL adapter shouldn't expose Postgres-specific error codes; translate to the library's error type.
4. **Versioning the error type is a breaking change.** Be conservative.

## Error model for binaries / services

- Distinguish **operator errors** (config wrong, dependency down) from **user errors** (bad request) from **bugs** (assertion failed). Different exit codes, different log levels, different alerting.
- Set a real exit code. `0` = success, non-zero = failure, with a documented mapping per CLI.
- Print errors to **stderr**, not stdout. Stdout is for the program's data output.

## Anti-patterns to flag in review

- `except: pass` (Python) — almost always wrong.
- `} catch (...) {}` (C++) — almost always wrong.
- `if (err) { /* TODO */ }` — TODOs in error paths rot. The bug ships.
- Translating a rich error to a string and discarding the original.
- Returning a sentinel and not documenting it (`-1`, `NULL`, `""`).
- "Just retry forever" without a budget.
- `raise` re-raise inside `except` that doesn't preserve the cause (Python pre-`from e` style).
- `errors.New("error")` / `RuntimeError("error")` — message duplicates the type. Worse than no message.
- `panic` in a library function. Libraries should *return* errors; the application chooses the panic.
