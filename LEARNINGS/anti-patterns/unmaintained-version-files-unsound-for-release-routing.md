# unmaintained VERSION files are unsound signals for release-routing logic

**Category**: anti-pattern
**Confidence**: 0.9
**Scope**: project
**Date**: 2026-10-11

## Anti-pattern

Forking install behavior on "running tree version == latest release tag"
assumes the VERSION file tracks releases. When release tooling does not
maintain that file (semantic-release only tags; #669's tree still said
12.19.1 while v12.20.0 was the latest tag), the mismatch is permanent: every
maintainer-checkout `add` cloned the stale tag and silently installed it
over local edits. The installer-version bats tests were the canary (claude/
kilo translation fixtures seed the source tree, then expect the local tree
to install).

## Fix

Route only on signals that cannot lie about the tree: `.git` presence
separates npx-fetched caches (no .git → auto-resolve latest release tag)
from real checkouts (install own tree), and an explicit `--ref` is
deliberate intent honored everywhere. The initially-failing translation
tests became the permanent regression pins.

## Evidence

#670 exit gate, first pass: 3 failures (claude_target :135/:146,
kilo_target :66) — all three fixed by the `.git`-signal + explicit-ref
condition; 662/662 on the third pass (PLAN-668 Trace, db56245).
