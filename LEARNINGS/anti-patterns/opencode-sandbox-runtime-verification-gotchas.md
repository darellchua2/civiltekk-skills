# Verifying OpenCode at runtime in a sandbox: two things HOME/XDG do not isolate

- **Category**: anti-pattern
- **Confidence**: 0.85
- **Scope**: project
- **Date**: 2026-11-26
- **Ticket**: #703 (Step 5)

## Symptom

Two surprises while measuring a config change against the installed OpenCode v2.4.1 with `HOME`, `XDG_CONFIG_HOME`, `XDG_DATA_HOME` and `XDG_RUNTIME_DIR` redirected to a scratch directory:

1. `opencode service start` in the sandbox refused with "Managed service port 49374 ... is already in use by PID ...". The managed background service listens on a fixed default port, so a sandboxed `service start` or `service stop` acts on the same port as the developer's real service.
2. `opencode api GET /api/model` against a just-started server answers 200 with an empty `data` list until plugins finish loading. `opencode models` waits for plugins; `opencode api` does not.

## Rule

Never run `opencode service start`, `stop` or `restart` in a sandbox on a developer machine.

- Start `opencode serve --hostname 127.0.0.1 --port <port>` instead.
- For model data, call `opencode api --server <url>` with `OPENCODE_PASSWORD` set from the server's "server password" startup line, and poll until `data` is non-empty (about three seconds here).
- Confirm isolation first with `opencode debug paths <name>`, and judge teardown by the port no longer listening.
