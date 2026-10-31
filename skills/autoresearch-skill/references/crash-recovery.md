---
version: 1.0
---

# Crash Recovery

Failures are normal in an autonomous loop. This table classifies each failure mode and prescribes the response. The goal is to **never silently keep a broken commit** and to **avoid wasting iterations on fixable mistakes**.

## Failure-mode → response table

| Failure mode | Detection | Response | Counts as iteration? |
|--------------|-----------|----------|----------------------|
| **Syntax error** in modified code | Evaluator crashes immediately with `SyntaxError` / `IndentationError` | Fix immediately, re-run. Do NOT commit the broken state. | **No** — free fix |
| **Runtime error** (exception, traceback) | Evaluator exits ≠ 0 with Python traceback in log | Up to **3 fix attempts**. If still failing, skip the idea, log `crash`, revert, move on. | Yes (after 3rd failed attempt) |
| **Timeout** | Run exceeds time budget (e.g. >10 min for a 5-min ML run) | Kill process, treat as `pass:false`, revert, log `crash` | Yes |
| **OOM (out of memory)** | `CUDA out of memory` / `killed` (OOM killer) | Retry with a **smaller variant** (halve batch size, reduce model width). If smaller variant also OOMs, skip idea. | Yes |
| **Infinite loop** | Run exceeds 2× time budget with no output | Kill after timeout, revert, log `crash`, blacklist the offending pattern | Yes |
| **Hook-blocked commit** | `git commit` rejected by pre-commit hook | Do NOT bypass the hook. Log `hook-blocked`, revert the working-tree change, move on. | Yes |
| **Metric-error** (evaluator output not parseable) | Last stdout line is not `{.*}` JSON | Revert, log `metric-error`. Do NOT guess a score. | Yes |
| **Guard failure** (metric improved but guard failed) | Guard exits ≠ 0 | Revert regardless of metric improvement. Log `discard` with guard-failure note. | Yes |
| **Network/dependency error** | `ConnectionRefusedError`, missing package, auth failure | Log, skip iteration. Do NOT attempt to install packages or modify `pyproject.toml` mid-loop. | Yes |

## General principles

1. **Never keep a commit whose evaluator never produced a verdict.** If in doubt, revert.
2. **Fixable mistakes are free.** A typo does not consume an iteration — fix and re-run.
3. **Fundamentally broken ideas are skipped, not fixed.** If an architectural change OOMs even at half size, the idea is wrong; log and move on.
4. **Hooks are never bypassed.** A pre-commit hook is a hard gate; `--no-verify` is forbidden.
5. **Repeated identical crashes escalate.** 3 identical `crash` rows in a row → treat as a 3-strike pivot trigger (see `stuck-detection.md`).

## Logging crashes

Crash rows in the TSV use:

- `metric: 0.0`
- `delta: 0.0`
- `status: crash` (or the specific status from the table)
- `description:` one-line root cause (e.g. `OOM at batch=64, halving`)
- `evaluator_output: -` (no verdict produced)

The `research_log.md` entry should include the tail of the stack trace for post-hoc debugging.

## Resume after crash

If the loop process itself crashes (not just one experiment), `autoresearch-loop.sh` restarts the session. On resume:

1. Re-screen the pinned predicate (`screen-state-predicate`).
2. Read the last TSV row to recover iteration count and best-so-far.
3. Do NOT re-run the last experiment — its result is already logged.

A crash mid-experiment (process killed before evaluator ran) is logged as `crash` with `commit: -` and the working tree is reset to `HEAD`.
