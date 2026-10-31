---
version: 1.0
---

# Audit Trail

The audit trail is the human's only window into an overnight run. It must be **append-only**, **machine-parseable**, and **self-explaining**.

## TSV format (8 columns)

File: `<skill>-results.tsv` (e.g. `autoresearch-ml-results.tsv`, `coverage-results.tsv`). Tab-separated.

```
iteration	commit	metric	delta	status	description	timestamp	evaluator_output
```

| Column | Type | Notes |
|--------|------|-------|
| `iteration` | int | 0 = baseline; 1..N = loop iterations |
| `commit` | short SHA (7 chars) | `-` for non-committed (crash before commit) |
| `metric` | float | The `score` from `{"pass":bool,"score":N}`; `0.0` for crashes |
| `delta` | float | `metric - prev_metric`; `0.0` for baseline |
| `status` | enum | `keep` \| `discard` \| `crash` \| `no-op` \| `hook-blocked` \| `metric-error` |
| `description` | string | One-line summary; **no tabs, no commas** (use spaces) |
| `timestamp` | ISO 8601 | `YYYY-MM-DDTHH:MM:SS` |
| `evaluator_output` | string | Raw last-line JSON from the evaluator, or `-` |

Header line (comment-prefixed):

```
# metric_direction: higher_is_better
# skill: the ml route
iteration	commit	metric	delta	status	description	timestamp	evaluator_output
```

## Baseline row (iteration 0)

Written before the first experiment. Establishes the starting metric.

```
0	a1b2c3d	0.997900	0.0	keep	baseline	2026-03-09T22:00:00	{"pass":true,"score":0.9979}
```

## Append-only

Never rewrite or delete rows. A reverted experiment still gets a row (status `discard`). The trail is the evidence; rewriting it destroys reproducibility.

## research_log.md

Companion to the TSV — a free-form markdown log, also append-only. One section per iteration:

```markdown
## Iteration 3 (2026-03-09T22:15:00)
- Commit: c3d4e5f
- Idea: switch to GeLU activation
- Evaluator: {"pass":false,"score":1.005000}
- Decision: discard (metric worsened)
- Delta vs baseline: +0.0071
```

The TSV is for machines and quick scanning; `research_log.md` is for the human reading the result over coffee.

## progress.png

Optional chart regenerated after each kept iteration (matplotlib, metric vs iteration). Karpathy's original repo ships one as `progress.png`. Regeneration rules:

- After every **kept** commit (not on discards — they don't move the metric).
- On loop end (final state chart).
- Never committed to git (it's a build artifact) — leave untracked, like `results.tsv`.

## Reading the trail

`check_progress.sh` prints the last 10 TSV rows, current iteration count, and best-so-far metric. Use it to assess a running or completed loop without opening the full file.
