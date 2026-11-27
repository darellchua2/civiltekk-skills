# OpenCode — harness values

> Values only; the method lives in SKILL.md. Copy this file's skeleton for another
> harness as `references/<harness>.md`. Every value carries a citation or a
> verify-locally note.

## Managed toolset

- `browser.*` — "controls the browser attached by the OpenCode desktop app"
  (https://opencode.ai/v2/docs/tools/, §Browser). Whether the tools are listed
  depends on the OpenCode version. Observed 2026-09-28 on an earlier v2 build:
  listed even with no desktop app attached. On v2.4.2 an agent lists them only
  while a desktop app holds the session's pane (anomalyco/opencode#65969;
  observed 2026-11-27: plugin `opencode.browser` active, no `browser`
  namespace in a terminal session). Presence is still not connection: a pane
  another window takes is withdrawn mid-session, so keep probing.

## Probe (read-only, side-effect free)

- `browser.tabs.list({})` — lists the session's tabs and focused tab; needs no
  tabID and mutates nothing. (Runtime-observed catalog inspection, 2026-09-28. No
  documented connection-state query exists — verify-locally on OpenCode upgrades.)

## Mutating first-touches to avoid

- `browser.tabs.open` — opens a tab and focuses the Review pane.
- `browser.preview` — opens a file in the Review pane.

## Disconnect signature

- `[browser.disconnected] No desktop browser is connected to this session. Open
  this session in the desktop app and wait for it to connect.` — runtime-observed;
  appears nowhere in V2 docs (verify-locally). Repeating the call cannot succeed.

## Fallback stacks (independent of the desktop app)

- `playwright.*` — self-contained, launches its own browser; default for
  verify-then-handoff (load check + screenshot).
- `chrome-devtools.*` — CDP-level inspection (traces, CPU profiles, console) when
  the check needs more than a load check.

## Interface detection (researched 2026-09-28 — configurator issue #628)

- NO documented signal: no env var, plugin-context field, config field, or API
  endpoint exposes desktop-vs-terminal (plugins guide documents zero `OPENCODE_*`
  vars; `/api/info` returns version/pid/urls/paths only; all 136 API operations
  checked against https://opencode.ai/v2/docs/api/).
- `OPENCODE_TERMINAL=1` observed in a live terminal session but undocumented —
  do not build on it (candidate for an upstream OpenCode feature request).
- Sessions can move between interfaces mid-life (the disconnect error instructs
  attaching the desktop app to a live session) — hence SKILL.md rule 6.
