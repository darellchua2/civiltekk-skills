#!/usr/bin/env bash
#
# check_progress.sh — quick status viewer for a running or completed
# autoresearch project. Prints: last 10 TSV rows, current iteration count,
# best-so-far metric, and the metric direction.
#
# Adapted from uditgoenka/autoresearch (MIT) — see THIRD_PARTY_LICENSES.md.
#
# Usage:
#   check_progress.sh ./my-experiment
#   check_progress.sh ./my-experiment --all     # print every row
#   check_progress.sh ./my-experiment --watch   # refresh every 30s
#
set -uo pipefail

PROJECT="${1:-}"
PRINT_ALL=0
WATCH=0
[ "${2:-}" = "--all" ]  && PRINT_ALL=1
[ "${2:-}" = "--watch" ] && WATCH=1

if [ -z "$PROJECT" ]; then
  printf 'usage: check_progress.sh <project-dir> [--all|--watch]\n' >&2
  exit 64
fi

if [ ! -d "$PROJECT" ]; then
  printf 'check_progress: no such directory: %s\n' "$PROJECT" >&2
  exit 2
fi

TSV=$(ls "$PROJECT"/*-results.tsv 2>/dev/null | head -1)
if [ -z "$TSV" ]; then
  printf 'check_progress: no *-results.tsv in %s\n' "$PROJECT" >&2
  exit 2
fi

# Metric direction is recorded in the second comment line of the TSV.
DIRECTION=$(grep -m1 '^# metric_direction:' "$TSV" \
            | sed 's/^# metric_direction:[[:space:]]*//')
METRIC_NAME=$(grep -m1 '^# metric:' "$TSV" \
              | sed 's/^# metric:[[:space:]]*//')

render() {
  clear 2>/dev/null || true
  printf '=== autoresearch progress: %s ===\n' "$PROJECT"
  printf 'metric: %s   direction: %s\n' "${METRIC_NAME:-?}" "${DIRECTION:-?}"
  printf 'tsv:    %s\n\n' "$TSV"

  # Current iteration count = number of data rows (lines starting with a digit).
  TOTAL=$(grep -c '^[0-9]' "$TSV" 2>/dev/null || echo 0)
  printf 'iterations logged: %s\n\n' "$TOTAL"

  # Best-so-far: pick max or min of column 3 depending on direction.
  if [ "$TOTAL" -gt 0 ]; then
    if [ "$DIRECTION" = "higher_is_better" ]; then
      BEST=$(awk -F'\t' '/^[0-9]/ { if (max == "" || $3+0 > max+0) max=$3 } END { print max }' "$TSV")
    else
      BEST=$(awk -F'\t' '/^[0-9]/ { if (min == "" || $3+0 < min+0) min=$3 } END { print min }' "$TSV")
    fi
    printf 'best %s so far: %s\n\n' "${METRIC_NAME:-metric}" "${BEST:-?}"
  fi

  printf '--- last rows ---\n'
  if [ "$PRINT_ALL" = "1" ]; then
    cat "$TSV"
  else
    tail -n 10 "$TSV"
  fi
}

if [ "$WATCH" = "1" ]; then
  while true; do
    render
    printf '\n[watch mode: refreshing in 30s, Ctrl-C to exit]\n'
    sleep 30
  done
else
  render
fi
exit 0
