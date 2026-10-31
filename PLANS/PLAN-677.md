# PLAN: Decouple deploy/setup.sh — data-driven MCP packs, TUI installer, CivilTekk rename

**Branch**: feat/677
**Issue**: https://github.com/darellchua2/civiltekk-skills/issues/677
**Base**: main

## Acceptance Criteria

- [ ] Adding a new MCP pack = one `pack-<name>.json` file; zero setup.sh edits (`install` block drives config merge + runtime install)
- [ ] `install_markitdown_mcp` / `install_docling` replaced by generic `install_pack_runtime`; dry-run contract preserved (no pip/npm under `--dry-run`)
- [ ] All 4 MCP prose surfaces derive from `deploy/opencode.json` + packs dir; `test_mcp_count_consistency.bats` passes without hand counts
- [ ] `provision_laya_guard` lives in `plugins/laya-guard/provision.sh`; `deploy_plugins` invokes provision hooks generically; `LAYA_GUARD_SKIP`/`LAYA_GUARD_WARM`/dry-run semantics preserved
- [ ] `deploy/seed-provider-auth.mjs` owns auth.json/pi/codex seeding; merge-never-clobber + corrupt-file parking + `0600` perms preserved
- [ ] `tui.mjs install-wizard` emits `install-plan.json`; `--from-plan` ≡ equivalent CLI flags (identical `build_plan`); non-TTY aborts; cancel writes nothing
- [ ] `civiltekk-setup` / `civiltekk-init` deployed primary; `opencode-setup` / `opencode-init` kept as compat symlinks; no log-path break
- [ ] README Installation section = 5-entry-point table; derived-count greps (`ships N MCP server entries`) still pass
- [ ] Full `bats tests/` suite green; `test_laya_guard.bats`, `test_markitdown_skill.bats`, `test_docling_skill.bats`, `test_pack_permissions.bats`, `test_help_parity.bats`, `test_dry_run_leaks.bats` updated for new locations

## Dependency & Consumer Map

| Node (file/module) | Depends on (must precede) | Consumers (who depends on this) | Change risk |
|---------------------|---------------------------|---------------------------------|-------------|
| `deploy/packs/pack-*.json` | — | `deploy/merge-packs.mjs` (mcp/permissions fragments only — `install` key ignored by construction), `setup.sh` (`validate_enable_pack`, new `install_pack_runtime`), `deploy/tui.mjs` `scanPackNames`, `dump_catalog` | medium |
| `deploy/setup.sh` | packs schema (P1), laya provision.sh (P3), seed-provider-auth.mjs (P4) | `deploy/setup.ps1` + `setup.cmd` (thin launchers), `tests/deploy_delegate.bats` (line-order pin), `tests/test_dry_run_leaks.bats` (greps), `tests/test_help_parity.bats`, `test_setup_ps1_vars.bats` (ps1 pin-absence), `opencode-setup` shim users, README | high |
| `deploy/tui.mjs` + `installer/tui-primitives.mjs` | pack install blocks (P1, for wizard step descriptions) | `setup.sh` (provider-picker/tier-editor/select-items), `installer/init.mjs` (primitives import) | medium |
| `plugins/laya-guard/*` | — | `setup.sh` `deploy_plugins` provision hook (new), `tests/test_laya_guard.bats` | medium |
| `deploy/seed-pi-provider.mjs`, `~/.local/share/opencode/auth.json` writer | — | `setup.sh` credential steps, `tests/test_agent_detection_seed.bats` | low |
| `README.md` | wizard + rename (P5, P6) | `tests/test_mcp_count_consistency.bats` (`ships N MCP server entries` grep), `tests/test_count_drift.bats` | low |
| `skills/civiltekk-install-assistant/` | rename (P6) | end users in-session (self-contained per #437 — no cross-skill deps to break) | low |

Phase order: P1 → P2 (listings read pack data); P3, P4 independent; P5 after P1 (wizard step 3 + review screen read install blocks); P6 after P5 (wizard header carries the new name); P7 last (documents P5+P6).

## Implementation Phases

### Phase 1: Self-describing pack installs ✅

- [x] **1.1** Add optional `install` block to `deploy/packs/pack-markitdown.json` and `pack-docling.json` (`runtime: "pip"`, `packages: [...]`, `idempotent: {pipShow, version, import}`); move the pin-rationale prose into each pack's `$comment`/`install.notes`; teach `deploy/merge-packs.mjs` to strip `install` alongside `$comment` in the reserved-key destructure (`const { mcp, permissions, $comment, install, ...restPack } = pack`) — unknown pack keys are deep-merged into the deployed config today (`merge-packs.mjs:182-183`), so without this the install blob would land in every deployed opencode.json
    — **Why:** the pack file becomes the single source for both config merge AND runtime install; pin bumps stop requiring setup.sh edits; the merger must never write non-config keys into the deployed config
    — **Done when:** `node merge-packs.mjs --config <tmp> --packs-dir deploy/packs --packs markitdown` produces output byte-identical to the pre-change merger (no `install` key in output); `jq .install deploy/packs/pack-markitdown.json` parses
    — **Consumers affected:** `merge-packs.mjs` (reserved-key strip), `setup.sh` install call sites (1.3)
    — **Done:** install blocks added to pack-markitdown/pack-docling (pip runtime, packages, idempotent probes, uninstall legacy, $install-notes bump ritual); merge-packs reserved-key strip — old-merger leak ($install-notes+install at :884-885) vs new-merger clean output proven; files: deploy/packs/pack-markitdown.json, deploy/packs/pack-docling.json, deploy/merge-packs.mjs; fixes: none
- [x] **1.2** Add generic `install_pack_runtime <name>` to `deploy/setup.sh` (reads the pack JSON via node, dispatches `pip` — user install, PEP 668 `--break-system-packages` retry, per-OS PATH check, idempotency probe from the `idempotent` block — or `npm`; `runtime: "none"`/absent block = no-op) reusing `resolve_python`
    — **Why:** one dispatcher replaces two per-pack shell functions; future runtimes are a new verb, not new functions
    — **Done when:** `install_pack_runtime markitdown` installs/skips identically to the old function on this machine (idempotent second run skips); `--dry-run` prints `[DRY-RUN] Would install pack runtime: <name>` and never spawns pip/npm
    — **Consumers affected:** call sites in 1.3; `test_dry_run_leaks.bats` (add case)
    — **Done:** generic install_pack_runtime added (pip user-install + PEP668 fallback + npm verb + idempotency probe + legacy uninstall); verified: dry-run prints only, config-only no-op, idempotent skip via pipShow=pip, unparseable/missing warn; files: deploy/setup.sh; fixes: case-pattern quoting (< is a metachar), trailing-> strip in KEY<val> parser
- [x] **1.3** Rewire both call sites: the inline `grep -qw markitdown → install_markitdown_mcp` block in `setup_config` and the install-on-enable block in `run_pack_merger` call `install_pack_runtime "$pack"` per requested pack
    — **Why:** call sites become pack-agnostic — adding a pack with an install block needs zero setup.sh edits
    — **Done when:** `grep -c install_pack_runtime deploy/setup.sh` ≥ 3; no remaining direct `install_markitdown_mcp|install_docling` call sites
    — **Consumers affected:** `tests/test_markitdown_skill.bats`, `tests/test_docling_skill.bats` (grep targets move)
    — **Done:** both call sites rewired to pack-agnostic loops (setup_config + run_pack_merger) with IFS=',' split + trim; files: deploy/setup.sh; fixes: junk drafting line removed, _pack_list localized
- [x] **1.4** Delete `install_markitdown_mcp` and `install_docling` from `deploy/setup.sh`
    — **Why:** dead code after 1.3; deletion over addition
    — **Done when:** `grep -n "install_markitdown_mcp\|install_docling" deploy/setup.sh` returns only `install_pack_runtime` references (none)
    — **Consumers affected:** `tests/deploy_delegate.bats` line-order pin (verify first-occurrence lines still parse — removed functions sat below the pinned region)
    — **Done:** install_markitdown_mcp + install_docling deleted (splice of lines 2942-3066); deploy_delegate structure pin re-verified green (deploy_content/deploy_agents order intact); files: deploy/setup.sh; fixes: none
- [x] **1.5** Update `test_markitdown_skill.bats` / `test_docling_skill.bats` install-function greps to `install_pack_runtime` + pack-JSON `install` block; update `test_help_parity.bats`'s `setup_sh_markitdown_bump_comment_names_only_pin_carriers` grep — the pinned comment (`the pin lives in deploy/setup.sh only`) lives inside the deleted `install_markitdown_mcp` block, so the bump-ritual comment moves to the pack JSON `$comment` and the test greps it there; extend `tests/test_pack_permissions.bats` with install-schema validation (`runtime` ∈ pip|npm|none, `packages` non-empty array when runtime ≠ none)
    — **Why:** tests must guard the new contract, not the deleted one; help_parity pins the bump-ritual comment by literal text
    — **Done when:** `bats tests/test_markitdown_skill.bats tests/test_docling_skill.bats tests/test_pack_permissions.bats tests/test_dry_run_leaks.bats tests/test_help_parity.bats` green
    — **Consumers affected:** none
    — **Done:** tests updated: pack_permissions (3 pins moved to pack JSON + 2 new tests: schema validation, merge-strip guard), help_parity (bump-ritual grep → pack JSON + setup.sh pin-absence), ps1_vars (pin greps → pack JSON), dry_run_leaks (+install_pack_runtime preview case); files: tests/test_pack_permissions.bats, tests/test_help_parity.bats, tests/test_setup_ps1_vars.bats, tests/test_dry_run_leaks.bats; fixes: undefined $CONFIG/$PACKS_DIR in pack_permissions test → literal paths

### Phase 2: Derived MCP listings ✅

- [x] **2.1** Add `mcp_state_listing` helper to `deploy/setup.sh` (one `node -e` read of the deployed `~/.config/opencode/opencode.json` `mcp.servers` — auto-start = `disabled:false` — plus packs-dir enumeration with required-key hints from pack `$comment`/`requires` field; falls back to `deploy/opencode.json` when no config deployed)
    — **Why:** one derivation point replaces four hand-maintained lists; the drift class this repo has re-fixed three times dies
    — **Done when:** helper prints auto-start + opt-in lists correctly against a fixture config; missing config file → falls back to source config, never errors
    — **Consumers affected:** the four surfaces in 2.2
    — **Done:** mcp_state_listing + mcp_state_lines + mcp_state_count + mcp_pack_names added (packs derive covered servers from their own mcp.servers keys — handles nextjs→next-devtools mapping); verified AUTO-START=3/PACKED=7/OPTIN=1(atlassian)/COUNT=11 + no-deployed-config fallback to source; files: deploy/setup.sh; fixes: none
- [x] **2.2** Replace the hand-written MCP blocks in `show_help`, `setup_config` echo, `print_summary`, and `print_next_steps` with `mcp_state_listing` output (keep the literal `MCP SERVERS:` header line — `test_mcp_count_consistency.bats` greps it)
    — **Why:** surfaces stop restating; a new pack appears in help/summary automatically
    — **Done when:** `grep -n "markitdown,docling\|alpha-vantage,nanobanana" deploy/setup.sh` finds zero hand-maintained enumerations outside comments; the four surfaces render the helper output
    — **Consumers affected:** `tests/test_help_parity.bats`, `tests/test_mcp_count_consistency.bats`
    — **Done:** all four surfaces rewired (show_help MCP SERVERS block, setup_config echo, print_summary, print_next_steps incl. dynamic MCP Servers (N) count + derived --enable-pack vocabulary); parse_arguments error + flag comment de-enumerated; files: deploy/setup.sh; fixes: worktree deploy/opencode.json had been silently mutated by an earlier in-place merge test AND swept into the phase-1 commit — reverted to origin/main here (fix-forward)
- [x] **2.3** Verify count tests: `bats tests/test_mcp_count_consistency.bats tests/test_help_parity.bats` green (no test edit expected — derivation satisfies the existing greps by construction)
    — **Why:** proves the drift class is closed without loosening guards
    — **Done when:** both files green
    — **Consumers affected:** none
    — **Done:** test_mcp_count_consistency + test_help_parity green with zero test edits — derivation satisfies the guards by construction; also re-ran dry_run_leaks + pack_permissions (no regression); files: none; fixes: none

### Phase 3: Plugin provisioning convention ✅

- [x] **3.1** Create `plugins/laya-guard/provision.sh` (body of `provision_laya_guard` moved verbatim: LAYA_GUARD_SKIP/Node≥24/npm gates, sidecar copy + npm install + `.provisioned` hash marker, warm pre-pull prompt/LAYA_GUARD_WARM; dry-run gate preserved via `[ "$DRY_RUN" = true ]` prints; sources nothing — reads env `DRY_RUN`, `AUTO_ACCEPT`, `REPO_DIR`, `LAYA_GUARD_*`)
    — **Why:** provisioning knowledge belongs to the self-contained plugin dir (#437 isolation contract), not the orchestrator
    — **Done when:** `bash plugins/laya-guard/provision.sh` from the worktree provisions `~/.cache/laya-guard` (or skips per gates) exactly as the old function did; `LAYA_GUARD_SKIP=1` exits 0 with note; `DRY_RUN=true` mutates nothing
    — **Consumers affected:** `deploy_plugins` (3.2), `tests/test_laya_guard.bats`
    — **Done:** plugins/laya-guard/provision.sh created — body moved verbatim into provision_main() with a self-contained header (own run_cmd/log_*/prompt_yes_no, DRY_RUN/AUTO_ACCEPT explicit-comparison, REPO_DIR auto-resolve from script location); verified: SKIP=1 escape, dry-run zero-mutation, real provision + npm install, idempotent marker re-run; files: plugins/laya-guard/provision.sh; fixes: standalone-script gaps (run_cmd missing, function-only return/local, missing trailing newline gluing the close brace)
- [x] **3.2** Extend `deploy_plugins` copy loop: after copying a plugin subdir, if `<plugin>/provision.sh` exists run `bash <src>/provision.sh` (non-fatal; inherits DRY_RUN/AUTO_ACCEPT env; one log line per hook run)
    — **Why:** generic `if [ -f ]` hook — second provisionable plugin needs zero setup.sh edits
    — **Done when:** a fresh-machine dry-run deploy prints the laya provision hook line; a plugin without `provision.sh` skips silently
    — **Consumers affected:** `tests/deploy_delegate.bats` (verify), `tests/test_dry_run_leaks.bats`
    — **Done:** deploy_plugins runs <plugin>/provision.sh when present after the copy loop — non-fatal, env pass-through; verified end-to-end via sandboxed deploy_plugins run (hook fired for laya-guard); files: deploy/setup.sh; fixes: none
- [x] **3.3** Delete `provision_laya_guard` from `deploy/setup.sh` and its `setup_config` call site; update `tests/test_laya_guard.bats` to exercise `plugins/laya-guard/provision.sh` directly (behavior asserts survive; location greps change)
    — **Why:** single home for the logic; tests point at the real artifact
    — **Done when:** `grep -c provision_laya_guard deploy/setup.sh` = 0; `bats tests/test_laya_guard.bats` green
    — **Consumers affected:** none
    — **Done:** provision_laya_guard (93 lines incl. comment block) + its setup_config call site deleted — 0 references left; test_laya_guard.bats +6 tests (parses, setup.sh-free, generic hook, dry-run no-mutation, SKIP escape, no process.env) — 14/14 green; files: deploy/setup.sh, tests/test_laya_guard.bats; fixes: none

### Phase 4: seed-provider-auth.mjs ✅

- [x] **4.1** Create `deploy/seed-provider-auth.mjs` (zero-dep node, ES module, camelCase args per merge-packs conventions): `resolve` subcommand (preset file + chosen provider → credential block JSON: auth_ids/env_var/oauth), `seed` subcommand (merge-never-clobber auth.json write for one auth_id — corrupt-file parking to `.corrupt.bak`, `0600` chmod, port of the python heredoc), `seed-codex` subcommand (guarded TOML append with both section-exists checks + endpoint-docs comment, port of `seed_codex_provider` heredoc)
    — **Why:** one node CLI owns all credential writes; python3 dependency for auth.json drops away
    — **Done when:** `node deploy/seed-provider-auth.mjs seed --auth-id zai --key test --file <tmp>` writes/merges correctly (pre-existing entries preserved, 0600, corrupt input parked); `resolve` against `installer/provider-presets.json` returns the zai block
    — **Consumers affected:** setup.sh rewiring (4.2), `tests/test_agent_detection_seed.bats`
    — **Done:** seed-provider-auth.mjs created (resolve/seed/seed-codex, zero-dep, merge-packs conventions); key travels via AUTH_KEY env (never argv); verified: resolve flag/derive/oauth paths, fresh+merge writes (zai preserved beside gemini), 0600 perms, corrupt parking to .corrupt.bak, codex append-once + both section guards; files: deploy/seed-provider-auth.mjs; fixes: stray ValueError → Error
- [x] **4.2** Rewire `setup.sh`: `register_provider_auth` → `node seed-provider-auth.mjs seed`; credential-block lookups in `setup_provider_credentials` → one `resolve` call (replaces four inline `node -e` snippets); `seed_pi_provider` stays on `seed-pi-provider.mjs`; `seed_codex_provider` → `seed-codex` subcommand
    — **Why:** shell keeps only capture/TTY/restart UX; merge/write logic has one home
    — **Done when:** dry-run deploy of the credentials step prints `[DRY-RUN]` lines and mutates no auth.json; a real seeded key verifies via `opencode auth list` path unchanged
    — **Consumers affected:** `tests/test_agent_detection_seed.bats`
    — **Done:** register_provider_auth → node seed; setup_provider_credentials → one resolve call (5 node -e snippets gone); seed_codex_provider → node seed-codex behind its shell guards; SEED_AUTH_SCRIPT global added; test_agent_detection_seed 12/12 green unchanged (functions remain the shell entry points); files: deploy/setup.sh; fixes: none
- [x] **4.3** Delete the python heredoc `register_provider_auth` body and the codex TOML heredoc from `deploy/setup.sh`
    — **Why:** dead code after 4.2
    — **Done when:** `grep -c "PYEOF\|model_providers.zai" deploy/setup.sh` = 0; `bats tests/test_agent_detection_seed.bats` green
    — **Consumers affected:** none
    — **Done:** python auth.json heredoc + codex TOML heredoc deleted — PYEOF count in setup.sh = 0, no model_providers.zai TOML in shell; pi seed already delegated (seed-pi-provider.mjs untouched); files: deploy/setup.sh; fixes: none

### Phase 5: TUI install wizard

- [ ] **5.1** Add `install-wizard` flow to `deploy/tui.mjs`: numbered-step singleSelect screen (mode / provider / MCP packs / skill profile / plugins / per-item / Review & Install) reusing `tui-primitives.mjs`; pack step lists `deploy/packs/*.json` names + `$comment`-derived descriptions + `install`-block runtime preview; review screen prints the exact planned actions (config deploy, pack list, pip/npm commands from install blocks, profile) then `confirm`; emits `install-plan.json` (`{mode, provider, packs, skillProfile, items}`) to `--out`; `q`/ctrl-c writes nothing; non-TTY → `{aborted, nonTty}` usage error per existing flow convention
    — **Why:** guided interactive session with an OpenCode-style review step; TUI-only-decides keeps one executor
    — **Done when:** `node deploy/tui.mjs install-wizard --print-plan --defaults` (headless escape hatch) emits valid plan JSON ≡ existing defaults; interactive run against a pty writes the plan file; cancel path writes nothing
    — **Consumers affected:** setup.sh `--from-plan` (5.2), `tests/test_install_wizard.bats`
- [ ] **5.2** Add `--from-plan <file>` to `deploy/setup.sh` `parse_arguments` + `build_plan`: mode → QUICK/SKILLS/UPDATE flags, `provider` → PROVIDER, `packs` → ENABLE_PACK (through existing `validate_enable_pack`), `skillProfile` → SKILL_PROFILE, `items` → SELECT_PLAN_FILE consumption path; then the normal plan executor runs untouched
    — **Why:** wizard and CLI converge on one execution surface — no TUI/CLI drift possible
    — **Done when:** `build_plan` output for `--from-plan <fixture>` is byte-identical to the equivalent explicit-flag invocation (test-pinned); unknown/invalid plan → named error exit 1 before any mutation
    — **Consumers affected:** `tests/parse_arguments.bats`, `tests/test_install_wizard.bats`
- [ ] **5.3** Interactive menu gains option `1) Guided setup (TUI)` (wizard launch); legacy 1–6 menu becomes the `--no-tui`/TUI-failure fallback (same degrade pattern as select-items dashboard → linear); headless default unchanged (skills-only, no TTY → never launches wizard)
    — **Why:** wizard is the front door when a TTY exists; every existing headless contract stays bit-identical
    — **Done when:** `bats tests/test_menu_multipick.bats tests/test_headless_default.bats` green unchanged; TTY menu shows the new option and `--no-tui` restores the legacy menu
    — **Consumers affected:** `tests/test_menu_multipick.bats` (new option case), README (P7)
- [ ] **5.4** Add `tests/test_install_wizard.bats`: plan JSON schema, `--from-plan` ≡ flags equivalence (wizard plan vs explicit flags → identical `build_plan`), non-TTY abort, cancel-writes-nothing, headless `--print-plan` path
    — **Why:** the equivalence pin is the drift guard for the whole TUI layer
    — **Done when:** `bats tests/test_install_wizard.bats` green; `bats tests/parse_arguments.bats` green
    — **Consumers affected:** none

### Phase 6: CivilTekk Skills Setup branding + shim rename

- [ ] **6.1** Rename deployed shims: `setup_opencode_setup_symlink` / `setup_opencode_init_symlink` install `civiltekk-setup` / `civiltekk-init` as primary AND refresh `opencode-setup` / `opencode-init` as compat symlinks to the same targets (idempotent refresh logic reused); PATH warnings mention the new names
    — **Why:** deployed API matches the project name without breaking existing scripts/muscle memory
    — **Done when:** after a dry-run preview, planned `ln -sf` lines name all four links; on a real run both names resolve to the same script via `readlink -f`
    — **Consumers affected:** README (P7), `tests/test_setup_symlinks.bats` (if present) / symlink assertions in deploy tests
- [ ] **6.2** Rebrand user-facing strings: TUI wizard header, setup.sh banners + mode-completion lines, `show_help` header block, `print_summary`/`print_next_steps` headers → "CivilTekk Skills Setup"; `deploy/setup.ps1` + `setup.cmd` help text rebranded; upstream-product references (`@opencode/cli`, `opencode --version`, `~/.config/opencode/`) stay verbatim; log filename `~/.opencode-setup.log` unchanged
    — **Why:** configurator identity ≠ upstream runtime; rename-sweep must cover the ps1/cmd launchers and root-adjacent surfaces, not just setup.sh
    — **Done when:** `grep -rn "OpenCode Configuration Setup\|OpenCode Skills Deployment" deploy/` = 0; `bats tests/test_help_parity.bats tests/test_setup_ps1_vars.bats` green (branding only — no new vars/pins in ps1)
    — **Consumers affected:** `tests/test_help_parity.bats` (expected-string updates)
- [ ] **6.3** Root-doc spelling sweep: README, `deploy/setup.ps1` comments, `installer/init.mjs` tips (`opencode-setup` → `civiltekk-setup`, `opencode-init` → `civiltekk-init` with one compat note)
    — **Why:** directory-scoped renames miss root docs that teach the spelling (repo learning)
    — **Done when:** `grep -rn "opencode-setup\|opencode-init" README.md deploy/ installer/ | grep -v "compat\|legacy"` returns only intentional compat mentions
    — **Consumers affected:** none

### Phase 7: README + install-assistant docs

- [ ] **7.1** Restructure README Installation: "pick your entry point" table — npx single skill, TUI wizard (`civiltekk-setup`), scripted full deploy, per-project presets (`civiltekk-init`), in-session assistants (`civiltekk-install-assistant`, `mcp-install-assistant-skill`, `opencode-repo-setup-skill` promoted from deep reference); compat-shim note for old names
    — **Why:** five real entry points exist after P5; the README is the front door and must not bury two of them
    — **Done when:** README renders the 5-row table; derived-count phrasing `ships N MCP server entries` preserved verbatim for `test_mcp_count_consistency.bats`
    — **Consumers affected:** `tests/test_mcp_count_consistency.bats`, `tests/test_count_drift.bats`
- [ ] **7.2** Add full-stack routing row to `skills/civiltekk-install-assistant/SKILL.md` route table ("set up the whole stack" → `civiltekk-setup` wizard/flags) and a deploy-time-pack pointer in `skills/mcp-install-assistant-skill/SKILL.md` (→ `--enable-pack` / wizard packs step); keep both skills self-contained (#437 — no new cross-skill references beyond the routing line)
    — **Why:** in-session assistants route full-stack asks instead of reimplementing them
    — **Done when:** route table shows the new row; `bats tests/test_skill_isolation.bats` green unchanged
    — **Consumers affected:** none
- [ ] **7.3** Full verification: `bats tests/` entire suite green; AC checklist re-ticked in PLAN + ticket
    — **Why:** the exit gate is full-tier by contract; suite-wide green is the merge precondition
    — **Done when:** full `bats tests/` exit 0; gate memo `tier=full` recorded
    — **Consumers affected:** PR (Step 10 citation)

## Trace

GATE bc5e069+phase1 tier=light lint=- typecheck=- build=- unit=t(e2e n.a) — 67/67 green across test_pack_permissions, test_help_parity, test_dry_run_leaks, deploy_delegate, test_setup_ps1_vars, test_markitdown_skill, test_docling_skill
LOG fix1: test_setup_ps1_vars pin grep moved to pack JSON (pin relocated by design)
LOG fix2: pack_permissions merge-strip test used undefined $CONFIG/$PACKS_DIR → literal deploy/opencode.json + deploy/packs

GATE phase2 tier=light lint=- typecheck=- build=- unit=t(e2e n.a) — test_mcp_count_consistency + test_help_parity green with ZERO test edits (derivation satisfies guards by construction); deploy/opencode.json restored to origin/main (phase-1 test artifact)

GATE phase3 tier=light lint=- typecheck=- build=- unit=t(e2e n.a) — test_laya_guard 14/14, dry_run_leaks + deploy_delegate no regression; deploy_plugins hook verified in sandbox

GATE phase4 tier=light lint=- typecheck=- build=- unit=t(e2e n.a) — test_agent_detection_seed 12/12 unchanged; dry_run_leaks/deploy_delegate/help_parity/ps1_vars no regressions; python3 dependency for auth.json dropped

## Technical Notes

- Test runner: `bats` (repo standard). `tests/deploy_delegate.bats` pins first-occurrence line order of delegate functions in setup.sh — all four deleted functions (`install_markitdown_mcp`, `install_docling`, `provision_laya_guard`, python heredoc) sit below/after pinned regions; verify per phase, never reorder pinned functions.
- `tests/test_dry_run_leaks.bats` greps for real mutations under `--dry-run`; new dry-run arms (`install_pack_runtime`, provision hook, wizard launcher) must print, not execute.
- `tests/test_setup_ps1_vars.bats` enforces setup.ps1 carries NO pins (thin launcher) — Phase 6 touches ps1 branding strings only.
- macOS bash 3.2 nounset: empty-array expansions guarded with `local var=""` accumulation (existing idiom, e.g. `deploy_selected_group`).
- merge-packs.mjs deep-merges only `mcp` + `permissions` fragments — the new `install` key needs no merger change; add a verify-only assertion instead of code.
- Wizard JSON emission: `--print-plan --defaults` headless path mirrors `select-items --print-plan --defaults` shape (test-pinned equivalence there — copy the pattern).
- `~/.opencode-setup.log` name unchanged (log continuity); shim renames are additive-only — both names always resolve.

## Dependencies

None — single ticket, no `blocked-by:`. Upstream history: #376 (restructure), #673 (multi-pick menu + OS-aware installs) are merged context, not blockers.

## Risks & Mitigation

| Risk | Mitigation |
|------|------------|
| bats content pins break on function deletion/moves | Per-phase `bats` on the pinned files (1.4, 3.3); never reorder pinned delegate functions |
| Dry-run contract regression (real pip/npm/provision under preview) | Dedicated `test_dry_run_leaks` cases per new arm (1.5, 3.2, 5.2) |
| TUI/CLI drift (wizard decisions ≠ flag semantics) | `--from-plan` ≡ flags equivalence test (5.4) — the wizard never executes |
| Rename breaks external scripts using `opencode-setup` | Compat shims kept indefinitely; grep sweep distinguishes intentional compat mentions (6.3) |
| merge-packs silently consuming/mangling the new `install` key | **Confirmed real** (arch review: `merge-packs.mjs:182-183` deep-merges unknown keys) — 1.1 strips `install` in the reserved-key destructure + byte-identical merge assertion |
| Credential seeding regression loses stored keys | `seed` subcommand merge-never-clobber port is test-first (4.1 tmp-file round-trip incl. corrupt-file parking) |
