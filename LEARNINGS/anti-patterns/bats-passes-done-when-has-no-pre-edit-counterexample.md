# "bats passes, including the new tests" is a done-when that cannot fail

- **Category**: anti-pattern
- **Confidence**: 0.85
- **Scope**: project
- **Date**: 2026-11-26
- **Ticket**: #703 (Step 7 architecture review)

## Symptom

PLAN-703 step 2.2 added two tests to an existing bats file. Its done-when was "bats <file> reports every test ok, including the two new ones". That command exits 0 on the unmodified tree, where the file holds its five existing tests, so the step could be ticked with both new tests missing.

## Rule

For a step that adds tests to an existing file, pin the count: `bats -c <file>` prints N (it prints M before this step), plus a passing run. Name the new tests in the step text.

Run every done-when against the unmodified tree at plan time and keep the output. A done-when whose command already passes there has no counterexample.
