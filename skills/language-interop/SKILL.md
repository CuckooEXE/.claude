---
name: language-interop
description: FFI patterns, ABI considerations, and ownership/lifetime discipline at boundaries between Python, C, C++, and Zig. Covers Python C-extension options (ctypes, cffi, Cython, pybind11/nanobind, PyO3), Zig's `@cImport`, C as the lingua franca ABI, marshalling concerns, error propagation across the boundary, GIL release patterns, and string/buffer lifetime rules. Pairs with `memory-management` (ownership rules across the boundary) and `error-handling-strategies` (how errors translate). Trigger on `ctypes`, `cffi`, `cdef`, `extern "C"`, `pybind11`, `nanobind`, `PyO3`, `@cImport`, `@cInclude`, `setup.py` with `Extension(...)`, or any code that calls another language's library.
---

# Language interop

When you cross a language boundary, the rules of *both* languages apply at the seam, and *neither* language's compiler enforces them. Bugs at FFI boundaries are also where memory safety, error handling, and threading models all collide. This skill is the working set of patterns and gotchas for the user's stack.

## C is the lingua franca

When two non-C languages need to talk, the path is almost always through a C ABI:

- Python → Rust: PyO3 → C ABI → Rust.
- Python → Zig: ctypes → C ABI → `export fn` in Zig.
- Zig → C++: Zig speaks C; expose C++ as `extern "C"` shims.

Implications:

- Use C-compatible types at the boundary. No C++ classes, no Python objects, no Zig error unions.
- Pointers, integers, structs of those, and function pointers are universal.
- C strings (`char *` + length, NUL-terminated) is the universal string format.

The fewer types cross the boundary, the simpler the seam.

## Python ↔ C/C++/Zig — the option matrix

| Tool | Speaks to | Speed of dev | Speed of code | Use when |
|---|---|---|---|---|
| `ctypes` | Any C ABI | Fast | Slowest (per-call overhead) | Quick wrappers, one-off scripts, when you can't compile |
| `cffi` (ABI mode) | Any C ABI | Fast | Slow | Cleaner than ctypes; same use case |
| `cffi` (API mode) | C, with parsed headers | Medium | Medium | Production C bindings without C++ |
| **Cython** | C, C++ | Medium | Fast | Numerical hot loops in mostly-Python code |
| **pybind11** | C++ (header-only) | Medium | Fast | Mature C++ bindings; most-used in scientific Python |
| **nanobind** | C++ (modern, faster compile) | Medium | Fast | Same niche as pybind11; smaller, faster, C++17+ |
| **PyO3** | Rust | Medium | Fast | Rust libs, modern toolchain |
| **CPython C API** | C, C++ | Slow | Fast | Last resort or maximum-control situations |

Default recommendation: **`cffi` API mode for C, `nanobind` for C++ (or `pybind11` if you need broader compiler support)**. Both have clear ownership stories and don't lock you to a build system.

## ctypes — the simplest path

```python
import ctypes
lib = ctypes.CDLL("./libfoo.so")

# Declare signatures — required for correctness on non-x86_64
lib.parse_message.argtypes = [ctypes.c_char_p, ctypes.c_size_t]
lib.parse_message.restype  = ctypes.POINTER(ctypes.c_uint8)

# Call
result_ptr = lib.parse_message(b"hello", 5)
```

Gotchas:

- **Always set `argtypes` and `restype`.** Without them, ctypes infers `int` for everything → silent corruption on mismatched ABIs (especially returning pointers as `int`).
- **`bytes` not `str`.** `c_char_p` is `bytes`; `c_wchar_p` is `str`. Don't pass `str` to a `c_char_p` arg — it works on Python 3 by accident but breaks subtly.
- **Ownership**: if the C function returns a heap pointer, *Python won't free it*. You must call the matching free function. Wrap with a helper that does this on `__del__`.

## cffi — ABI mode vs API mode

ABI mode (cffi parses no headers, you describe the interface):

```python
from cffi import FFI
ffi = FFI()
ffi.cdef("uint8_t *parse_message(const char *buf, size_t len);")
lib = ffi.dlopen("./libfoo.so")
result = lib.parse_message(b"hello", 5)
```

API mode (cffi compiles a small extension that calls into the C library):

```python
ffi.cdef("uint8_t *parse_message(const char *buf, size_t len);")
ffi.set_source("_foo_cffi", '#include "foo.h"', libraries=["foo"])
ffi.compile()
```

API mode catches signature mismatches at compile time; ABI mode catches them only at call time (or worse, silently corrupts).

## C++ via pybind11 / nanobind

```cpp
// nanobind example
#include <nanobind/nanobind.h>
namespace nb = nanobind;

NB_MODULE(mymodule, m) {
    m.def("add", [](int a, int b) { return a + b; });
    nb::class_<MyClass>(m, "MyClass")
        .def(nb::init<int>())
        .def("compute", &MyClass::compute);
}
```

Build via `pip install nanobind` and a `pyproject.toml` extension config.

Strengths: type conversions are largely automatic for STL containers, smart pointers, etc. nanobind's compile is much faster than pybind11's, and runtime overhead is lower.

Pitfalls:

- **GIL discipline**: by default, the GIL is held during the C++ call. For long-running CPU work, release it: `nb::call_guard<nb::gil_scoped_release>()` (or pybind11's `py::call_guard<py::gil_scoped_release>()`). Without releasing, you serialize all Python threads.
- **Lifetime of returned references**: pay attention to `rv_policy::reference`, `take_ownership`, `automatic`. Wrong policy = double-free or dangling pointer.
- **Exceptions**: C++ exceptions translate to Python exceptions (`std::runtime_error` → `RuntimeError`). Custom mappings via `register_exception`.

## Zig ↔ C

```zig
const c = @cImport({
    @cInclude("foo.h");
});

pub fn parse(buf: []const u8) !void {
    const ret = c.parse_message(buf.ptr, buf.len);
    if (ret == 0) return error.ParseFailed;
}
```

`@cImport` parses C headers at compile time. Strengths: zero overhead, full type checking against the actual header.

Exposing Zig to C:

```zig
export fn add(a: c_int, b: c_int) c_int {
    return a + b;
}
```

Use `export` for C-visible symbols. Use `c_int`/`c_uint`/`c_long` etc. (not `i32`) at the boundary — sizes match the platform's C compiler.

Pitfalls:

- **Allocator at the boundary**: Zig has no global allocator. Functions called from C either need an allocator passed in or use a known allocator (`std.heap.c_allocator` is the standard for "the C side will free this").
- **Errors don't cross**: Zig error unions don't translate. Convert at the boundary: return a status code + out-param, or a tagged result struct.
- **Slices don't cross**: `[]const u8` in Zig is `(ptr, len)` — pass them separately when calling C / being called by C.

## Marshalling — the universal concerns

### Ownership

The single most-asked question at any FFI boundary. **Who frees this?** Document explicitly. Conventions per direction:

- **Caller-owns** (most common): callee returns a buffer, caller frees with a documented free function.
- **Callee-owns + temporary**: callee returns a pointer that's only valid until the next call. Caller copies if needed for later. Document loudly.
- **Callee-owns + ref-counted**: the FFI side has its own GC/refcount. Caller incs/decs.
- **Caller-provides + callee-fills**: caller passes a buffer and capacity; callee writes. Caller frees the buffer.

Mismatched ownership = leaks (best case) or use-after-free (worst case).

### Strings

C strings are NUL-terminated. Other languages aren't:

- **Python**: `str` is internally Unicode; encode to bytes (UTF-8 by default) for C. `bytes` has explicit length.
- **C++**: `std::string` is length-prefixed; `c_str()` gives NUL-terminated.
- **Zig**: `[]const u8` is length-prefixed; convert to `[*:0]const u8` for C calls expecting NUL.

When the source language's strings can contain embedded NULs (Python `bytes`, C++ `std::string`), and the C function uses `strlen` to find the end, **you have a bug.** Always pass length explicitly when possible.

### Encoding

A `char *` is just bytes. The encoding (UTF-8, ASCII, Latin-1, UTF-16-as-bytes) is a contract, not a property of the type. Document the encoding at the boundary.

Common bug: Python passes UTF-8 bytes; C library is locale-aware and interprets as Latin-1; everything looks fine for ASCII inputs and breaks for any non-ASCII character.

### Buffers and lifetimes

When passing a buffer:

- Document whether the callee may keep the pointer beyond the call. (Default: no.)
- Document whether the buffer can be modified by the callee. (Default: no, unless it's an out-param.)
- If callee needs to retain, callee must copy.

A common mistake in Python/ctypes: pass a Python `bytes` to a C function that stashes the pointer; Python GCs the bytes; C dereferences a freed pointer.

## Errors across the boundary

The styles don't translate. You need a convention.

### C → Python (via PyO3, pybind11, nanobind, cffi)

Modern bindings auto-translate C++ exceptions to Python. For raw C, set a Python error and return NULL/0:

```c
// Python C API style
static PyObject *foo_parse(PyObject *self, PyObject *args) {
    ...
    if (failed) {
        PyErr_SetString(PyExc_ValueError, "parse failed: ...");
        return NULL;
    }
    return result;
}
```

### Zig → C / Zig → Python (via Zig as C)

Zig errors don't cross. Pattern:

```zig
export fn parse(buf: [*]const u8, len: usize, out: *Result) c_int {
    const result = parseInternal(buf[0..len]) catch |err| {
        return @intFromEnum(toCError(err)); // -1, -2, ... mapped enum
    };
    out.* = result;
    return 0;
}
```

The integer return is the error code; the out-param is the result on success.

### Python → C/C++ (back the other way)

When a callback registered from Python is invoked from C:

- Acquire the GIL inside the callback (`PyGILState_Ensure` / `nb::gil_scoped_acquire`).
- Catch Python exceptions in the callback; translate to a C-friendly status.
- Don't let a Python exception propagate through C frames — undefined behavior.

## GIL release in extensions

Long-running CPU work in a Python C extension should release the GIL. Otherwise other Python threads stall.

**Pure C macros (Python C API):**

```c
Py_BEGIN_ALLOW_THREADS
do_long_work();
Py_END_ALLOW_THREADS
```

**Inside the GIL-released block: don't touch any Python object.** No `PyObject *`, no `Py_DECREF`, nothing. Re-acquire the GIL first if you need to.

**pybind11 / nanobind**: `py::call_guard<py::gil_scoped_release>()` on the function definition.

**PyO3**: `Python::allow_threads(|| { ... })`.

If your extension takes >1 ms and doesn't touch Python objects in the middle, release the GIL.

## Calling conventions and ABI versions

ABI compatibility means: a binary built against one library version works against a future library version of the same ABI level.

- **C**: System V AMD64 ABI on Linux/macOS, Microsoft x64 calling convention on Windows. Standard ABIs are stable.
- **C++**: ABI is **compiler-specific**. GCC and Clang share the Itanium C++ ABI on Linux. MSVC has its own. Mixing C++ object files across compilers is risky.
- **Python**: stable ABI exists (`Py_LIMITED_API`); use it for wheels that should work across Python minor versions.

For shared libraries with C ABI: maintain ABI compatibility within a major version. Adding fields to the *end* of structs is safe if size is communicated. Reordering fields, changing types, removing functions = ABI break = SONAME bump.

## Build integration

The bindings only matter if they build. Per stack:

- **Python C extensions**: `pyproject.toml` with `[build-system]` requires `setuptools`, `meson-python`, or `scikit-build-core`. The latter two are modern; `setuptools` is the boring default.
- **Cython**: `Cython` in `build-system`, `.pyx` files, `cython` directive in setup.
- **pybind11**: `pybind11` in `build-system`, CMake or scikit-build-core.
- **nanobind**: nanobind has its own build helpers; integrates well with scikit-build-core.

Wheels need to be built per platform/Python-version unless you use `Py_LIMITED_API` (stable ABI). `cibuildwheel` is the standard for building wheels for Linux/macOS/Windows in CI.

## When to NOT do FFI

The bug rate at FFI boundaries is high. Before adding one:

1. **Is there a pure-Python alternative that's fast enough?** Often yes. Profile first.
2. **Is the C library already wrapped?** Check PyPI / crates.io / pkg manager.
3. **Could you call out to a subprocess instead?** Higher latency, but a clean process boundary kills entire classes of bugs.
4. **Could you use a stable IPC (gRPC, JSON over a socket) instead?** Removes the in-process memory model from concern.

The user's stack benefits from FFI when it benefits — but if the use case is "call a 50-ms function once per second," a subprocess is simpler and harder to break.

## Debugging across the boundary

When something breaks at the seam:

- **Sanitizers** for the C/C++ side (ASan especially) — they often catch the bug Python doesn't see.
- **gdb with python-gdb extensions** — lets you see Python frames mixed with C frames.
- **Print at both sides** of the boundary — the simplest correctness check is "did each side see what the other thought it sent."
- **Single-step the marshalling** — half the bugs are "the bytes I thought I passed weren't the bytes that arrived."
- **Disable optimizations** in the FFI build temporarily — sometimes UB only manifests with optimization.
