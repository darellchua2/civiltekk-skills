---
version: 1.0
---

# Evaluator Contract

The evaluator is the **sole** source of keep/revert truth in the autoresearch loop. It is a program (not an LLM judgment) that, given the current state of the system under optimization, emits exactly one JSON object on the last line of stdout:

```json
{"pass":bool,"score":N}
```

## Field semantics

| Field | Type | Meaning | Consumed by |
|-------|------|---------|-------------|
| `pass` | boolean | `true` → keep commit; `false` → revert | keep/revert decision |
| `score` | number (int or float) | Raw metric value at this iteration | TSV audit trail, trend analysis |

`pass` is **not** derived from `score` crossing a threshold inside the loop driver — the evaluator itself decides the boolean. Direction (`higher_is_better` / `lower_is_better`) is set at init time and only affects trend/plateau analysis, never the keep/revert decision directly.

## Required properties

1. **Mechanical** — deterministic given the same system state (or, for stochastic evaluators, reproducible within a documented tolerance band).
2. **Single-line JSON** — the loop driver greps the last line for `{.*}`; anything before it is free-form logging.
3. **Bounded runtime** — the evaluator must terminate. A timeout is treated as a crash (see `crash-recovery.md`).
4. **Side-effect free** — the evaluator must not modify the system under optimization (no training, no commits, no writes outside its own scratch dir).

## Tier taxonomy

| Tier | Evaluator type | Example domain |
|------|---------------|----------------|
| 1 | Mechanical program (shell/Python/binary) | ML val_bpb, test pass-count, bundle size |
| 2 | Agent-as-evaluator (LLM judge with rubric) | Literature review quality, prose clarity |
| 3 | Human-in-the-loop (manual sign-off) | Shipping, deploy (out of scope for autonomous loop) |

Tier 2 is an explicit fallback declared in the skill body when no mechanical evaluator applies (`the research route`). Tier 3 never runs autonomously.

## Example evaluators

### Python script

```python
# evaluator.py — outputs {"pass":bool,"score":N}
import json, subprocess
out = subprocess.check_output(["pytest", "--tb=no", "-q"]).decode()
passed = out.count(" passed")
result = {"pass": passed >= 40, "score": passed}
print(json.dumps(result))
```

### Shell one-liner

```bash
score=$(npm run coverage 2>/dev/null | grep -oE 'All files[^|]*\|[^|]*' | grep -oE '[0-9.]+$')
python3 -c "import json,sys; s=float('$score'); print(json.dumps({'pass': s>=80.0, 'score': s}))"
```

### Compiled binary

```bash
./bench --json-tail   # prints auxiliary info, last line is {"pass":bool,"score":N}
```

## Guard vs evaluate

A **Guard** runs after evaluate and independently forces revert on failure (e.g. `npm test` must pass even while optimizing bundle size). Guards do NOT emit `{"pass":bool,"score":N}` — they exit 0/nonzero. See `iteration-safety.md` for the Verify/Guard separation.

## When the evaluator crashes

Evaluator exit ≠ 0, no parseable JSON on the last line, or timeout → treat as `pass:false`, revert the commit, log `crash` status. Do NOT silently keep a commit whose evaluator never ran.
