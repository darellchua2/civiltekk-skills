---
version: 1.0
---

# Stuck Detection

A loop with no plateau detection thrashes forever. Autoresearch uses a 3-tier strike system keyed on **consecutive non-improving iterations** (where "improving" means `score` moved in the configured direction beyond a noise tolerance, default ε = 0).

## Strike rules

| Strikes | Action | Rationale |
|---------|--------|-----------|
| 0–2 | Continue current strategy | Normal iteration noise |
| **3 consecutive** | **Pivot strategy** — change the hyperparameter family, code region, or approach branch | Same idea-space is exhausted |
| **5 consecutive** | **Paradigm shift** — re-read in-scope files, consider architectural change, consult references/papers | Strategy space is exhausted |
| **Max iterations** | Finalize — write summary, stop | Bounded-by-default guarantee |

## What counts as a strike

- An iteration where `score` did not improve (worse or flat within ε).
- An iteration where the evaluator crashed (`pass:false`, status `crash`).
- A reverted commit (`pass:false`) — always counts as a strike.

## What does NOT count as a strike

- A syntax-error fix — fixed immediately, does not consume an iteration (see `crash-recovery.md`).
- A guard-only failure where the metric itself improved — revert, but reset the strike counter only if the underlying idea was sound (judgment call; log the reasoning).

## Strike reset

The counter resets to 0 on **any** improving iteration. One good result after a dry spell is enough to continue the current strategy — do not pivot prematurely.

## Per-domain pivot examples

### ML (`the ml route`)
- 3-strike pivot: switch optimizer family (AdamW  Muon), change LR schedule, swap activation.
- 5-strike pivot: change model width/depth, try a different attention variant, re-examine `train.py` constants.

### Code (`the code route`)
- 3-strike pivot: switch from micro-optimization to algorithmic change, target a different hotspot.
- 5-strike pivot: reconsider the benchmark itself (is it measuring the right thing?), profile before continuing.

### Research (`the research route`)
- 3-strike pivot: switch search query family, change corpus (arXiv → Semantic Scholar).
- 5-strike pivot: re-scope the research question with the human (Tier 2 escalation).

## Ceiling interaction

A plateau (3 or 5 strikes tripped) does NOT automatically stop the loop — it triggers a pivot. The loop stops only when (a) predicate met, (b) plateau AND ceiling both tripped, or (c) max iterations reached. This lets a post-pivot breakthrough extend the run.

## Logging

Record the current strike count and pivot events in the TSV `description` column (e.g. `3-strike pivot: switch to Muon`). This makes the audit trail self-explaining when a human reviews it post-hoc.
