# Rebase conflict edits inside the block stage the markers with the fix

**Category**: anti-pattern
**Confidence**: 0.9
**Scope**: project
**Date**: 2026-10-08

## Anti-pattern

Resolving a rebase conflict with a targeted string edit whose oldString
matches a region *inside* the conflict block replaces only that region —
the `<<<<<<<` / `=======` / `>>>>>>>` markers and the losing side stay in
the file, and the subsequent `git add` stages them as the resolution.
Nothing downstream objects: JSON parsers see valid JSON when the markers
sit in a `.md` sibling, the bats suite has no marker guard, and the
broken prose ships to every consumer of the skill.

## Context

#641 resume rebase (2026-10-08): the worktree-pipeline-skill soft-deps
conflict was resolved by editing the text visible inside the HEAD side;
markers plus the duplicate variant shipped in commit 35a8bfd and were
caught only by the Step 9 diff review — `grep -rn "^<<<<<<<"` over the
tree found exactly the one file. The 657-test suite stayed green
throughout.

## Fix

- After every conflict resolution, before staging: `git diff --check`
  (flags leftover markers) or `grep -rn "^<<<<<<<\|^>>>>>>>"` over the
  touched files — the resolution edit must span the ENTIRE conflict block
  (first marker line through last), never just its readable text.
- A repo-level guard test (no conflict markers in tracked
  `*.md`/`*.json`/`*.bats`) turns this class into a hard failure; the
  inline-review marker sweep is the stopgap until that test exists.

## Evidence

feat/641 review round 2 (2026-10-08): markers shipped at
`skills/worktree-pipeline-skill/SKILL.md:92-104` in 35a8bfd, fixed in
5d37dba after diff review; suite green at both points.
