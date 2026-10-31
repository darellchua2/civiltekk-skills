# learnings-autoinject

A local OpenCode plugin that auto-injects a compact **manifest** of a project's
`LEARNINGS/*.md` files into the system prompt at session start, so the model
knows what learned knowledge exists without spending a tool call on `glob`.

It does **not** inject full file bodies — only titles + paths + a one-line
summary. The model `read()`s specific files on demand.

## Why

OpenCode does not auto-scan `LEARNINGS/` directories — the git-committed
markdown files are never surfaced automatically. `continuous-learning-skill`
documents the gap: *"OpenCode does NOT auto-scan LEARNINGS/ directories."*
This plugin automates the discovery step.

## Toggle (enabled by default)

| Control | Effect |
|---------|--------|
| `LEARNINGS_AUTOINJECT_DEFAULT=off` | Disable globally (default `on`) |
| `/learnings-off` | Disable for the current session |
| `/learnings-on` | Re-enable for the current session |
| `/learnings` | Report current state + file count |
| `/learnings-refresh` | Re-scan `LEARNINGS/` and rebuild the manifest on the next turn |

Per-session overrides take precedence over the env-var default.

## Env vars

| Var | Default | Purpose |
|-----|---------|---------|
| `LEARNINGS_AUTOINJECT_DEFAULT` | `on` | Global on/off |
| `LEARNINGS_AUTOINJECT_USER` | `off` | Also scan `~/.config/opencode/learnings/` (user-level) |
| `LEARNINGS_AUTOINJECT_OFF` | *(built-in regex)* | Agent names to exclude (read-only/research agents) |
| `LEARNINGS_AUTOINJECT_MAX` | `30` | Cap on files included in the manifest |

## Agent scoping

Read-only/research agents (`explore`, `general`, `explorer-subagent`,
requirements/discovery specialists, etc.) skip injection — they don't act on
LEARNINGS. The off-set regex mirrors `opencode-ponytail-scoped.ts` and can be overridden
via `LEARNINGS_AUTOINJECT_OFF`.

## What gets injected

```
<LEARNINGS AUTOINJECT — project: my-app>
Available learnings (use `read()` on a path for full detail):
- decisions/sqlite-over-postgres.md — Chose SQLite for local-first
- anti-patterns/mutable-default-args.md — Avoid mutable default args in Python
Source: LEARNINGS/ (2 project). Refresh: /learnings-refresh
</LEARNINGS AUTOINJECT>
```

~200-400 tokens for a typical 5-file repo.

## Hooks

| Hook | Role |
|------|------|
| `config` | Register slash commands |
| `session.hook("context")` | Core: append manifest (idempotent, off-set-gated; event carries `agent` + `sessionID` directly) |
| `command.transform` | Register `/learnings*` commands; persist per-session toggles inside `execute()` |

## Compatibility

- No `opencode.json` change — local plugins are glob-discovered.
- Requires `LEARNINGS/` to exist in the project root; absent → skips silently.

It is `.ts` (not `.mjs`) because OpenCode's local-plugin discovery glob matches only `*.{ts,js}` — an `.mjs` plugin file is silently never loaded (verified at v1.18.11; all five shipped v2 plugins are `.ts` and demonstrably load — diagnostic history: `git log --all --oneline -- research`).
