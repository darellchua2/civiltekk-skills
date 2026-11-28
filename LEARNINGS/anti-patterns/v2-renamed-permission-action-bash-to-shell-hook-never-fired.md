# A permission hook keyed on an action name the host renamed never fires

- **Category**: anti-pattern
- **Confidence**: 1.0
- **Scope**: project
- **Date**: 2026-11-26

laya-guard gated `actions: ["bash", "edit"]`, but OpenCode v2 renamed the action `shell` (v1 called it `bash`). Result: 0 of 35,764 shadow-log rows over six weeks were commands, while about 9,000 commands ran per 200 sessions. Every bats guard stayed green because it pinned source strings, never a live event. Rule: after writing a hook or rule keyed on an action or tool name, make it log one real event and read that log. `deploy/opencode.json` still carries three `bash` deny rules for the same reason (see `activating-dormant-deny-rules-without-history-check`).
