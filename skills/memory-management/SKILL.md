---
name: memory-management
description: Memory management discipline for C, C++, and Zig — ownership rules, allocator selection, lifetime tracking, and the standard tooling (valgrind, ASan, MSan, heaptrack, massif). Use when writing or reviewing code that allocates, when triaging a use-after-free / double-free / leak / overflow, when picking an allocator, or when explaining lifetimes in an FFI boundary. Pairs with `debugging-workflow` (sanitizer output triage), `concurrency-and-async` (atomics + memory ordering), and `language-interop` (ownership across FFI). Trigger on `malloc`/`free`/`new`/`delete`/`unique_ptr`/`shared_ptr`/`Allocator`/`arena`/`alloca`, on UAF/leak/overflow symptoms, or on questions like "who owns this", "when does this get freed".
---

# Memory management

The user works in C, C++, and Zig — three languages where memory is your problem. Python doesn't escape this either when you're writing extensions or holding C-allocated memory across the FFI. This skill covers the working set: ownership rules per language, allocator selection, the standard bug taxonomy, and the tools to find them.

## Ownership rules — single-sentence per language

- **C**: every `malloc`-family return value has *exactly one* owner. The owner is responsible for the matching `free`. If ownership transfers, document it in the function signature *and* the comment. There are no compiler enforcements; discipline is the entire game.
- **C++**: prefer **RAII** — the destructor frees what the constructor acquired. `std::unique_ptr<T>` is the default smart pointer. `std::shared_ptr<T>` is for genuinely-shared ownership and should be explained when used. Raw `new`/`delete` outside RAII is suspect; raw `malloc`/`free` in C++ is suspect-er.
- **Zig**: every allocation passes through an explicit `std.mem.Allocator`. The allocator that allocated *must* be the allocator that frees. There is no global allocator — functions that allocate take an allocator parameter and document its required lifetime.

## C: the discipline

### Pairing rule

Every `malloc` / `calloc` / `realloc` / `strdup` / `getline` / `asprintf` etc. pairs with exactly one `free` on a path you can name. If you can't name it, the code is wrong.

### Common patterns

- **Caller-owns**: function returns a pointer the caller frees.
  ```c
  // Returns malloc'd buffer; caller frees.
  char *read_file(const char *path);
  ```
- **Callee-owns + out-param**: function fills a caller-owned buffer.
  ```c
  // Caller provides buf and cap. Returns bytes written, or -1 on error.
  ssize_t encode(const struct foo *in, char *buf, size_t cap);
  ```
- **Container-owns**: function adds an item to a container that owns it.
  ```c
  // After this call, item is owned by list; do not free it.
  void list_push(struct list *l, struct item *item);
  ```

State the convention in the function comment. Always.

### Sentinel values

When a struct contains pointers, set them to `NULL` after free. Then double-free becomes a no-op (`free(NULL)` is defined as a no-op) and reads catch the bug immediately. The cost is one store per free; pay it.

### `realloc` discipline

`realloc(ptr, 0)` is implementation-defined. `realloc(NULL, n)` equals `malloc(n)`. On failure, `realloc` returns `NULL` *and the original pointer is still valid* — never write `p = realloc(p, n)` because you'll leak on failure. Use a temporary:

```c
void *tmp = realloc(p, n);
if (!tmp) { /* handle without losing p */ }
p = tmp;
```

### `strncpy` is not safe-`strcpy`

`strncpy(dst, src, n)` doesn't NUL-terminate if `strlen(src) >= n`. Use `snprintf(dst, n, "%s", src)` or ensure NUL by hand. `strlcpy` (BSD) is the real safe version; not in glibc, but available in many builds.

## C++: the discipline

### Smart pointers, in order of preference

1. **Stack object** — the simplest "smart pointer" is no pointer at all. Default to value semantics.
2. **`std::unique_ptr<T>`** — sole owner. Move-only. The standard for "this function returns a heap object."
3. **`std::shared_ptr<T>`** — shared ownership. Has a real cost (atomic refcount, control block allocation). Justify in a comment why shared and not unique.
4. **Raw pointer (non-owning)** — observation only. Document non-owning in the type if possible (`gsl::not_null<T*>`, `T&` for required, `T*` for optional non-owning).

### Move semantics

If a type owns a resource (file handle, allocation, lock), make it **non-copyable, move-only** unless you have a specific reason to allow copy. Default `= delete` the copy ctor and copy-assign:

```cpp
class FileHandle {
public:
    FileHandle(const FileHandle&) = delete;
    FileHandle& operator=(const FileHandle&) = delete;
    FileHandle(FileHandle&&) noexcept = default;
    FileHandle& operator=(FileHandle&&) noexcept = default;
    ~FileHandle() { if (fd_ >= 0) close(fd_); }
private:
    int fd_ = -1;
};
```

`noexcept` on the move ctor matters — STL containers fall back to copy when move is throwing.

### `std::shared_ptr` cycles

Two shared_ptrs that point at each other never get destroyed. Use `std::weak_ptr` to break the cycle on the back-edge.

### Don't `delete this`

The lifetime of an object should be controlled from outside. `delete this` is a code smell that almost always indicates an ownership bug.

## Zig: the discipline

### Explicit allocator threading

Every function that allocates takes an `std.mem.Allocator` argument. The caller picks the allocator and is responsible for the lifetime contract. There is no implicit global allocator.

```zig
fn parse(allocator: std.mem.Allocator, input: []const u8) !Parsed {
    const tokens = try allocator.alloc(Token, input.len);
    errdefer allocator.free(tokens); // critical
    ...
}
```

`errdefer` is the killer feature. A function that allocates and may fail later **must** `errdefer` the cleanup. Without it, an error path leaks.

### Allocator selection

Zig's stdlib gives you the menu — pick the right tool:

| Allocator | Use when |
|---|---|
| `std.heap.GeneralPurposeAllocator` | Default. Detects leaks, double-frees, UAF in safe builds. Slow, **for development**. |
| `std.heap.c_allocator` | Production after profiling, or when interfacing with C. |
| `std.heap.ArenaAllocator` | Many small allocations with one shared lifetime. Free everything at once via `deinit`. |
| `std.heap.FixedBufferAllocator` | All allocations fit in a pre-sized stack/static buffer. Embedded, hot path. |
| `std.heap.page_allocator` | Page-sized allocations. Direct `mmap`/`VirtualAlloc`. |
| `std.testing.allocator` | Tests. Asserts no leaks at end of test. Use this in every test. |

State the allocator choice and its lifetime in a comment when it's non-obvious.

### Slices vs many-pointer

`[]T` carries length; `[*]T` doesn't. Pass slices except across FFI. A common bug is taking `[*]T` from C and forgetting to track length.

## Allocator selection in C/C++

For workloads beyond "use the system malloc":

| Allocator | Use when |
|---|---|
| **System (glibc, jemalloc, mimalloc)** | Default. Modern alternatives often outperform glibc's ptmalloc by ≥2× under contention. Try jemalloc/mimalloc before optimizing. |
| **Arena / region** | Many small allocations sharing a lifetime (parser, request handler). Free in O(1) at the end, no per-alloc bookkeeping. |
| **Pool / slab** | Many same-size objects (sessions, packets). O(1) alloc/free, no fragmentation. |
| **Slab + freelist** | Pool with explicit freelist for cache-friendly recycling. |
| **`alloca` / VLA** | Stack-allocated, function-scope. Bounded size only. Don't use in a loop. |

A switch to jemalloc or mimalloc is often the highest-leverage one-line change for fragmentation-bound or contention-bound C/C++ workloads. Verify with a benchmark.

## The bug taxonomy

| Bug | Symptom | Tool |
|---|---|---|
| **Use-after-free** | Crash with surprising read, or wrong-looking data | AddressSanitizer (best), valgrind, GPA |
| **Double free** | `free(): invalid pointer`, or silent heap corruption | ASan, valgrind, glibc tcache hardening, GPA |
| **Buffer overflow (stack)** | Crash on return, mangled locals, canary failure | ASan, `-fstack-protector-strong`, FORTIFY |
| **Buffer overflow (heap)** | Heap corruption, later crash far from cause | ASan, valgrind |
| **Read of uninitialized memory** | Nondeterminism, "works in debug, breaks in release" | MemorySanitizer, valgrind |
| **Memory leak** | RSS grows, OOM-killer eventually | LeakSanitizer (part of ASan), heaptrack, massif |
| **Wild pointer write** | Far-distance crash, hard to localize | ASan, debug allocator with guard pages |
| **Type confusion (C++)** | Crash on virtual dispatch, vtable garbage | UBSan with `-fsanitize=vptr` |
| **Aliasing violation** | "Optimizer broke my code" | UBSan with `-fsanitize=alignment,object-size` |

## Tooling — the actual commands

```bash
# AddressSanitizer + LeakSanitizer + UBSan — the default dev build
clang -O1 -g -fsanitize=address,undefined -fno-omit-frame-pointer src.c -o app
ASAN_OPTIONS=detect_leaks=1:abort_on_error=1:strict_string_checks=1 ./app

# MemorySanitizer (Clang only) — for uninit reads. Needs MSan-instrumented libc.
clang -O1 -g -fsanitize=memory -fno-omit-frame-pointer src.c -o app

# valgrind — works on uninstrumented binaries; slow but no rebuild needed
valgrind --leak-check=full --show-leak-kinds=all --track-origins=yes ./app

# heaptrack — sampled allocation profiler
heaptrack ./app && heaptrack_gui heaptrack.app.*.gz

# massif — heap-over-time
valgrind --tool=massif ./app && ms_print massif.out.*
```

ASan should be the default for `-DDEBUG` builds. The 2× slowdown is a non-issue compared to the bug-finding value. Ship release builds without it but always keep an ASan build green in CI.

## Lifetimes across FFI

The single most important question at an FFI boundary: **who frees?**

- **Caller frees**: most common. Rust `String::from_raw` style — the C side calls a free function exposed by the Rust side. Document the free function name in the API.
- **Callee frees**: rare and risky. Don't unless the boundary owns the memory's allocator.
- **Borrowed**: pointer + length, valid only for the call. Never escape it. The receiver must copy if it needs longer lifetime.

The Python C extension worst-case is "Py_DECREF the input but it was a borrowed reference" — own/borrow confusion. Document every reference's status with the standard `[in]`, `[out]`, `[in,out]`, `[steals reference]` etc. notation in CPython.

## Stack vs heap

- **Stack**: cheap, automatic lifetime, bounded size (default 8 MB on Linux, less elsewhere). Use for everything that fits and has function-local lifetime.
- **Heap**: arbitrary size, arbitrary lifetime, expensive (malloc isn't free).
- **Stack-overflow risk**: large arrays, deep recursion, big stack frames in tight loops. Watch for `char buf[1 * 1024 * 1024]` in any function — that's 1 MB per call.

A function that allocates >4 KB on its stack should usually allocate on the heap instead. Heap allocations show up in profilers; stack overflows just crash.

## Don't fight the language

Each language has a memory style. Don't import another language's idioms wholesale:

- C with C++-style "everything is a smart pointer" via macros: usually worse than disciplined C.
- C++ with C-style raw `malloc`/`free` everywhere: leaks RAII benefits.
- Zig with hidden global allocators: defeats the explicit-allocator design.

Match the language. The standard library and tooling assume you're playing by its rules.
