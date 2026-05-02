---
description: Propose a stepwise, TDD-friendly refactor plan for a target file/module — analysis only, no code changes.
argument-hint: [target — file, module, or class to refactor]
allowed-tools: Read, Glob, Grep, Bash(git:*), Bash(test:*), Bash(wc:*)
---

# /refactor-plan — propose a refactor plan, don't execute

This command is **planning only**. It produces a numbered sequence of small refactor moves, each one independently committable, with a green-test checkpoint between each. Per the `refactoring` skill, the discipline is "small steps, tests pass between each."

Argument: `$ARGUMENTS` — the target. May be a file, a class/function, a module, or a directory. If empty, ask.

## Procedure

1. **Read the target** in full. If it's a directory, also read the most-coupled files (callers, sibling modules).

2. **Read the existing tests** for the target. If there are none, that's the *first* item in the plan: cover before refactoring (per `refactoring` skill, "refactor under tests").

3. **Identify the smells** — what is actually wrong with the current shape? Be specific. Smells worth naming:
   - Long function (>100 lines doing many things).
   - Duplicate code across N call sites.
   - High-cycle complexity (deep nesting, many branches).
   - Boolean parameter creep (3+ booleans in a signature).
   - God class / module (touched by everything, depends on everything).
   - Implicit state / hidden coupling (mutating globals, reaching across modules).
   - Mixed levels of abstraction in one function.
   - Comment-as-substitute-for-naming (a comment that should be a function name).
   - Defensive code for cases that can't happen (the user's CLAUDE.md flags this).

4. **Decide the goal**. State it in one sentence. Example: "Split `Parser` into `Tokenizer` + `Parser` so each can be tested independently."

5. **Decide the moves**. Use the technique catalog from `refactoring` skill: extract function, rename, inline, extract variable, replace conditional with polymorphism, introduce parameter object, etc. Each move is small.

6. **Order the moves** so each one keeps tests green. Standard ordering:
   1. **Cover** — add characterization tests if missing. (Skip if coverage is already adequate.)
   2. **Inline-and-rename pass** — clean up names and remove redundant indirection so subsequent moves are easier to see.
   3. **Extract-and-pull-up pass** — pull cohesive code into named functions/classes.
   4. **Move-and-split pass** — relocate things to where they belong.
   5. **Cleanup pass** — delete dead code, remove obsolete comments, simplify signatures.

7. **For each move, state the green-bar checkpoint** — what test you'd run to confirm no behavior change. If a move can't be checked, that's a problem; either add coverage or break the move into smaller pieces.

8. **Estimate scope** for each step:
   - Lines changed (rough).
   - Files touched.
   - Whether the step is mechanical (rename, inline) or judgmental (extract method, split class).

9. **Apply the Mikado check** — ask: would step N break tests because step N-1 wasn't done? If yes, you have an ordering bug. If no, the plan is committable.

10. **Report** the plan as:

    ```
    # Refactor plan: <goal>
    
    ## Goal
    <one sentence>
    
    ## Smells found
    - <smell> (<location>) — <why it matters>
    - ...
    
    ## Pre-requisites
    - <e.g., "no characterization tests for parse_header — Step 0 covers">
    
    ## Plan
    
    ### Step 0 — Cover
    <what tests to add, where>
    Verify: `pytest path/to/test_X.py` passes.
    
    ### Step 1 — <name>
    <move description>
    Files: <list>
    Lines: ~N
    Verify: <tests or compile + tests>
    
    ### Step 2 — ...
    ...
    
    ## Out of scope
    - <smell intentionally not addressed, with one-line reason>
    ```

11. **Don't apply any of the steps.** This command produces the plan only. The user reviews, course-corrects, and runs each step as a separate turn.

## Don't

- **Don't propose a "big refactor."** If the plan can't be split into 4–8 steps, it's a rewrite. Tell the user.
- **Don't mix in feature changes.** Refactoring changes shape, not behavior. Any "while we're here, let me also add X" goes in a separate plan.
- **Don't propose steps that can't be tested.** Without a test signal, the move is a leap of faith — bad refactoring.
- **Don't recommend deleting "obviously dead" code without showing the search.** "Obviously" is where the bug always was. Show grep results.
- **Don't propose abstractions for hypothetical future needs** (per CLAUDE.md). The plan addresses *current* smells.

## See also

- `refactoring` skill — the technique catalog and the discipline.
- `testing-strategy` skill — what coverage you need before you start.
- `code-review` skill — review heuristics, useful for the "should this be refactored at all" judgment.
- The `refactor-planner` agent — fresh-eyes alternative to this command, useful when the file is large enough that a focused agent helps.
