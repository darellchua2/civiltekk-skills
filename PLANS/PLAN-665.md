# PLAN: Fix goal plugin load failure under opencode 2.0.25 (pin bump to ^0.1.59)

**Branch**: feat/665
**Issue**: https://github.com/darellchua2/civiltekk-skills/issues/665
**Base**: main

## Acceptance Criteria
- [ ] `deploy/opencode.json` plugins entry reads `@prevalentware/opencode-goal-plugin@^0.1.59` (was `^0.1.48`, line 540)
- [ ] `LEARNINGS/decisions/goal-plugin-v2-readoption.md` documents the 2.0.25 breakage cause (host intercepts `effect` imports; `optionalWith` missing in host bundle; npm cache freezes caret resolution) and the new pin floor
- [ ] Deployed `~/.config/opencode/opencode.json` carries the new pin, redeployed from repo source (no hand-edit of deployed content)
- [ ] Stale OpenCode npm cache `~/.cache/opencode/npm/@prevalentware/` removed
- [ ] After service restart: log shows `loading plugin` under the new spec with no `failed to load plugin` follow-up, and `/goal` is present in the command catalog

## Dependency & Consumer Map

| Node (file/module) | Depends on (must precede) | Consumers (who depends on this) | Change risk |
|---------------------|---------------------------|---------------------------------|-------------|
| `deploy/opencode.json` (plugins array) | — | `deploy/setup.sh` `setup_config` (copies to `~/.config/opencode/opencode.json`); every deployed session's goal mode (`/goal`, `/pause_goal`, `/resume_goal`) | low — one version-string change inside an existing array entry |
| `LEARNINGS/decisions/goal-plugin-v2-readoption.md` | pin bump (content cites the floor) | future session recall (LEARNINGS autoinject), README watch-list context | low — docs only |
| `~/.config/opencode/opencode.json` (deployed) | repo source bump (2.1 redeploy) | the running opencode service (plugin resolution at boot) | low — scoped copy from source with backup |
| `~/.cache/opencode/npm/@prevalentware/` (runtime cache) | — | opencode plugin installer (frozen 0.1.48 resolution) | low — regenerated on next boot |

## Implementation Phases

### Phase 1: Repo source bump
- [x] **1.1** Change the plugins entry in `deploy/opencode.json` from `"@prevalentware/opencode-goal-plugin@^0.1.48"` to `"@prevalentware/opencode-goal-plugin@^0.1.59"`
    — **Why:** the repo is the single source for the deployed config; 0.1.59 is the upstream fix (dependency aliased `effect-goal-state: npm:effect@^3.21.2`, sidestepping the 2.0.25 host's `effect` interception whose `Schema` lacks `optionalWith`)
    — **Done when:** `git -C <worktree> diff` shows exactly that one-line change; JSON still parses (`python3 -m json.tool` exit 0 — the file is JSON)
    — **Consumers affected:** `deploy/setup.sh` config deploy; all deployed sessions' goal mode
    — **Done:** Pin bumped in `deploy/opencode.json` (line 540), exactly one line changed, JSON parses clean; files: deploy/opencode.json; fixes: none
- [x] **1.2** Sync `LEARNINGS/decisions/goal-plugin-v2-readoption.md`: update the Pattern line's pin to `^0.1.59`, add a dated note recording the 2.0.25 breakage (host-intercepted `effect` lacking `optionalWith`; caret pin did not float because the opencode npm cache freezes the resolved install — cache clear required on floor bumps)
    — **Why:** the decision file is the recall home for this plugin's pinning rationale; leaving `^0.1.48` in the Pattern text makes future sessions recall a stale floor and re-break
    — **Done when:** file references `^0.1.59`, carries the breakage note with the 2026-10-08 date, and keeps the existing caret-pin rationale intact
    — **Consumers affected:** future sessions recalling goal-plugin config facts (LEARNINGS autoinject)
    — **Done:** Pattern line now reads `deploy/opencode.json` + `^0.1.59` (also fixed the stale `opencode_app/` path from pre-#607), dated Update note appended with the host-interception cause and the cache-clear-on-floor-bump rule; files: LEARNINGS/decisions/goal-plugin-v2-readoption.md (main-checkout memory; repo-ignored — lands via end-of-ticket chore(learnings) sweep with .gitignore negation, deviation logged in Trace); fixes: none
- [x] **1.3** Commit Phase 1 (`fix(config): bump goal plugin pin to ^0.1.59 for opencode 2.0.25 (#665)`) and push `feat/665`
    — **Why:** the repo change must be durable before any runtime mutation; the commit footer carries the ticket ref for close-on-merge plumbing
    — **Done when:** `git log -1` shows the commit on `feat/665` and `git push` succeeds
    — **Consumers affected:** PR creation (Step 10), `Closes #665` detection
    — **Done:** Single atomic commit (config bump + PLAN ticks/Done/Trace) pushed to feat/665; files: deploy/opencode.json, PLANS/PLAN-665.md; fixes: none

## Trace
LOG 1.2 deviation: LEARNINGS/decisions/goal-plugin-v2-readoption.md is repo-ignored (.gitignore:37, no negation) — update applied to main-checkout memory; repo landing rides the end-of-ticket chore(learnings) sweep with a `!LEARNINGS/decisions/goal-plugin-v2-readoption.md` negation.
LOG pivot (2026-10-08 post-restore): ^0.1.59 LOADS clean on opencode 2.0.25 (no failed-to-load since restart), but sessions on strict providers fail to drain — `AI.Error: tools.function.parameters is not a valid moonshot flavored json schema ... properties.revisit_evidence: invalid type` (log 14:10:22Z+, 4 sessions). `revisit_evidence` verified in the plugin's own dist/server.js + README. User experiment confirmed causality: config deleted → sessions clean; restored → failures return. Decision (user): remove the plugin from the repo pending an upstream schema fix; pin bump alone is insufficient.
SKIP 3.1 restart-for-load — superseded by removal (service restart happens as removal verification instead).
SKIP 3.2 /goal catalog check — superseded (plugin absent → no /goal expected; `[plan:*]` marker aliases per plan-execution-skill remain valid without the plugin).

### Phase 2: User-space redeploy (no service disruption)
- [x] **2.1** Redeploy the config from source: `cp` backup of `~/.config/opencode/opencode.json` then copy the worktree's `deploy/opencode.json` over it — the scoped equivalent of `setup_config`'s copy step for the one changed file (full alternative: `./deploy/setup.sh --quick -y`, heavier — prompts and redeploys skills/AGENTS.md too)
    — **Why:** the running service reads the deployed file, not the repo; repo rule says redeploy from source, never hand-edit deployed copies
    — **Done when:** `grep goal-plugin ~/.config/opencode/opencode.json` shows `^0.1.59`; backup file exists beside it
    — **Consumers affected:** opencode service plugin resolution at next boot
- [ ] **2.2** Remove the frozen plugin cache: `rm -rf ~/.cache/opencode/npm/@prevalentware`
    — **Why:** the cache dir is keyed by the old spec resolution (0.1.48) and never re-resolves; removing it guarantees the next boot fetches 0.1.59+ (belt-and-braces alongside the changed spec string, and frees the orphaned install)
    — **Done when:** directory absent; next service start recreates it under the new spec
    — **Consumers affected:** opencode plugin installer only

### Phase 3: Runtime verification (DISRUPTIVE — orchestrator defers until after PR creation)
- [ ] **3.1** `opencode service restart`
    — **Why:** plugins load only at server start; this restarts the shared background service the current session runs on — deferral until after the PR exists keeps all durable work safe if the session disconnects
    — **Done when:** `opencode service status` reports a healthy URL post-restart
    — **Consumers affected:** all sessions on this machine (momentary reconnect)
- [ ] **3.2** Verify the fix: log shows `loading plugin` for the new spec hash with no `failed to load plugin`; `/goal` present via `opencode api get /api/command` (authenticated per LEARNINGS Docker note — v2 enforces auth on every route; local api command handles it)
    — **Why:** proves the acceptance criteria — the plugin actually loads and registers, not just that the pin changed (LEARNINGS rule: never trust a green deploy as plugin evidence — assert runtime presence)
    — **Done when:** both checks pass; any failure files an upstream follow-up and reopens the verification
    — **Consumers affected:** none (read-only checks)

## Technical Notes
- Root cause chain (verified 2026-10-08): opencode 2.0.24→2.0.25 auto-update (11:06) → host resolves plugin `effect` imports to its bundled Effect lacking `Schema.optionalWith` → plugin 0.1.48 `dist/server.js` (28 call sites) dies at import → `failed to load plugin` every boot since.
- Upstream fix in 0.1.59: dependency renamed to `effect-goal-state: npm:effect@^3.21.2`; `dist/server.js` imports `"effect-goal-state"` (verified in tarball).
- No `commands.goal` block exists and none must be added — v2 self-registers `/goal` (decision file rule).

## Dependencies
- None. Upstream `@prevalentware/opencode-goal-plugin@0.1.59` published 2026-10-08 12:41 (latest).

## Risks & Mitigation
- **0.1.59 itself broken under 2.0.25** → Phase 3.2 catches it; fallback: revert pin, hold the ticket, file upstream issue.
- **Service restart disrupts this session** → Phase 3 deferred to post-PR; all durable work (commit, push, PR) lands first.
- **Scoped copy diverges from setup.sh behavior** → backup retained; `setup.sh --quick -y` remains the full sanctioned rerun; a later full setup run is idempotent over the same content.
