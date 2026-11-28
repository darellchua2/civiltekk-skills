# Activating a dormant deny rule without checking history breaks routine work

- **Category**: anti-pattern
- **Confidence**: 0.95
- **Scope**: project
- **Date**: 2026-11-26

The three `bash` deny rules in `deploy/opencode.json` are inert under OpenCode v2 (the action is `shell` now). Renaming them looked like a safe one-word fix, but 120 days of session history showed it would have started blocking 22 routine `git push --force-with-lease` pushes and 12 `rm -rf /tmp/...` cleanups: `git push --force*` and `rm -rf /*` are whole-value wildcards. Rule: before a change makes an existing rule live, count what it would have denied in real history, then settle the pattern with the owner. The rules were left as they were and reported instead.
