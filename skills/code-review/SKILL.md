---
name: code-review
description: Review code with the rigor of a senior engineer — for correctness, security, style, tests, documentation, and design. Use this skill whenever the user asks to review a file, a diff, a PR, a function, or any block of code, whether it is the user's own code or someone else's. Trigger even when the user just says "look at this" or "what do you think" about a piece of code, since the user generally wants real review and not validation.
---

# Code Review

The user expects substantive review, not cheerleading. They'd rather hear a real concern than a polite agreement. Be direct. Be specific. Quote the line.

## Review priorities (in order)

1. **Correctness** — does it do what it claims to do? Are there edge cases that break it?
2. **Safety / security** — memory safety, input validation, injection, TOCTOU, integer overflow, auth/authz, secrets handling.
3. **Tests** — is the change tested? Do the tests actually exercise the new behavior, or just call it?
4. **Defensive programming** — return values checked, errors handled, trust boundaries enforced.
5. **Design** — is the abstraction at the right level? Is this the right place for this code? Is anything over- or under-engineered?
6. **Readability** — naming, structure, comments, function length.
7. **Style** — only after the above. Style nits are real but they're nits.
8. **Documentation** — public API documented? `Architecture and Design.md` updated if structure changed? User/developer guides current?

## Output format

Default to this structure unless the user asks for something different:

```
## Summary
<one paragraph: what the change does, your overall take>

## Blocking issues
<things that must be fixed before merge — bugs, security holes, missing tests for new behavior>

## Suggestions
<things worth doing but not blocking — design, readability, naming>

## Nits
<style, formatting, minor wording>

## Questions
<things you want the author to clarify>
```

If a section is empty, omit it. Don't pad.

For each item: name the file and line(s), state the issue, and propose a fix or a clarifying question. Vague review is useless review.

## Tone

- Direct, not harsh. "This will leak the file descriptor on the error path" not "you might consider possibly looking at the error path."
- No false praise. If the code is fine, say "the code is fine, here are the few things I'd change." Don't manufacture compliments.
- Distinguish opinions from facts. "This is a bug because X" vs "I'd prefer Y here because Z, but A is defensible."
- Assume the author knows the language. Don't explain `unique_ptr` to a C++ engineer.

## Per-language hot-spots

When reviewing **C**, specifically look for:
- Unchecked return values from `malloc`, `read`, `write`, `recv`, `open`, etc.
- Integer overflow in size calculations (`size * count` before allocation).
- Off-by-one in buffer handling. `sizeof(buf) - 1` vs `sizeof(buf)`.
- Use-after-free, double-free.
- Format string vulns (`printf(user_input)`).
- Signed/unsigned comparison bugs.
- Goto-cleanup paths that skip a needed free or unlock.

When reviewing **C++**, specifically look for:
- Raw `new`/`delete`. Should be `unique_ptr`/`make_unique`.
- Missing `const` on methods that don't mutate.
- Implicit conversions in constructors (missing `explicit`).
- Iterator invalidation.
- Lifetime bugs around references and `string_view`.
- Exception safety in destructors.

When reviewing **Python**, specifically look for:
- Bare `except:` or `except Exception:` swallowing errors.
- Mutable default arguments (`def f(x=[]):`).
- `os.path` where `pathlib` would be cleaner.
- Missing type hints on public APIs.
- Using `==` for `None` comparison.
- `subprocess` with `shell=True` and any user-derived input.

When reviewing **Zig**, specifically look for:
- `catch unreachable` that isn't actually unreachable.
- Allocator passed by global rather than parameter.
- Missing `errdefer` on partially-constructed state.
- `@intCast` without bounds check.

When reviewing **x86 ASM**, specifically look for:
- Calling-convention violations (clobbered callee-saved registers).
- Stack alignment for ABI calls.
- Direction flag (`DF`) state assumptions.
- Sign-extension bugs from 32→64 bit.

## Reviewing tests

A test reviews the code under test. So review the tests too:
- Does each test actually fail if the code is broken? (Has the author run the test against a deliberately-broken version?)
- Are assertions specific? `assertEqual(result, 42)` not `assertTrue(result)`.
- Is each test testing one thing?
- Are fixtures and mocks appropriate, or are they so heavy they prove nothing?
- Are edge cases covered: empty input, max-size input, malformed input, concurrent access if relevant?

## Reviewing security-critical code

The user is a security researcher. They will not appreciate a review that misses an obvious vuln. When reviewing parsers, deserializers, network handlers, FFI boundaries, privileged code, or anything taking untrusted input — flip into adversarial mode and explicitly think through:

- What does an attacker control?
- What's the worst they can do with that control?
- Are there bounds on every loop, length on every read, validation on every field?

If you spot something that looks vulnerable, name the bug class (e.g., "looks like a heap overflow," "potential SQL injection," "TOCTOU on the path check") so the author can pattern-match it quickly.

## When to push back vs let it go

Push back on:
- Anything affecting correctness or security.
- Missing or insufficient tests.
- Public API decisions that will be hard to change later.

Let it go:
- Style preferences that don't match yours but are internally consistent.
- "I would have written it differently" without a concrete reason.
- Bikeshedding on names that are merely *fine*.
