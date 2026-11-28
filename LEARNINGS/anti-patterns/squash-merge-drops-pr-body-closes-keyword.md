# `gh pr merge --squash` drops the PR body — `Closes #N` auto-close never fires

- **Category**: anti-pattern
- **Confidence**: 0.9
- **Scope**: project
- **Date**: 2026-11-28

A green squash merge whose PR body carried `Closes #707` left the issue OPEN: `gh pr merge --squash` composes the commit message from the PR title plus the commit list, not the PR body, so the closing keyword never reaches the default-branch commit. Rule: after any watcher/squash merge, run check-first on the ticket (`gh issue view --json state`) and close explicitly with the merge comment when still open — or pass the keyword in `--subject`/`--body`. Guard: assert `state == CLOSED` after the merge step, not just `mergeCommit` presence.
