# A fixed look-ahead window lets a PLAN step borrow the next step's rationale lines

- **Category**: anti-pattern
- **Confidence**: 0.9
- **Scope**: project
- **Date**: 2026-11-26
- **Ticket**: #703 (Step 6d self-check)

## Symptom

The 6d self-check looked for Why / Done when / Consumers affected in a fixed four-line window after each step line. PLAN-703 has no blank lines between steps (the canonical template's own shape), so step 1.1 with its Why line deleted reached into step 1.2 and borrowed that step's Why. The check reported zero malformed steps.

## Rule

The three markers must be the three lines immediately after the step line (i+1 to i+3). No look-ahead.

Pair the checker with a negative fixture built from a real numbered step. Two fixtures in a row removed the template's example line instead, and one (`grep -v -m1`) produced a one-line file. Both pass an empty input silently, so print the step count and require it.
