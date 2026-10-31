---
name: civiltekk-ponytail-audit-skill
description: >-
  Over-engineering audits and debt tracking — whole-repo audit (ranked
  delete/stdlib/native/yagni/shrink findings, net removable count, one-shot
  report), diff-only review (concrete replacements), and `ponytail:` comment
  harvest into a debt ledger (ceiling + upgrade trigger per marker, no-trigger
  rot). Triggers: audit for over-engineering, find bloat, what can I delete,
  over-engineered diff, simplify this change, review for bloat, ponytail
  shortcuts, what did ponytail defer, tech debt markers.
license: Apache-2.0
compatibility: opencode
category: Code Quality
---

<!--
  Vendored from @dietrichgebert/ponytail v4.10.0 (MIT)
  Sources: https://github.com/DietrichGebert/ponytail/blob/v4.10.0/skills/ponytail-audit/SKILL.md
           https://github.com/DietrichGebert/ponytail/blob/v4.10.0/skills/ponytail-review/SKILL.md
           https://github.com/DietrichGebert/ponytail/blob/v4.10.0/skills/ponytail-debt/SKILL.md
  Pinned at tag v4.10.0. Re-vendor deliberately on upstream bumps.
  See ../../plugins/ATTRIBUTION.md for license and attribution.
-->

Consolidates ponytail-audit-skill + ponytail-review-skill + ponytail-debt-skill (#603).

## What I do

Cut over-engineering, on three scopes:

1. **Detect the route** (§Routes) — explicit > inferred > ask-once.
   Explicit: the request names the scope ("audit for over-engineering",
   "find bloat", "what can I delete" → `whole-repo-audit`;
   "over-engineered diff", "simplify this change", "review for bloat" →
   `diff-review`; "ponytail shortcuts", "what did ponytail defer",
   "tech debt markers" → `debt-ledger`). Inferred: the artifact under
   review (a diff/PR → `diff-review`; the whole tree → `whole-repo-audit`;
   `ponytail:` comments or a deferral ledger → `debt-ledger`). Ambiguous
   ("is this over-engineered?") → ask once — one ask per run, then proceed
   on the answer.
2. **Load the route's values file** (`references/audit.md` /
   `references/review.md` / `references/debt.md`) and apply its contract.
3. The routes compose — a `diff-review` finding a `ponytail:` marker feeds
   `debt-ledger`; a `whole-repo-audit` pass may end with a ledger sweep.
   Load per request, not all three up front.

## Side files (load rules)

| Read | When | Use |
|------|------|-----|
| `references/audit.md` | route `whole-repo-audit` | Repo-wide scan instead of a diff: tag set (delete/stdlib/native/yagni/shrink), hunt list, ranked one-line findings, net removable count, one-shot boundary |
| `references/review.md` | route `diff-review` | Diff-only review: finding format, tag set, good/bad examples, net-lines scoring, smoke-test exemption, revert phrases |
| `references/debt.md` | route `debt-ledger` | `ponytail:` comment harvest: grep scan, per-marker ledger rows (ceiling + upgrade trigger), no-trigger rot flags, persistence opt-in |

Side files carry VALUES only; this file carries the METHOD. The shared tag
vocabulary lives in the values files (review.md defines it; audit.md and
debt.md reuse it). The runtime `/ponytail` ladder itself is the scoped
plugin (`plugins/opencode-ponytail-scoped.ts`), not this skill — this skill
is the on-demand reviewer/auditor.

## Routes

| Situation | Route |
|-----------|-------|
| "audit for over-engineering", "find bloat", "what can I delete", repo-wide bloat sweep, no diff in hand | `whole-repo-audit` |
| "over-engineered diff", "simplify this change", "review for bloat", a diff/PR under review | `diff-review` |
| "ponytail shortcuts", "what did ponytail defer", "tech debt markers", `ponytail:` comment harvest, deferral ledger | `debt-ledger` |
| Ambiguous ("is this over-engineered?") | ask once (§What I do step 1), then route; headless default `diff-review` when a diff exists, else `whole-repo-audit` |

## Boundaries

- The three routes were formerly peer skills — those boundaries are internal
  now; the route table above is the boundary logic.
- Scope: over-engineering and complexity only. Correctness bugs, security
  holes, and performance are explicitly out of scope — route them to a
  normal review pass. Smell cataloging and KISS tradeoffs belong to
  the `code-smells` route of `code-principles-skill` / the `complexity-management` route of `code-principles-skill`; this skill cuts,
  those classify.
- All routes list findings and apply nothing; `debt-ledger` writes a file
  only on explicit ask. One-shot each.
- Mode switching ("/ponytail lite", "stop ponytail-audit", "normal mode")
  belongs to the scoped plugin and the values files' revert phrases.

## Agent behavior rules

- One ask per run maximum (route detection); headless/CI: no asks — infer
  from the artifact (diff → `diff-review`; tree → `whole-repo-audit`;
  markers → `debt-ledger`).
- End every route with its closing metric (`net:` line or marker count) —
  "Lean already. Ship." / "Clean ledger." when nothing is found.
- Never flag a single smoke test or `assert`-based self-check for deletion
  (ponytail minimum, not bloat).
