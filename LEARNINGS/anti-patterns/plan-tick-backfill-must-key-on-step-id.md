# Plan-tick backfill must key on the step ID, not a nearest-preceding-line scan

Scripting `[x]` ticks + `— Done:` lines into a PLAN by scanning backwards from
each `— **Consumers affected:**` line for "the most recent step line" attributes
every later phase's Done lines to the last matched earlier-phase step — 11 Done
lines appeared for 4 steps, silently mislabeling steps 2.x/3.x with step-1
evidence.

**Why**: the backward scan has no phase boundary; once step 1.4 matches, every
subsequent un-keyed Consumers line reuses it.

**Fix**: match each step line's `**N.M**` ID first, carry the ID forward as
state, and only emit a Done line while the current ID is in the done-set; reset
to none on any non-matching step. Then assert the global count: `Done:` lines ==
steps in the done-set (4), and each Done line directly follows its own step's
Consumers line.

Caught by post-transform count check (`grep -c '— \*\*Done:\*\*'` → 11 ≠ 4);
`git checkout` the PLAN and re-run the keyed transform.

- **Confidence**: 1.0
- **Scope**: project
- **Summary**: PLAN tick/Done-line backfills driven by "nearest preceding step line" scans misattribute evidence across phase boundaries — key each emitted line on the parsed step ID (N.M) and assert Done-line count == done-set size before committing (seen in #681 Phase 1 transform; reverted and redone keyed)
- **Date**: 2026-10-31
