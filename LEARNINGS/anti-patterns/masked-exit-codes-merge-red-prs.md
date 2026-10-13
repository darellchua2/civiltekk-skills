# Masked exit codes in watcher pipes merge red PRs; unclassified failures ship regressions

Date: 2026-10-13
Category: anti-pattern
Confidence: High (shipped a red PR this way — #674, reverted-forward by fix/673-plan-shape-pin)
Scope: any `gh pr checks --watch`-style merge gate; per-file test sweeps used as gates

## Summary

Two compounding mistakes let a red PR auto-merge:

1. **Pipe-masked verdict.** `timeout 1800 gh pr checks --watch | tail -5` makes
   the pipeline's exit status `tail`'s (0) — the "WATCH: green (exit 0)" branch
   fired while the printed table said `Run bats tests fail`. A merge gate must
   capture the watcher's own status (`set -o pipefail`, or drop the pipe), and
   green means rollup has zero FAILURE/TIMED_OUT/CANCELLED — not "the command
   exited 0".
2. **Failure classed as environmental without sampling the reason.** During a
   per-file local sweep, `test_plan_executor.bats notok=1` was binned as
   "outside the diff" because the file tests a skill — but it actually pins
   `build_plan`'s step shape, which the branch deliberately changed. A failure
   in a file that intersects the diff is unclassified until its assertion text
   is read; a blanket env-classification needs an A/B on base AND a sampled
   failure reason, not just a not-ok count.

Third leg of the same incident: the per-file sweep enumerated files with
`ls tests/*.bats | head -40` — 57 exist, so ~16 files (test_select_items.bats
among them) got zero local gate evidence, and three of those held pins on
behavior the branch deliberately changed (select+skills-only exclusivity, the
menu option-6 arm shape, the nvm install recommendation). Inventory for a
gate sweep must be the complete file set; a truncated list is a silent
coverage hole that CI then finds after merge.
