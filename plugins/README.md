# plugins/

OpenCode runtime plugins for this configurator. Glob-discovered by the OpenCode
plugin loader — no registration needed.

**Activation:** plugins load at service start. `deploy/setup.sh` restarts the
background service automatically when the deployed plugin set changes — but
only from an interactive terminal; headless runs (tests, CI, agent-driven)
print the `opencode service restart` instruction instead, so a deploy never
kills the session that launched it. Unchanged re-deploys never restart.

## Naming convention (#456)

| Prefix | Meaning | Deployed to OpenCode? |
|--------|---------|----------------------|
| `opencode-*.ts` | OpenCode runtime plugin (v2 `{ id, setup }` local port) | Yes — `deploy_plugins()` copies them to `~/.config/opencode/plugins/` |
| `kimi-*` | Reserved: future Kimi Code plugin ports | No (once the rule-4 filter lands) |
| `kilo-*` | Reserved: future Kilo Code plugin ports | No (once the rule-4 filter lands) |

Rules:

1. **Every OpenCode runtime plugin file starts with `opencode-`.** The loader
   glob-discovers every `*.ts` in this directory, so the prefix is what keeps
   foreign-runtime plugins out of OpenCode's load path once they exist.
2. **Plugin `id` fields are stable** and independent of filenames — they appear
   in logs and debug greps; do not rename them when renaming files.
3. **`vibeguard.config.json` stays put.** The plugin resolves it via a search
   path (<project>/.opencode/ → deployed copies); renaming it breaks the
   setup.sh and setup.ps1 legs at once.
4. **Before the first `kimi-*`/`kilo-*` plugin lands**, restrict
   `deploy_plugins()` (deploy/setup.sh) to `opencode-*.ts` + non-code support
   files (`ponytail/` vendored dir, `ATTRIBUTION.md` — it holds the MIT license
   texts for the vendored code; dropping it would ship MIT code without its
   license). Deferred from #456 by decision; until then "never auto-deployed"
   is by convention, not enforcement.
5. Historical records (`LEARNINGS/`, `PLANS/`) keep old paths —
   they are never rewritten.

## Plugin notes

### `opencode-location-keepalive-v2.ts`

Keeps actively-running sessions from being evicted by OpenCode v2's 60-minute
location TTL (`location-activity.ts:25,62-71` at v2.0.18): the sweeper
interrupts every running session in a location with no *durable* session event
for 60 min — and streaming deltas / `session.tool.progress` are ephemeral, so
a healthy agent in a long silent tool or generation looks idle. Every
interval, each probe-confirmed busy session is PATCHed with its own unchanged
title (`ctx.session.update`), publishing a durable `session.renamed` that
resets the TTL. Idle sessions are never touched — idle locations still evict.

| Env var | Default | Meaning |
|---------|---------|---------|
| `OPENCODE_LOCATION_KEEPALIVE_ENABLED` | `true` | Master switch (`0/false/no/off` disables) |
| `OPENCODE_LOCATION_KEEPALIVE_INTERVAL_MS` | `1800000` (30 min) | Touch interval; clamped to the default at ≥90% of the 60-min TTL |
| `OPENCODE_LOCATION_KEEPALIVE_DEBUG` | `false` | Debug logging via `ctx.client.app.log` |

**Coordination constraint:** keep `OPENCODE_AUTO_CONTINUE_STALL_MS`
(default 15 min) strictly below the keepalive interval (default 30 min) —
otherwise the auto-continue busy-stall watchdog could be fed by keepalive
touches and never fire for true silent hangs.

MIT attributions for vendored code: see [ATTRIBUTION.md](ATTRIBUTION.md).

## laya-guard (#671)

`opencode-laya-guard.ts` + the `laya-guard/` subdirectory travel together through
`deploy_plugins()`'s directory copy. The plugin file stays zero-dependency
(house rule above); ONNX inference runs in a Node >= 24 sidecar that
`setup.sh` provisions into `~/.cache/laya-guard` — the ~1.7 GB model pre-pull
is opt-in via `--enable-pack laya`. Ships in shadow mode (log-only). Config:
first-wins `laya-guard.config.json` (project root → project `.opencode/` →
the shipped copy in this directory). See `laya-guard/README.md`.
