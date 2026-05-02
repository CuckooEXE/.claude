---
name: api-design
description: Designing library and SDK surfaces for stability, evolvability, and clarity — distinct from CLI/UI design (`cli-tool-design`). Covers surface-area minimization, type-signature discipline, error model selection, versioning and deprecation, breaking-change discipline, and Hyrum's-law awareness. Use when designing a new library, adding a function/method to an existing library, deprecating something, planning a v2, or critiquing an API for ergonomics or evolvability. Trigger on "should this be public", "what should the signature look like", "can I change this without breaking", "how do I version this", "what's the deprecation path", or any change to a `.h` / `__init__.py` / module-level export list.
---

# API design

A CLI is consumed by humans; an API is consumed by code. The cost of getting an API wrong is paid in every line of every consumer for as long as the API exists. This skill is about the discipline of designing for that cost.

## The first principle: minimize surface area

Every public function, type, constant, and exception is a thing you can't change without breaking someone. The most expensive bug isn't a wrong function — it's a function that shouldn't exist at all but now does, because removing it breaks consumers.

Default to **private**. Promote to public only when:

1. There's a real consumer asking for it.
2. You can articulate the contract precisely.
3. You can commit to maintaining the contract.

It is much easier to make a private thing public than to make a public thing private. The library version where a function is added is forever; the version it's removed in is a major version bump.

## Naming the surface

The surface is what's *exported*. Per language:

- **Python**: `__all__` is the convention. Anything not in `__all__` is implicitly private. Underscore-prefixed names (`_helper`) reinforce. Don't rely on import-time-side-effects to make something importable.
- **C**: every non-`static` function and global is in the public ABI. Use `static` aggressively. For dynamic libraries, use visibility annotations (`__attribute__((visibility("hidden")))` or `-fvisibility=hidden` + explicit exports).
- **C++**: same as C, plus headers. Keep implementation details out of public headers (PIMPL, hidden friend functions, `internal::` namespaces).
- **Zig**: top-level `pub` declarations are exported. Default to non-`pub`; promote when needed.

A weekly grep of "what does this library export" is a useful habit when designing a v1.

## Function signatures

The signature is the contract. Constraints:

### Take what you need

A function that takes a 50-field config object when it uses three fields is over-specified. Take the three fields. The caller will adapt.

```python
# Bad
def render_user(req: HttpRequest) -> str: ...

# Good
def render_user(user_id: int, locale: str) -> str: ...
```

The bad version forces every caller to construct an `HttpRequest`, even unit tests. The good version is callable from anywhere.

### Return what's useful

- A function returning `void`/`None` and mutating its argument is harder to compose than one that returns the result.
- A function returning a tuple of unrelated values usually wants to be two functions.
- Don't return an `Optional<T>` when "not present" can be expressed as a sensible empty value (empty list, empty string, zero) and there's no semantic difference.

### Strong types over primitives

- `def grant(user: User, role: Role)` — typo-resistant.
- `def grant(user_id: int, role: str)` — typo-prone, swap-prone, easy to confuse two int parameters.

For dynamic languages, this is what type hints + dataclasses are for. For C/C++, opaque struct pointers (`typedef struct user user_t;`).

### Optional parameters

Default arguments are fine for common values. *Many* optional parameters is a signal you want a config object/struct.

```python
# Smell
def serve(host="0.0.0.0", port=8080, tls=False, certfile=None, keyfile=None,
          workers=4, timeout=30, max_request_size=1<<20, ...):

# Better
@dataclass
class ServerConfig:
    host: str = "0.0.0.0"
    port: int = 8080
    tls: TLSConfig | None = None
    workers: int = 4
    ...

def serve(config: ServerConfig): ...
```

The config object can be extended without changing the function signature, and named fields beat positional booleans.

### Don't take callbacks unless you have to

Callbacks invert control. They imply re-entrancy concerns, lifetime concerns, and threading concerns. Prefer:

- Return a value the caller does something with.
- Return an iterator/generator the caller pulls from.
- Take an "options" object with policy values, not behavior callbacks.

Reach for callbacks when there's no other way (event handler, async completion, custom comparator).

## Error model

The error model is part of the API. A library that mixes `raise`, `return None`, and `return -1` is a worse library than one that's consistent.

Per the `error-handling-strategies` skill:

- **Pick one model** for the whole library.
- **Document every error** the function can produce.
- **Don't leak internal error types.** A SQL adapter shouldn't expose Postgres-specific error codes.
- **Versioning the error type is a breaking change.**

Concretely: if your library raises a specific exception, catching that exception is part of the consumer's contract. Renaming or restructuring the exception hierarchy breaks them.

## Stability tiers

Mark each public symbol with a stability tier. Useful tiers:

- **Stable**: no breaking changes outside a major version bump.
- **Experimental**: subject to change in any release. Use at your own risk. Document this prominently.
- **Deprecated**: replaced; will be removed in version X. Compiler/runtime warning if possible.
- **Removed** (in changelog): gone. Will not be added back.

Languages support this differently:

- Python: `warnings.warn(DeprecationWarning, ...)`, `@typing.deprecated` (3.13+), or a decorator.
- C/C++: `__attribute__((deprecated("use X instead")))`.
- Zig: `@compileError`-on-use for hard removal, comments for soft deprecation.

## SemVer (and CalVer alternatives)

**SemVer** for libraries: `MAJOR.MINOR.PATCH`.

- MAJOR: breaking change to public API.
- MINOR: new functionality, backwards-compatible.
- PATCH: bug fix, backwards-compatible.

What "breaking" means is specific to the language and the contract:

- **Removing or renaming** a public symbol: breaking.
- **Adding a required parameter**: breaking.
- **Adding an optional parameter** to the end: usually not breaking.
- **Tightening a return type** (more specific): not breaking for callers using the old type.
- **Loosening a return type** (less specific): can be breaking if callers assumed the old type.
- **Tightening an input type**: breaking if old inputs no longer fit.
- **Loosening an input type**: not breaking.
- **Changing observable behavior** (different exception class, different serialization): breaking.

**CalVer** (`YY.MM`) is appropriate for tools, services, and libraries where time-since-release matters more than compat guarantees. SemVer is the better default for a library that other code links against.

A library that hits 1.0 too early is worse than one that stays in 0.x for longer. Stay in 0.x while the surface is still being shaped; reach 1.0 only when you can commit to the contract.

## Deprecation path

Don't remove things. Deprecate, then remove on a published timeline.

**Standard timeline:**

1. **Version N**: introduce replacement. Mark old as deprecated. Emit warning on use. Document in changelog and migration guide.
2. **Version N+M** (where M ≥ 1 minor cycle, typically 6+ months): remove the deprecated symbol. Bump major if the project follows SemVer.

The warning matters. A silent deprecation is no deprecation. Make sure consumers see it during their normal `pytest` / build / lint.

## Hyrum's law

> *"With a sufficient number of users of an API, it does not matter what you promise in the contract: all observable behaviors of your system will be depended on by somebody."*

Implications:

- The exact text of error messages will be parsed by someone. Keep them stable.
- The exact ordering of dictionary iteration will be relied on. Document explicitly that you don't guarantee order.
- The exact format of debug logs will be scraped. Treat as part of the contract or wear a "may change" warning.
- Performance characteristics (this is fast, that is slow) will be relied on. Major regressions feel like breaking changes even if the contract didn't say.

You can't prevent Hyrum's law. You can only:

1. Document what is and isn't part of the contract.
2. Vary unspecified behavior intentionally (random iteration order in Python sets) to keep consumers honest.

## Compatibility shims

When a breaking change is required:

- A shim that maps old → new can buy a deprecation cycle.
- The shim should be **marked deprecated**, **emit a warning**, and have a **scheduled removal date**.
- Without those three, the shim becomes permanent.

The user's CLAUDE.md says: "Don't use feature flags or backwards-compatibility shims when you can just change the code." This applies to internal code paths, not to public library APIs. For public APIs, deprecation shims are a kindness to consumers — but they're temporary, not load-bearing.

## Documentation as contract

The signature is the typed contract. The docstring is the typed-but-untyped contract. Document:

1. **What** the function does (one sentence).
2. **Inputs** with constraints ("must be UTF-8", "must be ≥ 0", "must not be empty").
3. **Outputs** with structure (what the dict keys are, what the iterator yields).
4. **Errors** with conditions (what raises what when).
5. **Side effects** if any (writes a file, sends a request, mutates an argument).
6. **Concurrency** if non-obvious (thread-safe, async-cancellation-safe, must hold lock X).
7. **Performance** if it's part of the contract (O(n), ~1 ms typical).

A function whose docstring is "Process the data" is undocumented.

## Versioning the wire (not just the API)

If your library's output is consumed (serialization formats, on-disk layouts, on-wire protocols), the **format itself** has a version. The library version and the format version are separate concerns:

- **Forwards compatibility**: old code reads new data without crashing (skips unknown fields).
- **Backwards compatibility**: new code reads old data correctly.
- **Both**: at any deployment, any pair of versions that might encounter each other can coexist.

For binary formats: include a magic number and a version field at the start. Always.

For text formats (JSON, YAML): include a `version` or `schemaVersion` key.

Without a version, every change is a coordinated deployment.

## When you're stuck

If you can't decide between two API shapes, ask:

1. **Which is harder to misuse?** Pick that.
2. **Which is harder to extend later?** Pick the *other*.
3. **Which has more obvious failure modes?** Pick that.
4. **Which one would I want to read in someone else's code?** Pick that.

Show two consumers of the API in a comment at the top of the module. The one that reads better wins.
