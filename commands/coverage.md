---
description: Run tests with coverage instrumentation and surface uncovered lines/branches as a prioritized TODO list.
argument-hint: [optional — module/file to focus on, default: project-wide]
allowed-tools: Bash(pytest:*), Bash(coverage:*), Bash(cargo:*), Bash(go:*), Bash(zig:*), Bash(make:*), Bash(test:*), Bash(grep:*), Read, Glob
---

# /coverage — find blind spots in the test suite

Coverage is a guardrail, not a goal (per `testing-strategy`). The point of running it is to find the **paths that aren't tested**, then decide which of them deserve a test versus which is dead code that should be deleted.

Argument: `$ARGUMENTS` — optional module/file to focus on. If empty, project-wide.

## Procedure

1. **Identify the language and testing setup** in parallel:
   - Python: `pyproject.toml` / `pytest.ini` / `setup.cfg` for pytest config; presence of `coverage` / `pytest-cov`.
   - Rust: `Cargo.toml`; coverage via `cargo llvm-cov` (modern) or `cargo tarpaulin` (older).
   - Go: built-in `go test -cover`.
   - Zig: less standardized; `kcov` or build with `-fno-stripping` and use `llvm-cov` against the test binary.
   - C/C++: build with `--coverage` (gcc) or `-fprofile-instr-generate -fcoverage-mapping` (clang); `gcovr` / `llvm-cov` for reports.

2. **Run the suite with coverage** — mark with `[log]`:
   ```bash
   # Python
   pytest --cov=<package> --cov-report=term-missing --cov-report=html --cov-branch
   
   # Rust
   cargo llvm-cov --html
   cargo llvm-cov report
   
   # Go
   go test -cover -coverprofile=cover.out ./...
   go tool cover -html=cover.out -o coverage.html
   go tool cover -func=cover.out | tail -20
   
   # C/C++ with gcov
   make CFLAGS='--coverage' && ./run_tests
   gcovr --html --html-details -o coverage.html
   gcovr --txt | head -40
   ```
   Reason: `[log: measuring coverage to find uncovered branches]` (or similar).

3. **Insist on branch coverage** when the language supports it. Line coverage misses partial-branch holes (e.g., `if x and y` with only the truthy combinations exercised). `--cov-branch` (Python), `cargo llvm-cov --branch` (Rust), `gcovr --branches` (C/C++).

4. **Identify the gaps** — read the report and categorize each uncovered region:

   | Category | Action |
   |---|---|
   | **Unreachable / dead code** | Delete it. Don't add a test that pins a behavior nobody needs. |
   | **Genuinely-tested but coverage tool missed it** | Investigate (e.g., subprocess invocation, async branch, exception handler). Add fixture or pragma if confirmed. |
   | **Error path, not currently tested** | High priority — error paths are where bugs hide. Add test. |
   | **Boundary / edge case** | High priority. Add test. |
   | **Defensive code that "can't happen"** | Decide: prove it can't (delete) or prove it can (test). Don't leave the "in case" comment. |
   | **Happy path missed** | Test scaffolding bug — should have been covered by other tests. Investigate. |

5. **Produce a prioritized TODO list** in the report:
   - 🔴 **High**: error paths, security-relevant code, public API surface.
   - 🟡 **Medium**: edge cases, recently-touched code (`git blame` is helpful here), conditional branches.
   - ⚪ **Low**: legacy code with stable behavior, pure helpers with obvious correctness.
   - 🗑️ **Delete candidate**: looks dead. Tag for the user to confirm.

6. **Report**:
   - Overall coverage % (line + branch). Trend if there's previous data.
   - Top 5 most-uncovered files (with absolute uncovered-line count, not just %).
   - The categorized TODO list above.
   - **Don't recommend a coverage threshold or gate.** Per the skill, that's a footgun.

## Hard rules

- **Don't add tests just to hit a number.** Quality > coverage.
- **Don't gate PRs on coverage delta.** It encourages low-quality "test that the test ran" tests.
- **Don't celebrate 100% coverage.** It means the test suite ran every line — not that every behavior is verified.
- **Don't suppress coverage with `# pragma: no cover` / `#[cfg(not(coverage))]` / `--ignore=` to win the number.** Suppress only when the line is genuinely unreachable in test (e.g., `if __name__ == '__main__'`), and document why.

## See also

- `testing-strategy` skill — what a "good" test looks like for a covered branch.
- `software-engineering-practices` skill — TDD as the primary defense (writing tests first beats running coverage second).
- The `test-writer` agent — given a specific uncovered function, propose tests for it.
