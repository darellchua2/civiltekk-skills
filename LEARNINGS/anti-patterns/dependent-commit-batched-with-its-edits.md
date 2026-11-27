# Anti-pattern: a commit issued in the same tool batch as the edits it must include

- **Category**: anti-pattern
- **Confidence**: 0.9
- **Scope**: project
- **Date**: 2026-11-27
- **Summary**: File edits and the `git add` + `git commit` that must contain them were issued in one parallel tool batch. The commit ran between the edits and captured the file half-edited. Edits go in their own batch; the commit is a later step, verified with `git show HEAD:<file>`.

## What happened

Pipeline run for #705, Phase 2 commit `8819046d` (never pushed in that state). Three edits to `PLANS/PLAN-705.md` and the commit were sent as one batch. All three edits reported success, but the commit captured one of them (an acceptance-criterion tick) and missed the other two (the step tick and its Done line). Every tool call reported success, so the partial commit was silent; the residue count printed in the same output was the only signal.

## Why it happens

Parallel tool calls in one batch carry no ordering guarantee. A commit depends on every edit that should precede it, so it is never an independent call.

## Rule

1. Edits first, as their own batch.
2. The commit or push in a later step.
3. After committing, confirm with `git show HEAD:<file>` that each tick or line the commit must carry is in it.
4. Fix a partial commit by re-staging and amending before the push, and record it in the trace.

## Alternatives Considered

Trusting the batch order: rejected, because the harness reports every call as successful and the partial state stays invisible until a later check reads the committed file.
