# Tracked append-only index files are merge hotspots — untrack derived indices

`LEARNINGS/_index.md` was a tracked, append-only file every pipeline appended
to at end-of-ticket (#682-style `chore(learnings)` sweeps). Any two branches
that both captured learnings conflicted at rebase/merge, and a locally-dirty
index blocked plain `git pull` in the main checkout. Root cause: the file was
machine-redundant — the autoinject plugin builds its manifest from a
`readdirSync` scan and never reads the index — so the tracked copy bought
nothing and cost every parallel workflow.

**Decision**: untrack derived indices (`git rm --cached`, keep local copy,
covered by the existing `LEARNINGS/**/*.md` ignore) and rewrite the
instruction sources (`continuous-learning-skill` steps 5-6, worktree-pipeline
Step 9, code-review-inline, reviewer-baseline, AGENTS.md memory hygiene) to
"write only the body; never stage the index". Per-body `.gitignore` negations
append at **end of file** — mid-file inserts were the remaining
parallel-branch touchpoint.

**Rejected**: union merge driver (fixes conflicts, keeps the
dirty-tree-blocks-pull failure, silently duplicates same-learning entries);
per-category indexes (N smaller hotspots, same disease).

- **Confidence**: 1.0
- **Scope**: project
- **Summary**: tracked append-only multi-writer indices are merge hotspots; if a runtime consumer scans the directory itself, untrack the index as a local derived cache and make the instructions say "body + end-of-file .gitignore negation only" — union merge and category splits treat symptoms (#684)
- **Date**: 2026-10-31
