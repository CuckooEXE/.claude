---
description: Surface breaking surface-area changes vs the base branch — what's added, removed, signature-changed, semver-relevant.
argument-hint: [optional base ref, default: main / master]
allowed-tools: Bash(git:*), Bash(grep:*), Bash(rg:*), Bash(diff:*), Bash(python:*), Bash(cargo:*), Bash(go:*), Bash(zig:*), Bash(test:*), Read, Glob
---

# /api-diff — surface-area diff vs base

Goal: tell the user what changed in the *public* API surface of this branch vs the base. Helps with version bump decisions, changelog drafting, and "did I accidentally break someone."

Argument: `$ARGUMENTS` — base ref. Defaults to `main` if it exists, else `master`. Falls back to first parent of HEAD if neither.

## Procedure

1. **Resolve the base ref** and confirm it exists. If `$ARGUMENTS` was empty, default in this order: `origin/main`, `main`, `origin/master`, `master`, `HEAD~1`. Tell the user which base you picked.

2. **Identify the language**. Use the project's manifest (`pyproject.toml`, `Cargo.toml`, etc.). For polyglot projects, run per-language passes.

3. **Run the language-native API diff if available**:

   | Language | Tool | Notes |
   |---|---|---|
   | Rust | `cargo public-api` | Reports the full pub surface. Diff with `cargo public-api --diff <base>..HEAD`. |
   | Rust | `cargo semver-checks` | Newer; semver-aware classification of changes. |
   | Python | `griffe` (with `mkdocstrings`'s diff mode) | Or roll a small AST walk. |
   | Go | `apidiff` (golang.org/x/exp) or `gorelease` for module-level | `gorelease` is for v2+ release validation. |
   | C/C++ | `abi-compliance-checker` (heavy), or compare exported symbols via `nm -D --defined-only` between built artifacts | Symbol-level only without ABI tooling. |

4. **Fallback: AST/grep-based surface scan** when no native tool is available. Walk through each modified file and identify:
   - **Added public symbols** — new functions/classes/methods/constants/exports.
   - **Removed public symbols** — gone since base.
   - **Signature changes** — same name, different parameters / return type / generics / errors.
   - **Visibility changes** — public → private (breaking) or private → public (additive).
   - **Type changes** — public type fields/variants added/removed/renamed.

   Heuristic per language:
   - Python: search for top-level `def `, `class `, `__all__` entries in non-test, non-underscore-prefixed files.
   - Rust: `pub fn`, `pub struct`, `pub enum`, `pub trait`, `pub use`, `pub const`, `pub mod`.
   - Go: capitalized top-level identifiers in non-`_test.go` files.
   - C: non-`static` functions and global variables in headers.
   - C++: anything in a non-`internal::` / non-`detail::` namespace exposed via headers.
   - Zig: top-level `pub` declarations.

5. **Classify each change** per `api-design` skill:

   - **Breaking**: removal, signature change requiring callers to update, error type change, semantic change.
   - **Additive**: new symbol, new optional parameter, expanded accepted input range.
   - **Internal**: visibility tightened on something that wasn't documented public, or a refactor with no surface impact.

6. **Report**:

   ```
   # API surface diff: <branch> vs <base>
   
   ## Summary
   <N breaking, M additive, K internal>
   
   ## Recommended version bump
   <major / minor / patch> — <reason>
   
   ## Breaking
   - **REMOVED** `pkg.foo` — deprecated since 0.4.0; this is the removal.
   - **CHANGED SIGNATURE** `pkg.bar(a, b)` → `pkg.bar(a, b, *, c=None)` — c is optional, but old positional callers calling with kwargs may need adjustment.
   - **CHANGED ERROR** `pkg.baz` now raises `BazError` instead of `ValueError`.
   
   ## Additive
   - **ADDED** `pkg.new_thing(x: int) -> str`
   - **EXTENDED** `pkg.Config` — new optional field `verbose: bool = False`
   
   ## Internal (no consumer impact)
   - **PRIVATIZED** `pkg._helper` — was never in __all__; tightening visibility.
   - **REORGANIZED** `pkg/util.py` split into `pkg/util/{a,b}.py` — public re-exports preserved.
   
   ## Files inspected
   <N files matched the public-surface heuristic>
   <N skipped (test files, internal modules)>
   ```

7. **Suggest changelog entries** for each non-internal change in the project's existing format. (`/release-notes` is the proper destination — link to it.)

## Hard rules

- **Don't modify any code.** Read-only.
- **Don't claim "no API changes" unless every modified file was inspected.** If the heuristic might miss something (dynamically-attached attributes, plugin hooks, FFI exports), say so.
- **Don't ignore deprecation removal as "internal."** A deprecated public symbol is still public until removed; the removal is a breaking change in the version it lands.
- **Document false-positive heuristics** at the bottom of the report. ("Counted `pkg/internal.py` because the heuristic doesn't know about your `internal` convention. Likely safe to ignore.")

## See also

- `api-design` skill — what counts as breaking, deprecation discipline, SemVer rules.
- `/scope` — overall change summary, broader than the API surface.
- `/release-notes` — turn the API diff into changelog entries.
