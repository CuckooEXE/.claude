---
description: Write a failing test for a described change, run it, confirm it fails for the right reason, then stop and wait for go-ahead before implementing.
argument-hint: <one-line description of the change>
allowed-tools: Bash(*), Read, Write, Edit, Grep, Glob
---

# /test-first — write the failing test, then stop

Pull in `software-engineering-practices`. The TDD loop is steps 1–6 of that skill; this command performs steps 1–3 and **explicitly stops there**.

## Procedure

1. **Restate the change** in 1–3 sentences from `$ARGUMENTS`. If `$ARGUMENTS` is empty or vague, ask the user once for the missing pieces (what the new behavior is, where it lives, how it should be called) — don't proceed on a guess.

2. **Locate the test home.**
   - Identify the language and test framework (`pyproject.toml` + pytest, `CMakeLists.txt` + GTest, `build.zig` + `test "..."` blocks, etc.).
   - Find the existing test file the new test fits into (matching module/file under test). If none exists, create a new file in the conventional location.
   - **Do not** introduce a new test framework. Match what's there.

3. **Write the failing test.**
   - Test name: descriptive, sentence-case (`test_parses_truncated_header_returns_error`, `ParsesTruncatedHeaderReturnsError`).
   - Pin down the new behavior precisely with specific assertions. `assertEqual(result, 42)` not `assertTrue(result)`.
   - For bug-fix changes, this is a regression test that **reproduces** the bug.
   - Keep it tight — one behavior per test. If the change implies multiple behaviors, write multiple tests.

4. **Run the test.** Use the project's test runner.

5. **Confirm it fails for the right reason.**
   - If it fails because the function doesn't exist → fine, that's expected. Make sure the failure message clearly says so.
   - If it fails because of a typo in the test → fix the typo, re-run.
   - If it **passes** → the test isn't actually pinning down new behavior. Stop and tell the user; the test needs to be more specific or the behavior already exists.
   - If it errors out for an unrelated reason (import error, missing fixture) → fix that, re-run.

6. **Stop.** Tell the user:
   - The path to the new test.
   - The exact command they (or you) can run to reproduce the failure.
   - The failure output (relevant lines, not the whole stacktrace).
   - A one-line plan for the implementation.

   Do **not** start implementing. Wait for the user's go-ahead.

## Output template

```
Test added: <path>:<line>
Command:    <how to run just this test>

Failure (excerpt):
  <relevant lines>

Failure reason: <"function doesn't exist yet" / "raises wrong exception" / etc>

Implementation plan: <1–3 bullet points>

Ready to proceed when you say go.
```

## Rules

- **Don't write the implementation.** This command's whole reason for existing is the gate before you do.
- **Don't skip the run-and-confirm step.** A failing test that hasn't been executed is unverified.
- **Don't write multiple tests for one behavior.** If the change has natural sub-parts, mention them in the plan; we'll write more tests after the first one goes green.
- If the project doesn't have a test runner set up at all, stop and tell the user — TDD without a runner is a non-starter, and quietly setting one up is out of scope for this command.
- The auto-commit hook will checkpoint the new test at end of turn — that's expected and fine.
