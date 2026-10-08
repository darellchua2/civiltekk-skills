## Decision: Re-adopt goal mode as @prevalentware/opencode-goal-plugin (v2), caret-pinned

**Context**: The v1 pin `opencode-goal-plugin@0.8.1` was removed in `5f95d9c` (v1-only plugin versions under a v2 runtime produced boot warnings; the README watch-list tracked the re-add). Upstream rescoped to `@prevalentware/opencode-goal-plugin` and shipped OpenCode v2 support (since `0.1.30`; `0.1.48` published 2026-09-07; actively released).
**Pattern**: `deploy/opencode.json` → `"plugins": ["@prevalentware/opencode-goal-plugin@^0.1.59"]` — caret pin, no options object (secure defaults: `restricted_agents: ["plan"]`, `allow_goal_execution_from_plan: false`), and **no `commands.goal` block**: on v2 the package self-registers `/goal`, `/pause_goal`, `/resume_goal` (`register_command: true` default), so a manual block risks a duplicate-command conflict. (Supersedes the v1-only "plugins array + commands block both required" rule — that applied to v1 `opencode-goal-plugin` only; folded here 2026-09-21 from the removed v1-era plugin-config solution, #506.)
**Rationale** (corrected per plan review): the v1 breakage cause was v1-only plugin versions under a v2 runtime plus exact pins that never floated to v2 releases — **not pinning itself**. A caret pin to the v2-native line bounds drift within `0.1.x`, keeps boots reproducible (repo convention: committed lockfile), and upgrades deliberately. Fallback: if opencode v2 cannot resolve the `@^` constraint at boot, use the bare name AND record the audited version (`npm view`) in the README re-add note.
**Alternatives Considered**: `wejick/opencode-goal` (rejected: 0★, 2 commits, GitHub-only, 4000-char objective cap, no Plan-mode safety). Vendoring the source (rejected: unlike vibeguard, upstream ships v2 — no port needed). Bare name as default (rejected: unreviewed overnight drift on every boot, no reproducibility).
**Trade-offs**:
- Pro: reproducible boots; Plan-mode safety (plan-agent goals stay paused, continuation pinned to `build`); evidence-gated completion; token/turn budgets with wrap-up handoff.
- Con: caret still floats `0.1.x` patches.
**Docker note** (residual folded 2026-09-21 from the removed Docker-v1-inertness solution, #506): #387 resolved the Docker inertness class — the image installs the v2 binary via the scoped `@opencode/cli` npm package and the compose healthcheck asserts goal-command presence in `/api/command`. Residual rule that outlives it: **v2 enforces HTTP auth on EVERY route (localhost included)** with an auto-generated password — healthchecks and scripted API calls must authenticate via the password file the entrypoint materializes. Never trust `docker compose build` green as plugin evidence; assert runtime presence.
**Update (2026-10-08, #665)**: opencode 2.0.24→2.0.25 changed the plugin host to resolve plugin `effect` imports to its bundled Effect, whose `Schema` lacks `optionalWith` — plugin 0.1.48 died at import on every boot (`failed to load plugin`). Caret pins do NOT self-heal this: opencode's npm cache (`~/.cache/opencode/npm/<spec>/<hash>/`) freezes the resolved install per spec string. Floor bumped to `^0.1.59`, where upstream aliases the dependency to `effect-goal-state: npm:effect@^3.21.2` so `dist/server.js` imports the real Effect and sidesteps the host interception. **Rule: on any pin floor bump, also `rm -rf ~/.cache/opencode/npm/@prevalentware` before restart.**

**Update (2026-10-08 #665, removal)**: REMOVED from `deploy/opencode.json` (commit 8ef3e36). 0.1.59 loads clean on 2.0.25, but the plugin's own tool schema (`revisit_evidence` parameter, in its dist/server.js) fails strict providers — moonshot rejects it (`Invalid API parameter` on session drain), breaking every session on such providers. Differential proof: config deleted → sessions clean; restored → failures. **Re-add rule: plugin-load green is NOT sufficient — retest session drain on a strict provider (moonshot) before re-adopting any version.**

**Confidence**: 0.85
**Scope**: project
**Date**: 2026-09-14

**References**:
- `opencode_app/opencode.json` — `plugins` array
- `README.md` — v2 watch-list re-add note (Knowledge Persistence section)
- `opencode_app/Dockerfile`, `opencode_app/docker-entrypoint.sh` — v2 binary install + authenticated goal-presence healthcheck (#387)
- Issues #382, #387; commit `5f95d9c`
