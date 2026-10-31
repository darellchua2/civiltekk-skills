#!/usr/bin/env bash
# guard.example.sh
#
# Example safety-net (Guard) command pattern for the code route.
# A Guard is a separate command from the Verify evaluator: it does NOT emit
# {"pass":bool,"score":N}; it exits 0 (green) or non-zero (forces revert).
#
# Typical use: "I'm optimizing bundle size (Verify), but the test suite
# (Guard) MUST stay green at every iteration."
#
# See references/iteration-safety.md §Verify vs Guard.

set -euo pipefail

# ---------------------------------------------------------------------------
# 1. Run the test suite (or any invariant that must stay true)
# ---------------------------------------------------------------------------
if ! npm test; then
  echo "GUARD FAILED: npm test exited non-zero" >&2
  echo "Forcing revert per autoresearch protocol (see iteration-safety.md)." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 2. (Optional) Run a second invariant — e.g. typecheck
# ---------------------------------------------------------------------------
if ! npm run typecheck; then
  echo "GUARD FAILED: npm run typecheck exited non-zero" >&2
  exit 2
fi

# ---------------------------------------------------------------------------
# 3. (Optional) Assert no security-sensitive files were touched
# ---------------------------------------------------------------------------
if git diff --name-only HEAD~1 HEAD | grep -qE '(^|/)(\.env|credentials|\.npmrc)$'; then
  echo "GUARD FAILED: guarded file modified" >&2
  exit 3
fi

echo "GUARD OK"
exit 0
