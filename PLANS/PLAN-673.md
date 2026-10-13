# PLAN: Multi-pick setup menu and OS-aware pack installs

**Branch**: feat/673
**Issue**: https://github.com/darellchua2/civiltekk-skills/issues/673
**Base**: origin/main

## Acceptance Criteria

- [ ] Menu accepts `2,6` / `3,5,6` / `4`; exactly one base + add-ons; `2,4`, `1,2`, unknown tokens rejected with a re-prompt
- [ ] `--skills-only --select` / `--quick --select` deploy the selected set (validated, not silently ignored)
- [ ] PeonPing attaches as a non-critical step to any base mode
- [ ] `resolve_python()` rejects a broken `python3` stub and falls through to `python`/`py -3`; both installers use `$PYTHON_BIN`
- [ ] Post-install PATH check resolves the per-OS scripts dir and warns with the exact directory (never mutates PATH)
- [ ] Preflight banner prints OS, invocation route, node + python versions
- [ ] `deploy/setup.cmd` runs the full setup from cmd.exe
- [ ] `setup.ps1 -EnablePack markitdown,docling` works on node < 26.4; `-Select` still enforces ≥ 26.4 (linear fallback otherwise)
- [ ] Stale `markitdown-local-mcp` dry-run block removed; `tests/test_setup_ps1_vars.bats` stays green
- [ ] README catalog table renders as one table; node floor aligned across README/setup.sh/setup.ps1; lean count no longer hardcoded; ticketing README points at the betekk catalog
- [ ] New bats tests: multi-pick parsing, `resolve_python` stub rejection, scripts-dir branches

## Dependency & Consumer Map

| Node (file/module) | Depends on (must precede) | Consumers (who depends on this) | Change risk |
|---------------------|---------------------------|---------------------------------|-------------|
| `deploy/setup.sh` menu/plan core (`parse_menu_selection`, `validate_mode_conflicts`, `build_plan`) | — | `deploy/setup.ps1` (forwards flags verbatim), `tests/*.bats`, README flag table | high |
| `deploy/setup.sh` installers (`install_markitdown_mcp`, `install_docling`) | `resolve_python()` (2.1) | markitdown/docling MCP servers spawned by opencode at runtime | high |
| `deploy/setup.sh` `detect_runtime_context()` | `resolve_python()` (2.1) | interactive users (preflight banner) | low |
| `deploy/setup.ps1` (gate scope, `OPENCODE_SETUP_VIA_PS1`) | `deploy/setup.sh` unchanged flag contract | Windows users, `deploy/setup.cmd`, `tests/test_setup_ps1_vars.bats` | med |
| `deploy/setup.cmd` (new) | `deploy/setup.ps1` | cmd.exe users, README quick-start | low |
| `tests/test_menu_multipick.bats`, `tests/test_resolve_python.bats` (new) | the setup.sh functions they exercise | bats suite / CI | med |
| `README.md` | shipped behavior of setup.sh/setup.ps1/setup.cmd | users, catalog readers | low |
| `deploy/.AGENTS.md` | — | deployed to `~/.config/opencode/AGENTS.md` by `setup_config` | low |
| `skills/ticketing-skill/README.md` | — | skill readers | low |

## Implementation Phases

### Phase 1: Menu multi-pick

- [ ] **1.1** Add `parse_menu_selection()` to `deploy/setup.sh` — split the pick line on commas/whitespace, require exactly one base (1|2|3, or standalone 4), accept add-ons 5/6 in any order, reject unknown tokens or a second base with a named error
    — **Why:** the menu is single-select, so base+add-on combos (e.g. skills-only + item picker) are impossible today; parsing is the shared entry for menu and validation.
    — **Done when:** new bats cases pass for `2,6` / `3,5,6` / `4` / blank-default-2 and reject `2,4` / `1,2` / `9`.
    — **Consumers affected:** `main()` menu branch (1.2), `validate_mode_conflicts` (1.3).
- [ ] **1.2** Rewire the interactive menu prompt in `main()` to loop on `parse_menu_selection()` and set `QUICK_SETUP`/`SKILLS_ONLY`/`SELECT_ITEMS`/`PEONPING_ADDON` accordingly (blank → default 2)
    — **Why:** this is the only surface where multi-pick is entered; flags stay the single source the plan model consumes.
    — **Done when:** sourcing setup.sh and invoking the parser-driven flag setter with `2,6` yields `SKILLS_ONLY=true` + `SELECT_ITEMS=true` (bats via function-level test).
    — **Consumers affected:** `run_plan` (via 1.4).
- [ ] **1.3** Relax `validate_mode_conflicts` with a compatible-pairs whitelist — `{quick, skills-only, full} × {select-items, peonping}` allowed; every other pair (update/rollback/models-only/migrate/check-*/list-items/save-preset with anything) stays exclusive
    — **Why:** keeps the #466 contract honest — new combos are validated first-class instead of silently ignored, while genuinely exclusive modes stay rejected.
    — **Done when:** bats asserts `--skills-only --select` and `--quick --peonping` pass validation and `--update --select` still exits 1.
    — **Consumers affected:** every scripted invocation (flags and menu share this gate).
- [ ] **1.4** Extend `build_plan`: when `SELECT_ITEMS` accompanies quick/skills-only, inject the select-branch steps (provision-tui → select-items → deploy-selected-skills/agents → prune → apply-selected-extras) in place of the blanket `agents` step; when `PEONPING_ADDON`, append `setup_peonping` as a non-critical step to any base
    — **Why:** the plan executor consumes only `PLAN_STEPS` — without injection the picker never runs outside full mode.
    — **Done when:** bats asserts the `2,6` plan contains `deploy_selected_skills` and no standalone `deploy_agents` step, and `1,5` contains `setup_peonping`.
    — **Consumers affected:** `run_plan`, epilogue summary (base PLAN_MODE unchanged).
- [ ] **1.5** Add `tests/test_menu_multipick.bats` covering 1.1–1.4 (function-level: source setup.sh with guarded main, sandboxed flags)
    — **Why:** the verification gate needs runnable checks per phase; parsing/validation are pure functions and cheap to test.
    — **Done when:** `bats tests/test_menu_multipick.bats` green.
    — **Consumers affected:** CI, Step 9 review.

### Phase 2: OS-aware python resolution and installers

- [ ] **2.1** Add `resolve_python()` — probe `python3` → `python` → `py -3`, accepting a candidate only when `$cand -c 'import sys; sys.exit(0 if sys.version_info >= (3,8) else 1)'` exits 0; export `PYTHON_BIN`; on total miss print a per-OS hint (Windows: Store-alias trap + python.org; Unix: python3 package)
    — **Why:** the MS Store `python3` stub passes `command_exists` but fails `python3 -m pip`, so both pack installs silently skip on Windows; a functional probe is the only honest signal.
    — **Done when:** bats with a PATH-sandboxed fake bin dir resolves `python` over a broken `python3` stub, and an empty PATH yields empty `PYTHON_BIN`.
    — **Consumers affected:** `install_markitdown_mcp`, `install_docling` (2.2), `detect_runtime_context` (3.3).
- [ ] **2.2** Switch `install_markitdown_mcp` and `install_docling` to `"$PYTHON_BIN" -m pip` (call `resolve_python` first; bail non-fatal with the hint when empty) and delete the stale `markitdown-local-mcp`/`${launcher_dir}` dry-run block (`deploy/setup.sh:2834`)
    — **Why:** Windows-native installs; the dead block references a removed vendored package and an undefined variable that would abort under `set -u` if ever reached.
    — **Done when:** `grep -n 'python3 -m pip' deploy/setup.sh` returns nothing inside the two installers and the `markitdown-local-mcp` string is gone; dry-run arm still prints its preview line.
    — **Consumers affected:** `--enable-pack markitdown` / `docling` installs; `run_pack_merger`'s re-install call.
- [ ] **2.3** Add `check_user_scripts_path()` — Windows: `"$PYTHON_BIN" -m site --user-base` + `/Scripts`; Unix: `~/.local/bin`; warn-only with the exact directory; replace the `~/.local/bin`-only PATH check inside `install_markitdown_mcp`
    — **Why:** `pip --user` console scripts land in `%APPDATA%\Python\PythonXY\Scripts` on Windows — off-PATH by default — so the enabled servers fail to spawn; the current warning checks the wrong dir.
    — **Done when:** on this platform the function echoes the scripts dir from `site --user-base` (win) or `~/.local/bin` (unix) and never mutates PATH (bats asserts output + absence of `setx`/export PATH writes).
    — **Consumers affected:** post-install UX for both packs.
- [ ] **2.4** Add `tests/test_resolve_python.bats` (stub rejection, fallthrough order, empty-PATH hint) plus scripts-dir branch cases
    — **Why:** gates for Phase 2; probe order is regression-prone.
    — **Done when:** `bats tests/test_resolve_python.bats` green.
    — **Consumers affected:** CI, Step 9 review.

### Phase 3: Entry points and preflight context

- [ ] **3.1** Add `deploy/setup.cmd` (~5 lines): forward `%*` to `powershell -ExecutionPolicy Bypass -File "%~dp0setup.ps1" %*`
    — **Why:** cmd.exe cannot run bash or ps1 directly by default; the shim makes cmd a first-class entry (cmd → ps1 → bash).
    — **Done when:** `cmd //c deploy\\setup.cmd -Help` prints setup help from Git Bash on Windows (test guarded to skip when `cmd.exe` is absent, e.g. Linux CI).
    — **Consumers affected:** README quick-start (4.1).
- [ ] **3.2** Scope `setup.ps1`'s node ≥ 26.4 gate to the `-Select` branch (keep a node-presence check global; dashboard's own linear fallback at `deploy/tui.mjs:121` covers below-26.4), and export `OPENCODE_SETUP_VIA_PS1=1` before invoking bash
    — **Why:** the 26.4 floor is the picker dashboard's requirement, not setup's — the blanket gate blocks non-picker runs on node 20-24 contrary to README; the env marker drives the preflight banner's invocation-route line.
    — **Done when:** `bats tests/test_setup_ps1_vars.bats` stays green plus a new assertion that the 26.4 comparison sits inside the `-Select` branch; a manual `-EnablePack markitdown -Help` path passes the bootstrap on node 24.
    — **Consumers affected:** every `setup.ps1` invocation; `deploy/setup.cmd` (3.1).
- [ ] **3.3** Add `detect_runtime_context()` as a non-critical plan step (full/quick/skills-only modes, first step): print `DETECTED_OS`, invocation route (`OPENCODE_SETUP_VIA_PS1` → "ps1-forwarded" else "bash-direct"), `node --version`, resolved `PYTHON_BIN` + version
    — **Why:** users (and support triage) should see what the installer detected before it acts; this machine's python3-stub trap was invisible in the output.
    — **Done when:** `./deploy/setup.sh --quick --dry-run` prints the context block with node and python versions filled.
    — **Consumers affected:** banner output only (read-only step).

### Phase 4: Docs alignment

- [ ] **4.1** Fix `README.md`: remove the blank line after the OpenTofu catalog row (line 300) so the Skill table renders whole; Prerequisites node line → "Node.js v20+ (`--select` dashboard wants ≥ 26.4, else linear prompts)"; quick-start adds the cmd.exe one-liner (`deploy\setup.cmd`); packs table Requires notes "python3 on PATH (resolved to python/py on Windows)"; setup section documents the multi-pick menu syntax (`2,6`) and the newly valid flag combos (`--skills-only --select`, base+peonping)
    — **Why:** the blank line breaks the markdown table mid-catalog (rows Git/Workflow → Media render headerless); the node line contradicted setup.ps1's old blanket gate; the new surfaces need documenting — a shipped interaction with no doc line repeats the documented-cli-behavior drift class.
    — **Done when:** no blank line between catalog rows 299-301; the five doc claims match shipped behavior (grep-verified).
    — **Consumers affected:** README readers, catalog renderers.
- [ ] **4.2** De-hardcode the lean count: replace the "70 primary-visible skills" figure at `deploy/setup.sh:3401` (and any other numeric lean claims surfaced by grep) with "primary-visible subset + deny-all"; align `deploy/.AGENTS.md`'s lean wording the same way
    — **Why:** the count drifted (ground truth `deploy/skill-profiles.json` = 68); prose restating a generated number is a standing drift bug.
    — **Done when:** `grep -rn "70 primary\|70 skills" deploy/` returns nothing; README's accurate "68" prose untouched.
    — **Consumers affected:** deployed AGENTS.md, setup help text.
- [ ] **4.3** Fix `skills/ticketing-skill/README.md:52` — point `dev-uat-promotion-skill` at the betekk catalog (`npx github:betekk/betekk-skills add dev-uat-promotion-skill`)
    — **Why:** the skill left this catalog in #667; the local pointer is stale.
    — **Done when:** the README row names the betekk source.
    — **Consumers affected:** ticketing-skill readers.

## Technical Notes

- Menu multi-pick is a menu+flag-level feature; `--dry-run`, headless no-TTY defaults, and the epilogue summary are untouched (base PLAN_MODE drives them as before).
- `resolve_python` must not "fix" PATH by mutation — warn-only everywhere (setx PATH truncation risk).
- `tui.mjs` needs no change: its `canDashboard` gate (node ≥ 26.4) already self-falls-back to linear prompts.
- Keep `python3` in non-installer contexts (docs prose about Unix) untouched — only the two installers and the banner consume `PYTHON_BIN`.

## Dependencies

- None (no `blocked-by:`). Single ticket, single lane.

## Risks & Mitigation

- **Menu parse ambiguity** (e.g. `2 6` vs `2,6`): accept both separators; tests pin the accepted shapes.
- **Whitelist loosens #466 too far**: the whitelist covers exactly two add-ons; every previously-exclusive pair still exits 1 — pinned by bats.
- **`py -3` probe on Git Bash**: `py` is a `.exe` launcher; probe via `py -3 -c` which resolves through PATH on Windows; absent on Unix → skipped naturally by probe order.
- **ps1 gate move breaks `test_setup_ps1_vars.bats` pins**: run that suite per phase (3.2) and adjust only assertions that name the gate's location, never the pin-absence contract.
