---
name: testing-strategy
description: Beyond TDD basics — how to choose what to test, at what level, with what fidelity. Use when designing or critiquing a test suite, deciding between unit/integration/e2e, choosing between fakes/mocks/stubs, picking property-based vs example-based, hunting flakes, or judging coverage gaps. Pairs with `software-engineering-practices` (which covers the TDD loop itself) and `/test-first` (which writes the failing test). Trigger when the user asks "how should I test this", "should I mock X", "why is this test flaky", "what's missing from this test suite", or proposes adding a test layer.
---

# Testing strategy

The TDD loop (`software-engineering-practices`) tells you to write a failing test before code. *This* skill tells you **what kind of test to write, where it lives, and what fidelity it needs.**

## Test pyramid — and when to break it

Default ratio: many fast unit tests, fewer integration tests, very few end-to-end tests.

- **Unit** — one function/class, no I/O, no shared state, runs in <10ms. Pure logic, parsers, calculators, state machines.
- **Integration** — multiple components together with **real** boundaries where the user has feedback memory: real DB, real filesystem, real subprocess. Mocks at this layer have burned the user before — see the `feedback_db_integration_tests` memory.
- **End-to-end** — the whole system. Slow, brittle, hard to debug. Reserve for "the critical user flow works at all."

**Inversions are sometimes correct.** A protocol parser with 200 input edge cases doesn't need integration tests of every case — write a single property-based test. A thin web handler with no logic doesn't need a unit test — let an integration test cover it. State the inversion explicitly when you propose it.

## Test doubles — Fowler taxonomy, applied

| Double | Use it for | Don't use it for |
|---|---|---|
| **Dummy** | Filling required parameters that aren't exercised | Anything the test asserts on |
| **Stub** | Returning canned answers for queries (`get_user → User(id=1)`) | Verifying the call happened |
| **Spy** | Recording calls *and* returning real-ish answers | Replacing a real component with critical behavior |
| **Mock** | Verifying interactions matter to the test (`assert email_sender.send_called_once_with(...)`) | Anything else — over-mocking creates change-detector tests |
| **Fake** | A working but simplified implementation (in-memory DB, in-memory queue) | Tests that need to detect real-DB-only bugs |

Default to **fakes over mocks** when the boundary has substantive behavior. A test that uses `mock_db.execute.assert_called_with("SELECT ...")` is a contract-on-the-mock, not a contract on the system. A test that uses an in-memory `FakeRepository` is much more durable across refactors.

## Table-driven tests

Almost always preferable when the same logic has many inputs. Pattern transcends Go:

```python
@pytest.mark.parametrize("input,expected", [
    ("",        0),
    ("a",       1),
    ("aa",      2),
    ("a" * 1024, 1024),
    pytest.param("\xff" * 4, 4, id="non-ascii"),
])
def test_byte_length(input, expected):
    assert byte_length(input) == expected
```

Each row is a behavior. Bug fixes add a row, not a new function. The id parameter is worth using for any non-obvious case.

## Property-based testing

When the function has a property that holds for **all** valid inputs, a property test beats a hundred examples. Hypothesis (Python), QuickCheck (Haskell, ports in C/Rust/Zig), `std.testing.fuzz` (Zig), libFuzzer for C/C++ (yes, fuzzing is property testing).

Useful properties:

- **Round-trip**: `decode(encode(x)) == x`
- **Idempotence**: `f(f(x)) == f(x)`
- **Invariant preservation**: after any sequence of ops, total balance is unchanged
- **Reference oracle**: `optimized(x) == naive(x)` for `x` in domain
- **Metamorphic**: if `f(x) == y`, then `f(g(x)) == h(y)` for some `g`, `h`

When a property test finds a failure, save the shrunk minimal example as a permanent regression test in the example-based suite.

## Snapshot / golden tests

Worth it when:
- The output is large but deterministic (rendered HTML, generated code, formatted reports).
- The output is hard to assert structurally but easy to eyeball-diff.

Risks:
- They rot — every "approve the new snapshot" is a chance to bake in a bug.
- They make `git diff` review the actual gate.

Mitigation: structure snapshots as **small files** (one per test), not one giant blob. Make snapshot updates a separate commit so the review can focus.

## Test data: fixtures vs factories

- **Fixture file** (a static `.json` / `.txt`) — for "this exact byte sequence is the protocol input." Binary inputs especially. Commit the file.
- **Factory** (`make_user(name="alice")` with sane defaults) — for object construction where most fields don't matter to the test. Avoids the "test sets 17 fields, three of which the test cares about" trap.
- **Builder** — when there are many optional knobs, e.g., `UserBuilder().with_admin().with_locked_account().build()`.

Default to factories with sane defaults; pull out a fixture file the moment the test data is "real-world byte-for-byte."

## Test naming

The test name is the **specification**. A future reader should know what's broken from the name alone.

- Bad: `test_user_1`, `test_validates`, `test_happy_path`
- Good: `test_locked_user_cannot_log_in`, `test_token_expires_after_24h`, `test_parser_rejects_unterminated_string`

Pattern: `<subject>_<condition>_<expected>` or `<expected>_when_<condition>`. Pick one and stay consistent.

## Coverage as guardrail, not goal

- Coverage tells you what *isn't* tested. It doesn't tell you what *is* well-tested.
- 100% line coverage on a test suite that asserts nothing is meaningless.
- Use coverage to find blind spots, then **read those blind spots**. Often they're either dead code (delete) or genuinely hard-to-trigger paths (worth adding a test).
- Branch coverage > line coverage. If your tooling supports it, use it.
- Don't gate PRs on a coverage delta. It encourages low-quality tests.

## Negative tests, boundaries, error paths

For every happy-path test, ask:
1. **What's the boundary?** Empty string, single element, max int, off-by-one, leap year, daylight savings, UTF-8 surrogate, etc.
2. **What's the error mode?** Network down, disk full, permission denied, malformed input. Test that errors are *propagated correctly*, not swallowed.
3. **What's adversarial?** Malicious input — billion laughs, zip bomb, regex DoS, billion `__init__` deep.

A test suite with only happy paths is a smoke test, not a test suite.

## Integration tests and the user's hard rule

The user has been burned by mocked tests passing while real-world integration broke. **Integration tests must hit a real boundary** unless explicitly told otherwise. For databases specifically, use a real Postgres / SQLite / whatever the production target is — not a mock, not a homemade fake.

If the integration test is too slow for inner-loop dev, that's a *speed* problem (testcontainers, in-process Postgres, fixture reuse, parallelism), not a *fidelity* problem.

## Flake hunting

A flaky test is worse than a missing test — it teaches the team to ignore failures.

**Deflake protocol:**
1. **Quarantine** — mark the test as flaky and skip-by-default with a tracking issue. Don't let it land on main.
2. **Reproduce** — `for i in {1..1000}; do pytest -k test_foo; done` until it fails. Bisect input randomness, ordering, timing.
3. **Categorize** the cause:
   - **Timing** — sleeps, races, deadlines tighter than the worst case. Fix: condition variables / wait-for-condition helpers, real synchronization.
   - **Ordering** — implicit reliance on map iteration order, `os.listdir` order, GC timing. Fix: sort, explicit ordering.
   - **External** — network call, time-of-day, shared file. Fix: fake the boundary or freeze the clock.
   - **State leakage** — test N pollutes test N+1. Fix: aggressive setup/teardown, parallel-isolation primitives.
4. **Fix and unquarantine.** Don't leave a `@pytest.mark.flaky(reruns=3)` band-aid; that's accepting flakiness.

## Tests on mutable inputs

When a function mutates its argument, **assert the mutation in the test** rather than only the return value. Otherwise the test passes if the function silently stops mutating.

## What "done" looks like for a test

- Has a name that describes the behavior, not the implementation.
- Asserts the *minimum* that proves the behavior — don't over-specify, don't pin internals.
- Fails for the right reason when the SUT is broken (verify by introducing a deliberate bug).
- Doesn't depend on test ordering, the clock, the network, or external state unless that's the test's whole point.
- Runs in <100ms for unit, <1s for integration, "tolerable" for e2e.
- Is deleted (not just `@skip`-ed) when the behavior it tests is no longer a real requirement.
