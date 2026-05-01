---
name: build-systems
description: Conventions and patterns for the build systems the user works with — CMake (modern target-based), Meson, Bazel, build.zig, plain Make, plus cross-compile, sanitizer toolchains, ccache, and reproducible-build hygiene. Use this skill when adding or modifying a build script, scaffolding a new C/C++/Zig project, setting up sanitizer or cross-compile builds, debugging a flaky build, or choosing a build system for a greenfield project.
---

# Build Systems

The user's hot languages are Python, C, C++, Zig, and asm. This skill covers build-system conventions for the compiled ones. For Python packaging, see `cli-tool-design`.

## Choosing a build system (greenfield)

| If the project is... | Use |
|---|---|
| Pure Zig | `build.zig`. Don't introduce CMake. |
| C, single-platform, < ~5 files | A short `Makefile`. Don't over-engineer. |
| C/C++, multi-platform | **CMake** with modern target-based usage. |
| Mixed-language monorepo, hermetic builds matter | **Bazel** (or Buck2). Steep learning curve, big payoff at scale. |
| C/C++ project that values fast configures and clean syntax | **Meson** + Ninja. |
| Embedded / kernel / firmware | Probably whatever the platform mandates (Kconfig+Make, IDF, Zephyr's west, etc.). Match the ecosystem. |

Don't switch a project's build system without an ADR. Build-system migrations are rarely cheap.

## Modern CMake

The user expects **target-based** CMake, not the directory-soup style from 2010.

Minimum standards:

```cmake
cmake_minimum_required(VERSION 3.21)  # or whatever's current; pin a real floor
project(myproj LANGUAGES C CXX VERSION 0.1.0)

set(CMAKE_CXX_STANDARD 20)             # or whatever the project chose
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)  # for clangd, clang-tidy

add_library(myproj_core src/core.cpp)
target_include_directories(myproj_core PUBLIC include)
target_compile_options(myproj_core PRIVATE -Wall -Wextra -Wpedantic)

add_executable(myproj src/main.cpp)
target_link_libraries(myproj PRIVATE myproj_core)
```

Rules:
- **Targets, not variables.** `target_compile_options(tgt PRIVATE ...)`, not `set(CMAKE_C_FLAGS "...")`.
- **PRIVATE / PUBLIC / INTERFACE** matter. Include dirs and link deps that consumers need are PUBLIC; internal-only is PRIVATE.
- **No `link_directories`.** Use full target paths from `find_package`.
- `find_package(Foo REQUIRED)` for deps, falling back to `FetchContent` for those without a system package, falling back to a vendored copy only when both fail.
- One `CMakeLists.txt` per logical component. Don't put everything in the root file.
- `target_sources(tgt PRIVATE ...)` to add files to a target after creation, when convenient.

### Sanitizer presets

Provide a `CMakePresets.json` with at least `dev`, `asan`, `ubsan`, `tsan`, `release` presets:

```json
{
  "version": 6,
  "configurePresets": [
    {
      "name": "asan",
      "generator": "Ninja",
      "binaryDir": "build/asan",
      "cacheVariables": {
        "CMAKE_BUILD_TYPE": "Debug",
        "CMAKE_C_FLAGS": "-fsanitize=address,undefined -fno-omit-frame-pointer -g",
        "CMAKE_CXX_FLAGS": "-fsanitize=address,undefined -fno-omit-frame-pointer -g",
        "CMAKE_EXE_LINKER_FLAGS": "-fsanitize=address,undefined"
      }
    }
  ]
}
```

`cmake --preset asan && cmake --build build/asan` should Just Work for any contributor.

### Compile flags floor

For any C/C++ target the user owns:

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


For release: add `-O2`, optionally `-flto`. Avoid `-Ofast` — it enables `-ffast-math`, which silently breaks IEEE 754 expectations.

For exploit-dev / RE work, the flags are usually **dictated by the target**, not the user. Match the target's build.

## build.zig

Idiomatic Zig: don't reach for anything else.

```zig
const std = @import("std");
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "myproj",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&b.addRunArtifact(exe).step);

    const tests = b.addTest(.{ .root_source_file = b.path("src/main.zig") });
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&b.addRunArtifact(tests).step);
}
```

Pin the Zig version: `.zig-version` file or document the required version in the README. Zig is pre-1.0; mismatched versions break.

## Plain Make

Still the right answer for tiny C projects. Keep it small:

```make
CC      ?= cc
CFLAGS  ?= -Wall -Wextra -Wpedantic -O2 -g
LDFLAGS ?=

SRCS := $(wildcard src/*.c)
OBJS := $(SRCS:.c=.o)

myproj: $(OBJS)
	$(CC) $(LDFLAGS) -o $@ $^

clean:
	rm -f myproj $(OBJS)

.PHONY: clean
```

- `?=` so the user can override on the command line.
- `.PHONY` for non-file targets.
- No recursive make. If you find yourself needing it, switch to CMake or Meson.

## ccache / sccache

On any non-trivial C/C++ project: install ccache and have CMake / Meson use it. Cuts incremental rebuild time massively. `export CC="ccache gcc"` or `cmake -DCMAKE_C_COMPILER_LAUNCHER=ccache`.

For distributed builds, `sccache` is the modern equivalent and works with cloud caches.

## Cross-compile

CMake: use a **toolchain file**, never inline cross flags.

```cmake
# arm-linux-gnueabihf.cmake
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR arm)
set(CMAKE_C_COMPILER arm-linux-gnueabihf-gcc)
set(CMAKE_CXX_COMPILER arm-linux-gnueabihf-g++)
set(CMAKE_FIND_ROOT_PATH /opt/arm-linux-gnueabihf-sysroot)
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
```

Then `cmake -DCMAKE_TOOLCHAIN_FILE=cmake/arm-linux-gnueabihf.cmake ...`.

For Zig, just `zig build -Dtarget=aarch64-linux-musl` — Zig is the easiest cross-compiler in the world.

For embedded / firmware: prefer the SDK's toolchain wrapper (esp-idf, Zephyr west, NXP MCUXpresso, etc.) over rolling your own.

## Reproducible builds

When it matters (security review, distribution, attestation):
- Pin compiler version. Document it in `developer-guide/building.md`.
- Pin all deps. Lockfiles for package managers; vendored or git-submoduled deps for C/C++.
- `-ffile-prefix-map=$PWD=.` to strip absolute paths from binaries.
- `-frandom-seed=<file>` if you have RNG-dependent symbol mangling.
- `SOURCE_DATE_EPOCH=<commit-time>` for timestamped artifacts.
- Verify with `diffoscope <build-A> <build-B>`.

## Common build mistakes

- **Globbing source files.** `file(GLOB ...)` in CMake is convenient but breaks incremental builds — CMake doesn't see new files until you re-configure. Prefer explicit lists.
- **Including private headers in `target_include_directories(... PUBLIC ...)`.** Now consumers see them.
- **Mixing static and shared library builds without thinking about LTO and PIC.** Pick a model.
- **Hard-coding paths.** `/usr/local/include`, `/opt/...`. Use `find_package` / `pkg_check_modules`.
- **Treating `-Werror` as a CI-only thing.** It silently bit-rots local builds. Either always-on or never.
- **Skipping the install step.** If your project is shipped, `cmake --install .` should produce a usable layout. Don't only test from the build tree.

## What to do before declaring a build "done"

- `cmake --build . --target test` (or `meson test`, `zig build test`, `make check`) passes.
- The sanitizer build passes the same tests.
- A *clean* build from a fresh checkout works (`rm -rf build && cmake --preset dev && cmake --build build`).
- The release build produces stripped binaries with debug info packaged separately if you ship symbols (`objcopy --only-keep-debug` flow).
- `developer-guide/building.md` matches reality.
