---
name: refactoring
description: When and how to refactor — under tests, in small commits, with a defensible plan. Covers the technique catalog (extract, inline, replace conditional with polymorphism, etc.), the Mikado method for large refactors, the strangler-fig pattern for gradual replacement, and the discipline of separating refactor commits from feature commits. Pairs with `software-engineering-practices` (the TDD loop), `testing-strategy` (what coverage you need before refactoring), and `code-review` (how to review a refactor PR). Trigger when the user asks "should I refactor X first", "how do I clean this up", "what's the right way to break this apart", or proposes a refactor before adding a feature.
---

# Refactoring

Refactoring is **changing the shape of code without changing its behavior**. The behavior part is what matters: if your test signal can't tell you whether behavior changed, you're not refactoring — you're rewriting and hoping.

## When to refactor

- **Before adding a feature**, when the existing code makes the feature harder than it needs to be. Pay down debt only as much as the new feature pays you back.
- **After a smell pattern crystallizes**: same logic in three places, a function that takes 7 booleans, a class with 800 lines and 14 responsibilities, a god-object passed to everything.
- **When you have to change the code anyway** for a bug fix and the surrounding code is genuinely blocking comprehension.

## When NOT to refactor

- **Hot path under deadline.** Refactor *after* the deadline. Add a TODO and move on.
- **Code about to be deleted.** Don't polish what's getting removed next quarter.
- **You don't have tests.** See "Refactor under tests" below — you cover first, then refactor.
- **The refactor is "I don't like the style."** Style differences aren't a refactoring trigger.
- **Speculative future-proofing.** YAGNI. Don't add abstraction layers for needs that haven't materialized.

## Refactor under tests

The defining discipline. Fowler's rule: every refactoring move is small enough that you can run the test suite between moves and trust a green bar.

If the code you're about to refactor has no tests:

1. **Cover first.** Add characterization tests that pin current behavior — even if that behavior is wrong. The point is to detect *unintentional* changes; the bugs you fix are separate commits.
2. **Refactor.** Now you have a green-bar safety net.
3. **Improve.** Optionally fix the bugs the characterization tests pinned.

The user's TDD-default applies: a refactor without tests is a leap of faith. Don't take it.

## Refactor commits are pure refactors

The single most important rule: **never mix a refactor with a feature or a bug fix in the same commit.**

A refactor commit:
- Changes the shape, never the behavior.
- The test suite should pass at HEAD~1 *and* at HEAD with no test changes (or with test changes that are themselves refactors — moving a test, renaming a fixture).
- The PR description should say "no behavior change."

Mixing refactor + feature is how reviewers stop reading and how regressions slip through. If you find yourself making both kinds of change, **stop, commit the refactor, then commit the feature.**

## The technique catalog

The classic moves. Each is small enough to do, run tests, commit.

### Extract function / extract method

The most common move. A block of code that has a name (or could) becomes a function with that name.

```python
# Before
def process(data):
    # validate
    if not data: raise ValueError("empty")
    if len(data) > 1024: raise ValueError("too big")
    if not data[0].isalpha(): raise ValueError("bad first char")
    # ... real work ...

# After
def process(data):
    _validate(data)
    # ... real work ...

def _validate(data):
    if not data: raise ValueError("empty")
    if len(data) > 1024: raise ValueError("too big")
    if not data[0].isalpha(): raise ValueError("bad first char")
```

### Inline function

The opposite. When a one-line wrapper adds nothing or a function name is more confusing than the code it hides.

### Rename

Renaming is a refactor. Run tests, commit, move on. Use the IDE's rename when available (real refactor, not text replace).

### Extract variable / introduce explaining variable

Pull a complex sub-expression into a named local. Comments-as-code.

```c
// Before
if ((flags & 0x3) == 0x3 && buf[off] != 0xff) { ... }

// After
const bool is_active_session = (flags & 0x3) == 0x3;
const bool is_real_packet    = buf[off] != 0xff;
if (is_active_session && is_real_packet) { ... }
```

### Replace conditional with polymorphism

Long `switch`/`if` chain branching on a type tag → polymorphic dispatch (vtable, dict-of-functions, sealed enum + match).

Use sparingly: a 3-arm switch is not worth a class hierarchy. Reach for this when the branches duplicate structure (every arm has "validate, log, transform, save").

### Replace temp with query

A local variable computed from inputs becomes a function call. Lets you call the computation from elsewhere without copy-paste.

### Move function / move method

Function lives on the wrong type. Move it. Watch for the tests that reach into the old location.

### Split phase / split loop

One function does two things; split into two functions called in sequence. Or one loop does two things; split into two loops. Trades a tiny perf cost for a large readability win.

### Replace magic literal with named constant

`if (status == 7)` → `if (status == StatusReady)`. Always.

### Decompose conditional

A complex `if/else` where each branch is itself complex → extract each branch into a named function, leaving a clean dispatcher.

### Introduce parameter object

Three function parameters that always travel together → one struct/dataclass parameter. Especially valuable when adding a fourth.

### Replace loop with pipeline

When a language has decent pipeline support, an imperative loop with mutation can become a chain of `filter` / `map` / `reduce`. Worth doing when the chain reads better; not worth doing for the sake of fashion.

## Mikado method (for refactors that touch more than you expected)

Sometimes you start a "small" refactor and find the change requires three other changes, each of which requires more. Mikado method:

1. **Set the goal** at the top of a TODO file (`mikado.md`).
2. **Try the change naively.** It will fail (compile error, test failure, dependency issue).
3. **For each failure**, write down the prerequisite change and **revert** the current attempt. Add the prerequisite as a sub-goal.
4. **Recurse** on prerequisites until you find a leaf — a change you can make without breaking anything.
5. **Make the leaf change**, commit, and walk back up the tree.

The key move is the **revert**. You're using the failure as exploration, not commitment. The end result is a sequence of small green commits leading to the goal.

## Strangler fig (for replacing legacy)

Named after the strangler fig vine. To replace a large legacy system:

1. **Wrap the legacy** behind an interface that you control.
2. **Add the new implementation alongside**, gated by a flag or routing rule.
3. **Migrate callers one by one** to the new implementation. Each migration is a small commit.
4. **Delete the legacy** when the last caller is migrated.

The principle: never have a "big bang" cutover. Live in a hybrid state for as long as it takes.

## Refactor PR hygiene

A good refactor PR:

- **Single coherent move.** Not "I touched 47 files cleaning things up."
- **Tests unchanged** (or refactored separately, in the same PR but obvious commits).
- **PR description states "no behavior change"** and names the move ("extract `validate_config` from `load`").
- **Diff is reviewable.** A 4000-line refactor PR is unreviewable; the reviewer rubber-stamps and you ship a regression.
- **Trivially revertable.** If something breaks in production, the PR can be reverted as a unit.

If a refactor crosses 800 lines or touches >10 files, **split it.** Mikado helps you find the seams.

## What "behavior" means

For refactor purposes, behavior is what callers and external systems can observe:

- Public API surface (signatures, return values, raised errors, exit codes).
- Side effects (file writes, network calls, log output, metric emission).
- Performance, when callers can observe it.

Behavior **does not** include:

- Internal helper functions and modules.
- Source-level structure of files.
- Variable names within a function.
- The exact bytes of an internal log message (be careful with this — sometimes ops tooling depends on log lines).

When changing one of the "does not include" items, you're refactoring. Changing one of the "includes" items is a feature/fix and needs new or updated tests.

## Refactoring and the auto-commit hook

The auto-commit hook produces `wip(claude):` checkpoints. When refactoring:

- The wip commits are fine to accumulate during exploration (especially Mikado-style).
- When ready, use `/squash` to consolidate into clean refactor commits.
- **Don't squash a refactor and a feature into one commit.** When `/squash` proposes a single commit, reject and ask for a split.

## When the refactor reveals a bug

Common: characterization tests pin behavior, you start refactoring, and you realize the behavior was wrong.

**Don't fix the bug in the refactor commit.** Order the commits:

1. Add a failing test for the bug (separately committed).
2. Fix the bug (separately committed).
3. Refactor (separately committed).

This sequence lets you bisect, revert, and review each change for what it is.

## When to stop

Refactoring has a stopping rule: **does the next step pay off the next feature you're about to add?** If yes, do it. If you're polishing for its own sake, stop. The user's CLAUDE.md is explicit: don't add abstractions for hypothetical future needs.

A clean, working system is the goal. "Maximally clean" is not.
