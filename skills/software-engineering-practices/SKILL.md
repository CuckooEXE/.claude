---
name: software-engineering-practices
description: Core software engineering discipline for the user — test-driven development, defensive programming, error handling, dependency hygiene, and the definition of "done" for a code change. Use this skill whenever writing, modifying, refactoring, or reviewing production code, fixing bugs, adding features, or setting up a new project. Trigger even when the user doesn't explicitly say "write tests" or "be defensive" — these are defaults, not opt-ins.
---

# Software Engineering Practices

The user holds code to a senior-engineer bar. Apply this skill on every code change — production, internal tooling, even one-off scripts that are likely to outlive the moment.

## Test-Driven Development

The default workflow:

1. **Understand the change.** State in 1–3 sentences what behavior is being added or fixed.
2. **Write the test first.** A failing test that pins down the new behavior. For bug fixes, this is a regression test that reproduces the bug.
3. **Run the test, confirm it fails for the right reason.** "Fails because the function doesn't exist yet" and "fails because of a typo in the test" look identical until you check.
4. **Write the minimum code to make it pass.**
5. **Refactor.** Now that the test is green, clean up.
6. **Repeat.**

When TDD is the wrong tool:
- Pure exploration / spike code that will be thrown away
- Reverse engineering or vulnerability research where you don't yet know the shape of "correct"
- UI/visual work where the feedback loop is the human eye

In those cases, say so explicitly ("skipping TDD because this is a spike") rather than silently dropping the practice.

### Test types and when to use them

- **Unit tests** — for pure logic, parsers, data transforms. Fast, isolated, no I/O.
- **Integration tests** — for code that crosses a boundary (DB, filesystem, network, IPC). Use real boundaries when feasible, fakes when not.
- **End-to-end tests** — for user-visible workflows. The user expects e2e tests on any project that has user-visible behavior. They live in a top-level `tests/e2e/` or `e2e/` directory by convention. An e2e test exercises the system the way a user would — through the CLI, the HTTP API, the wire protocol — not through internal function calls.
- **Property-based tests** — when a function has invariants (round-trips, idempotence, ordering). Hypothesis (Python), rapidcheck (C++), or equivalent.
- **Fuzz tests** — for parsers, deserializers, anything taking untrusted input. The user does security work; if you're writing a parser, ask whether to add a fuzz harness.

## Defensive Programming

### Return values are not suggestions
- In C: every `malloc`, `read`, `write`, `open`, `mmap`, `fork`, `dup2`, `pthread_create` etc. — check the return value. `errno` matters.
- In C++: prefer RAII and exceptions, but if an API returns a status, check it.
- In Zig: error unions are the language's love letter to this principle. Use them. `try`, `catch`, `errdefer` exist for a reason. Don't `catch unreachable` to dodge handling.
- In Python: don't bare-`except:`. Catch the specific exception you can handle. Let everything else propagate.

### Validate at trust boundaries
A trust boundary is anywhere data crosses from a domain you control into one you don't, or vice versa: user input, network input, file input, IPC, FFI, syscalls. Validate **once, at the boundary**, then trust the data internally. Don't sprinkle defensive checks through code that can only be called with already-validated data — that's noise.

### Fail loud, fail early
- An unrecoverable error should crash with a clear message, not limp on with corrupt state.
- Asserts are for invariants the programmer believes are always true. They are not for input validation.
- A function that can't do its job should say so via its return type (Result/Option/error union) or by raising — never by returning a sentinel value the caller has to remember to check, unless the language idiom demands it (e.g., C's `-1`).

### No silent catches
```python
# Bad
try:
    do_thing()
except Exception:
    pass

# Bad
try:
    do_thing()
except Exception as e:
    logger.warning(f"oops: {e}")  # and then continue as if nothing happened
```
If you're catching, you're either (a) handling the error meaningfully, (b) translating it to a different error type, or (c) logging-and-re-raising. "Logging and continuing" is almost always wrong.

## Error handling philosophy by language

- **Python**: exceptions for exceptional cases, return values for expected outcomes. Type hints distinguish `Optional[T]` from `T`.
- **C**: return-code conventions. Document what the function returns on error. Use `errno` for syscall-style APIs. Cleanup paths via `goto err:` are idiomatic and preferred to nested `if`s.
- **C++**: exceptions for truly exceptional, `std::expected` (C++23) or `tl::expected` for recoverable, RAII for cleanup. No raw new/delete.
- **Zig**: error unions everywhere. `defer` and `errdefer` for cleanup. Don't fight the language.

## Dependency hygiene

- Before adding a dependency, justify it. "We need ~3 functions" rarely justifies a new dependency.
- Pin versions. `requirements.txt` with exact versions, `Cargo.lock`, `package-lock.json`, vendored C deps where appropriate.
- Be aware of the supply chain. The user does security work — they think about transitive deps as attack surface.
- For Python tooling, the user prefers `pipx` for installing CLI tools globally (see `code-style-preferences`).

## Definition of done

A change is *done* when:

1. The new/changed behavior has tests, and they pass.
2. The whole test suite passes, not just the new tests.
3. Linters and type checkers are clean (or warnings are explicitly justified in a comment).
4. Documentation is updated — at minimum the docstring/comment on the changed function, and the user-facing or developer-facing docs if behavior visible to either has changed (see `project-documentation`).
5. If the change touches public API, the changelog / release notes are updated.
6. The change is small enough to review. If it isn't, it should have been split.

## Things to actively avoid

- **Dead code.** Delete it. Version control remembers.
- **Commented-out code.** Same.
- **`TODO` without a name and a date.** A `TODO` is a debt; an anonymous one is debt with no creditor.
- **Magic numbers.** Name them. `const int MAX_RETRIES = 3;` not `if (count > 3)`.
- **Mutating function arguments** unless the language idiom requires it (C output params, etc.) and it's documented.
- **Catching `Exception` / `...` / `anyerror`** as the default — be specific.

## When the user asks for a quick script

"Quick script" is not a license to abandon discipline. Even a one-shot script:
- Has a docstring/comment saying what it does and what it expects.
- Checks that its inputs exist before tearing into them.
- Doesn't `rm -rf` based on unvalidated input.

But scale the ceremony: a 30-line script doesn't need an `Architecture and Design.md`. Use judgment.
