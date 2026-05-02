---
description: Take a bug description and produce a minimal failing test that reproduces it. Test only — no fix in this command.
argument-hint: [bug description, ideally with what was expected and what happened]
allowed-tools: Read, Edit, Write, Glob, Grep, Bash(pytest:*), Bash(cargo:*), Bash(go:*), Bash(zig:*), Bash(make:*), Bash(test:*), Bash(grep:*)
---

# /repro-bug — minimal failing test from a bug report

Bridge between "user reports something is wrong" and "we have a regression test that would catch it again." This command writes the test only — it does **not** fix the bug. Fixing comes after, ideally as a separate commit/turn so `git bisect` and PR review work cleanly.

Argument: `$ARGUMENTS` — the bug description. Ideally includes: what was attempted, what was expected, what actually happened, and the relevant input/state.

## Procedure

1. **If the description is incomplete, ask** before writing anything. The minimum you need:
   - **Trigger**: what input or sequence of operations causes the bug?
   - **Expected**: what should happen?
   - **Actual**: what happens instead?
   - **Environment** if relevant (OS, version, config flags).

   Don't fabricate any of these. A wrong repro is worse than no repro.

2. **Locate the relevant code** — find the function/module that the bug description names or implies. Use `Grep`/`Glob`. Read it.

3. **Pick the test layer**:
   - **Unit** if the bug is in pure logic on inspectable inputs.
   - **Integration** if the bug only manifests when components combine — *especially* if a database, filesystem, or subprocess is involved (see the user's feedback memory: integration tests must hit real boundaries, not mocks).
   - **End-to-end / characterization** if the bug is a user-visible regression and you can't isolate the cause yet.

   When in doubt, write the *highest* layer test that fails fast on this bug. You can lower the layer later with the diagnosis.

4. **Find the test file** — match the project's existing convention. Look at neighboring tests for naming, fixtures, and asserting style.

5. **Write the test**. Properties:
   - **Names the behavior**: `test_<subject>_<condition>_<expected>` style. Example: `test_parse_returns_empty_list_for_whitespace_only_input` (per `testing-strategy`).
   - **Minimal**: smallest input that triggers the bug. Strip everything that doesn't matter.
   - **Self-contained**: no implicit setup, no order dependency on other tests.
   - **Fails for the right reason** (verify in the next step).
   - **No mocks for boundaries the user has feedback memory about** (DB, filesystem) — use the real thing.
   - **Comment** at the top with the bug description and any context the user gave.

6. **Run the test** with `[log: confirming the bug repro fails as expected]` and confirm it fails. **Read the failure carefully**:
   - If the failure message matches the bug ("Expected X, got Y" exactly as described): ✅ correct repro.
   - If the test fails for a *different* reason (import error, fixture problem, off-by-one in the test itself): ❌ wrong test. Fix the test, don't touch the SUT.
   - If the test passes: the repro is wrong, or you're testing the wrong code path. Stop and reconsider with the user.

7. **Report**:
   - Path to the new test file:line.
   - The failing assertion / output.
   - One-sentence next-step recommendation: "this looks like an off-by-one in `parse_header`:line 47 — fix the SUT, not the test."
   - A reminder: this command writes the test only. Apply the fix in a separate commit.

## Don't

- **Don't fix the bug in this command.** The point is the test exists *before* the fix lands so the diff is clean and the regression is verifiably caught.
- **Don't add multiple tests** "while I'm here." One bug, one test. Other coverage gaps are `/coverage`'s problem.
- **Don't pin behavior you suspect is wrong elsewhere.** A characterization test pins current behavior, including bugs. If the description mentions "this also seems wrong but not what I'm reporting" — surface it, don't pin it.
- **Don't mock the broken layer.** If the bug is in `parse_X`, the test must call `parse_X` against a real input, not a mock that pretends it returned the bug's symptom.

## After

The next step is to fix the bug and confirm the test now passes. That's a separate turn:
- Read the failing test.
- Diagnose the SUT bug.
- Apply a focused fix.
- Re-run the test (and the rest of the suite).
- Commit (the auto-commit hook will checkpoint; `/squash` later for a clean history).

## See also

- `testing-strategy` skill — what makes a test minimal, well-named, and durable.
- `software-engineering-practices` skill — TDD discipline.
- The `debugger` agent — for harder bug-repros where you need to first triage the failure across logs/traces/cores before you can write a minimal test.
