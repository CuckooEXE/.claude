---
name: code-style-preferences
description: The user's specific code-style and tooling preferences across Python, C, C++, Zig, and x86 assembly — including preferred libraries, build tools, test frameworks, packaging tools (pipx), and design patterns (Abstract Base Classes, etc.). Use this skill whenever writing new code in any of these languages, scaffolding a project, choosing a test framework, deciding how to package a tool, or making architectural choices about class hierarchies and interfaces. Trigger even when the user doesn't name a specific tool — these preferences should shape any greenfield code.
---

# Code Style Preferences

This skill captures the user's *personal* preferences. These apply to greenfield work and to projects where the user has authority over conventions. In existing projects, **match the project's existing conventions** — these preferences do not override `Read before you write`.


## Python

### Tooling
- **Package management**: `pipx` for installing Python CLI tools globally. `pip install -e .` inside venvs for dev work. Avoid `sudo pip` always.
- **Virtual environments**: `venv`
- **Linting / formatting**: `black`
- **Testing**: `pytest`
- **Type checking**: `mypy` with strict type checking.

### Code structure
- **Abstract Base Classes** preferred over duck typing for interfaces with multiple implementations. Use `abc.ABC` and `@abstractmethod`. Document the contract on the ABC, not on each subclass.
- Prefer `dataclass` (or `attrs`/`pydantic` if the project uses them) for value types. No bare classes-as-dicts.
- Composition where it makes sense
- `src/` directory structure

### Idioms
- Type hints on all public APIs. Internal helpers can be untyped if it hurts readability.
- f-strings for formatting. `%`-formatting and `.format()` only when there's a reason (e.g., logging).
- `pathlib.Path` over `os.path`.
- Context managers for anything with a lifecycle.

## C

### Tooling
- **Build system**: `make`

### Compiler Flags

For safe C compiler flags, here are the commonly recommended ones, grouped by purpose:

**Warnings (catch bugs at compile time)**
- `-Wall -Wextra` — enable most useful warnings
- `-Wpedantic` — warn about non-standard constructs
- `-Wshadow` — warn when variables shadow others
- `-Wconversion` — warn about implicit type conversions that may lose data
- `-Wformat=2` — strict printf/scanf format checking
- `-Wnull-dereference`, `-Wdouble-promotion`, `-Wstrict-prototypes`
- `-Werror` — treat warnings as errors (great for CI)

**Runtime hardening**
- `-D_FORTIFY_SOURCE=3` — enables compile- and runtime checks on libc functions like `memcpy`, `strcpy`, `sprintf`, `read`, etc. (Falls back to `=2` on older systems. Requires at least `-O1`.)
- `-fstack-protector-strong` — stack canaries to detect buffer overflows
- `-fstack-clash-protection` — defends against stack clash attacks
- `-fcf-protection=full` — control-flow integrity (x86, Intel CET)
- `-D_GLIBCXX_ASSERTIONS` — bounds checking in libstdc++ (C++ projects)

**Linker hardening**
- `-Wl,-z,relro,-z,now` — read-only relocations, eager symbol binding
- `-Wl,-z,noexecstack` — non-executable stack
- `-fPIE -pie` — position-independent executable (for ASLR)

**Debug/development builds — sanitizers**
These are runtime tools and slow things down, but they catch bugs that warnings can't:
- `-fsanitize=address` (ASan) — heap/stack/use-after-free bugs
- `-fsanitize=undefined` (UBSan) — undefined behavior (signed overflow, bad shifts, etc.)
- `-fsanitize=leak` — memory leaks
- `-fsanitize=thread` (TSan) — data races (use separately, not with ASan)

Pair sanitizers with `-fno-omit-frame-pointer -g` for usable stack traces.

**A reasonable starting set**

For development:
```
-O1 -g -Wall -Wextra -Wpedantic -Wshadow -Wformat=2 \
-fsanitize=address,undefined -fno-omit-frame-pointer
```

For release:
```
-O2 -Wall -Wextra -D_FORTIFY_SOURCE=3 \
-fstack-protector-strong -fstack-clash-protection \
-fcf-protection=full -fPIE -pie \
-Wl,-z,relro,-z,now -Wl,-z,noexecstack
```


### Idioms
- `goto err:` for cleanup paths. Single exit point per function preferred when there's resource management.
- Check every `malloc`. Check every syscall. `errno` matters.
- Header guards **and** `#pragma once`
- `typedef struct name_t {} name;` format for structures, enums, unions.
- Use `size_t`, `uint64_t`, etc rather than `long` or `int`
- Opaque pointer for invsible data

## C++

### Tooling
- **Test framework**: **Google Test** (`gtest`). Pair with `gmock` when mocking is needed.
- **Build system**: Cmake
- **Standard**: C++17
- **Compiler flags**: `-Wall -Wextra -Wpedantic` minimum.

### Idioms
- RAII for everything. No raw `new`/`delete` — `std::unique_ptr` / `std::make_unique`, `std::shared_ptr` only when ownership is genuinely shared.
- `const` correctness. `noexcept` where applicable.
- Prefer references to pointers when null is not a valid value.

## Zig

### Tooling
- Zig version: Current Stable
- Build via `build.zig`, no external build systems.
- Tests live alongside source via `test "..."` blocks. Run with `zig build test`.

### Idioms
- Error unions everywhere. `try`, `catch`, `errdefer`. Don't `catch unreachable` to dodge handling.
- Allocators are explicit. Pass them in; don't hide them.
- `defer` for cleanup, `errdefer` for cleanup-on-error-only.
- Document all public functions (including public functions in `struct`s) as such:

```
/// [comptime] <- If comptime
/// Brief description of function
///
/// Longer description if necessary using `mark`*down*
///
/// Return type description
pub fn symLinkW(
    self: Dir, // !!!! Don't annotate `self`
    /// Anotate  parameters with a small desc.
    target_path_w: [:0]const u16,
    flags: SymLinkFlags,
) !void {}
```

## x86 Assembly

### Tooling / context
- Primary use case: exploit development, shellcode, RE annotations.
- **Syntax**: Intel syntax
- **Assembler**: nasm
- **Disassembler conventions**: binary Ninja

### Style
- Comment liberally. Every non-trivial line gets a `;` or `#` comment explaining what it does and why. Asm without comments is write-only code.
- Register usage in a calling convention should be documented at the top of any function — caller-saved vs callee-saved, what each register holds on entry/exit.
- Group logically related instructions; insert blank lines between blocks.
- For shellcode: document the constraints (null-free, alphanumeric, size budget) at the top of the file.

## Cross-cutting

### Naming
- Acronyms in names: HTTPServer

### Comments
- Comment the *why*, not the *what*. Code says what; comments explain why.
- Invariants and assumptions stated explicitly near the relevant code.
- TODOs include a name and a date or issue reference.

### Project layout (greenfield defaults)
- Tests in a top-level `tests/` directory. E2E tests in `tests/e2e/`. Match this even in C/C++ projects where the convention varies.
- Documentation in `docs/` per the `project-documentation` skill.

## How to use this skill

When a preference *is* stated, follow it. If a project's existing conventions conflict, the project wins, but flag the conflict so the user can decide whether to migrate.
