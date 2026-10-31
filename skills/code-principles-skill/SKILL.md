---
name: code-principles-skill
description: >-
  Code principles router — one entry point for clean code, code smells and
  refactoring, SOLID, design patterns, object design (responsibility-driven),
  complexity tradeoffs (KISS/YAGNI/DRY), and clean architecture. Routes each
  design or review question to the right principle route.
license: Apache-2.0
compatibility: opencode
metadata:
  protocol: autoresearch-opt-in
category: Code Quality
---

# Code Principles Router

One entry point for code-quality principle questions. Identify the question
type, run only the matched route's file, and follow it.

Provenance: routes consolidated from the seven former principle skills
(#690). Three routes (clean-code, code-smells, solid-principles) carry
opt-in autoresearch iteration-protocol sections — engage them only when the
task is an autonomous loop.

## Routes (load exactly one)

| Question | Route | Read | Skip-when |
|----------|-------|------|-----------|
| Readability, naming, small functions | `clean-code` | `references/routes/clean-code.md` | smell hunt → code-smells |
| Detect/fix smells + refactoring guidance | `code-smells` | `references/routes/code-smells.md` | readability → clean-code |
| SOLID application/review | `solid-principles` | `references/routes/solid-principles.md` | concrete smells → code-smells |
| GoF pattern selection/review | `design-patterns` | `references/routes/design-patterns.md` | principle questions → solid-principles |
| Responsibility-driven object design | `object-design` | `references/routes/object-design.md` | SOLID mechanics → solid-principles |
| KISS/YAGNI/DRY tradeoffs | `complexity-management` | `references/routes/complexity-management.md` | smell-level → code-smells |
| Layering, dependency rule, slicing | `clean-architecture` | `references/routes/clean-architecture.md` | class-level → object-design |

Route files open with their own **Load when / Skip when** lines.

## Hard rules

- One route per question; if a task spans two (e.g. "refactor this class"
  = smells + SOLID), run them sequentially — never preload both.
- The three retrofitted routes' iteration-protocol sections are OPT-IN:
  engage only for autonomous keep/revert loop tasks (protocol source:
  `autoresearch-skill`).
- Each route file owns its detail; this router never restates it.

## Gates

- Zero-preload: only the matched route file enters context.
- Findings cite the route file's rules (file:line), not generalities.
