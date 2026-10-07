# Anti-pattern: preserved-phrase lists need a full assertion sweep

When a restructure must preserve grep-asserted phrases (bats guards that hold
a contract's wording in place), enumerating the preserved list by reading only
the section being edited misses assertions that target OTHER sections in the
edit region.

PLAN-560 step 4.1 preserved the four Step-10 phrases it knew about, but
`tests/test_tiered_gating.bats` also asserts `Step 9 code review` and
`(unconditional) backstops` — phrases living in Step 7's prose, inside the
region the same PLAN phase edits. The omission was caught in review, not by
the author.

**Rule:** before restructuring a file with phrase assertions, derive the
preserve-list from the assertion file — grep the test for every literal it
checks against the target file — not from the section you plan to touch.

- **Confidence**: 0.85
- **Scope**: project
- **Date**: 2026-09-25

## Recurrence (2026-10-08, #662)

Second instance, REWORD direction: PLAN-662 reworded `plan-execution-skill` 4c ("add one WORK LOG line naming the anchor…" → "append one LOG line … to `## Trace`") without grepping `tests/test_tiered_gating.bats:132`, which pins the old literal `WORK LOG line naming the anchor` — gate-red at the exit gate, fixed by unpinning the test to the new invariant-bearing phrase. The rule cuts both ways: derive BOTH the preserve-list (phrases that must survive) and the retire-list (phrases being replaced) from the assertion file before touching contract prose.
