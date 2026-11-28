# Pattern: give a decision model the text that carries the signal, and use its score to prompt, not block

- **Category**: pattern
- **Confidence**: 0.9
- **Scope**: project
- **Date**: 2026-11-26

laya-guard asked the model what a command would do but showed it a file *name* (edits) or the first 200 characters (commands). Bare names became a lookup table (35,764 edits, every path always the same score). At 200 characters the dangerous token was hidden in 24 of 30 force/delete commands and ranking was 0.66–0.84; at 1,200 characters (the English checkpoint reads about 320 tokens) it was visible in 71 of 80 and ranking rose to 0.92. Same lesson as the civiltekk-cad-app spike (25% on bare strings): before tuning a question, check what text the model can actually see.

Let the score rank and raise a prompt, never block outright: on real traffic the model's highest scores went to routine deletions (`rm -rf /tmp/...`, `git worktree remove --force` after a PR), so any block line interrupts normal work. Hard blocks belong in deterministic permission rules.
