# An EXIT trap inside a bats test suppresses its failure report

- **Category**: anti-pattern
- **Confidence**: 0.95
- **Scope**: project
- **Date**: 2026-11-26
- **Ticket**: #703 (Step 8)

## Symptom

`trap 'rm -rf "$dir"' EXIT` inside a test (the temp-dir cleanup pattern `tests/test_provider_pins.bats` used) replaces the trap bats-core 1.13.0 relies on to report a failing test. Under a mutation that made the test fail, bats printed no `not ok` line for it, only `# bats warning: Executed 6 instead of expected 7 tests`.

Verified with a three-test file on bats 1.13.0: the failing test without the trap reports `not ok` and the failing line, the failing test with the trap vanishes, and a passing test is unaffected.

## Rule

Clean up through a file-level `teardown()`, which bats runs even when the test fails. Never set an EXIT trap inside a test.

The suite still exits 1, so CI stays red, but the test name and the failing line are lost. Gate: `grep -nE "^[[:space:]]+trap .* EXIT" tests/*.bats` prints nothing.
