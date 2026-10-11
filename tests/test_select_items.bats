#!/usr/bin/env bats

# Per-item deploy picker pins (#473): one pure module (deploy-plan-items)
# behind three drivers with identical plan output; DAG auto-include with
# provenance; setup wiring (provisioning, consume-once, per-mode matrix).
# "Pure" = no writes/network; caller-passed-dir readdir (scanPackNames /
# scanPluginNames) is the module's single documented I/O exception (#537).

SETUP_SH="deploy/setup.sh"
SETUP_PS1="deploy/setup.ps1"
REGEN_MODULE="installer/deploy-plan-items.mjs"

@test "opentui_core_pinned_exact_with_lockfile" {
  grep -q '"@opentui/core": "0.5.11"' package.json
  grep -q '"@opentui/core": ' package-lock.json
}

@test "nvm_bumped_to_26_in_both_scripts_no_stale_24" {
  grep -q 'nvm install 26' "$SETUP_SH"
  grep -q 'nvm install 26' "$SETUP_PS1"
  run grep -q 'nvm install 24' "$SETUP_SH"
  [ "$status" -ne 0 ]
  run grep -q 'nvm install 24' "$SETUP_PS1"
  [ "$status" -ne 0 ]
  run grep -q 'v24 via nvm' "$SETUP_PS1"
  [ "$status" -ne 0 ]
}

@test "plan_items_auto_includes_agent_requires_skills_with_provenance" {
  # architecture-review-subagent requiresSkills: reviewer-baseline-skill (registry)
  node -e '
    import("./installer/deploy-plan-items.mjs").then(async (m) => {
      const { resolveSelection } = await import("./installer/init.mjs");
      const registry = JSON.parse(require("fs").readFileSync("installer/registry.json", "utf8"));
      const depMap = JSON.parse(require("fs").readFileSync("installer/dependency-map.json", "utf8"));
      const agent = registry.agents.find((a) => (a.requiresSkills || []).length > 0);
      if (!agent) { console.log("no requiresSkills agent in registry — pin vacuous"); return; }
      const plan = m.buildSelectionPlan({ choices: { agents: [agent.stem] }, registry, depMap });
      const pulled = plan.skills.find((s) => s.name === agent.requiresSkills[0]);
      if (!pulled) throw new Error(agent.requiresSkills[0] + " not auto-included");
      if (!pulled.source.startsWith("locked-by:")) throw new Error("no locked-by provenance on " + pulled.name);
      const directAgent = plan.agents.find((a) => a.name === agent.stem);
      if (directAgent.source !== "direct") throw new Error("direct agent misannotated");
    });
  '
}

@test "provenance_credits_true_source_with_two_direct_choices" {
  # Two agents with disjoint requiresSkills — each pulled skill must credit
  # ITS OWN agent, not the first solo closure (round-1 WARN 1).
  node -e '
    import("./installer/deploy-plan-items.mjs").then(async (m) => {
      const registry = JSON.parse(require("fs").readFileSync("installer/registry.json", "utf8"));
      const depMap = JSON.parse(require("fs").readFileSync("installer/dependency-map.json", "utf8"));
      const withDeps = registry.agents.filter((a) => (a.requiresSkills || []).length > 0);
      if (withDeps.length < 2) { console.log("fewer than 2 requiresSkills agents — pin vacuous"); return; }
      const [a1, a2] = withDeps;
      const plan = m.buildSelectionPlan({ choices: { agents: [a1.stem, a2.stem] }, registry, depMap });
      const byName = Object.fromEntries(plan.skills.map((s) => [s.name, s]));
      for (const a of [a1, a2]) {
        const dep = byName[a.requiresSkills[0]];
        if (!dep) throw new Error(a.requiresSkills[0] + " missing from the plan");
        if (!String(dep.source).includes(a.stem)) throw new Error(dep.name + " credited to " + dep.source + ", expected " + a.stem);
      }
    });
  '
}

@test "print_plan_is_deterministic" {
  run node deploy/tui.mjs select-items --print-plan --skills civiltekk-git-commits-skill --agents code-review-subagent
  [ "$status" -eq 0 ]
  local first="$output"
  run node deploy/tui.mjs select-items --print-plan --skills civiltekk-git-commits-skill --agents code-review-subagent
  [ "$output" = "$first" ]
}

@test "print_plan_auto_includes_locked_dependency" {
  run node deploy/tui.mjs select-items --print-plan --agents code-review-subagent
  [ "$status" -eq 0 ]
  [[ "$output" == *"reviewer-baseline-skill"* ]]
  [[ "$output" == *"locked-by:"* ]]
}

@test "print_plan_runs_headless_zero_tty" {
  run bash -c "node deploy/tui.mjs select-items --print-plan --skills civiltekk-git-commits-skill" </dev/null
  [ "$status" -eq 0 ]
}

@test "linear_empty_selection_matches_empty_print_plan" {
  run bash -c "printf 's\\ns\\ns\\ns\\ns\\n' | node deploy/tui.mjs select-items --driver linear 2>/dev/null | node -e 'let d=\"\"; process.stdin.on(\"data\",(c)=>d+=c).on(\"end\",()=>{const p=JSON.parse(d); console.log(JSON.stringify([p.skills.length,p.agents.length,p.packs.length]))})'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[0,0,0]"* ]]
  run node deploy/tui.mjs select-items --print-plan
  local empty
  empty=$(echo "$output" | node -e 'let d=""; process.stdin.on("data",(c)=>d+=c).on("end",()=>{const p=JSON.parse(d); console.log(JSON.stringify([p.skills.length,p.agents.length,p.packs.length]))})')
  [[ "$empty" == *"[0,0,0]"* ]]
}

@test "setup_select_mode_wiring_and_consumption_gates" {
  grep -q -- '--select)' "$SETUP_SH"
  grep -q 'SELECT_ITEMS" = true' "$SETUP_SH"
  grep -q 'provision_picker_deps()' "$SETUP_SH"
  grep -q 'npm ci --omit=dev' "$SETUP_SH"
  # consume-once: unlink only outside dry-run
  grep -q 'rm -f "$SELECT_PLAN_FILE"' "$SETUP_SH"
  grep -q '"$DRY_RUN" != true ]; then' "$SETUP_SH"
}

@test "select_conflicts_with_skills_only_at_the_validator" {
  # --select registers in validate_mode_conflicts (#473 round 1 WARN): the
  # combination must DIE at plan validation, not silently run skills-only
  # without the picker.
  local d; d="$(mktemp -d)"
  run bash -c 'export HOME="$1"; source "'"$SETUP_SH"'" >/dev/null 2>&1; SKILLS_ONLY=true; SELECT_ITEMS=true; build_plan' _ "$d"
  rm -rf "$d"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Mutually exclusive"* ]]
}

@test "select_dry_run_with_preseeded_plan_writes_nothing" {
  # The PLAN-promised leak net (#467 family): select + dry-run with a
  # pre-seeded plan PREVIEWS consumption and installs nothing into the live
  # config. Teeth: WITHOUT the --dry-run forwarding in deploy_selected_group,
  # init.mjs installs for real and exits 0 — this test FAILS (the round-1
  # BLOCK regression cannot re-land silently).
  local d; d="$(mktemp -d)"
  mkdir -p "$d/.config/opencode"
  printf '%s' '{"skills":[{"name":"civiltekk-git-commits-skill","source":"direct"}],"agents":[],"mcps":[],"packs":[],"plugins":[],"extras":[],"warnings":[]}' > "$d/.config/opencode/deploy-plan.json"
  run bash -c "export HOME='$d'; unset XDG_DATA_HOME XDG_CONFIG_HOME; source '$SETUP_SH' >/dev/null 2>&1
           SELECT_ITEMS=true; DRY_RUN=true; AUTO_ACCEPT=true
           command_exists(){ return 0; }; check_network(){ return 0; }; check_dependencies(){ return 0; }
           main --dry-run -y --select" </dev/null
  [ "$status" -eq 0 ]
  # The untouched-surface assertions (the actual teeth):
  [ ! -e "$d/.config/opencode/skills/civiltekk-git-commits-skill" ]
  [ ! -e "$d/.config/opencode/agents" ]
  # Consume-once: dry-run never unlinks the plan.
  [ -f "$d/.config/opencode/deploy-plan.json" ]
  rm -rf "$d"
}

@test "select_mode_plan_has_picker_steps_and_no_blanket_agents" {
  local d; d="$(mktemp -d)"
  run bash -c "export HOME='$d'; source '$SETUP_SH' >/dev/null 2>&1; SELECT_ITEMS=true; build_plan; printf '%s\n' \"\${PLAN_STEPS[@]}\""
  rm -rf "$d"
  echo "$output" | grep -q 'select-items'
  echo "$output" | grep -q 'deploy-selected-skills'
  echo "$output" | grep -q 'deploy-selected-agents'
  echo "$output" | grep -q 'provision-tui'
}

@test "mcp_to_pack_map_covers_dependency_map_implies_mcp" {
  # Derived-coverage pin (round-2 review): every impliesMcp value in
  # dependency-map.json must map to a pack, or the plan advertises an MCP
  # nothing enables.
  node -e '
    Promise.all([import("./installer/deploy-plan-items.mjs")]).then(([m]) => {
      const fs = require("fs");
      const depMap = JSON.parse(fs.readFileSync("installer/dependency-map.json", "utf8"));
      const implied = new Set();
      for (const list of Object.values(depMap.impliesMcp || {})) for (const mc of list) implied.add(mc);
      const unmapped = [...implied].filter((mc) => !m.MCP_TO_PACK[mc]);
      if (unmapped.length) throw new Error("implied MCPs with no MCP_TO_PACK mapping: " + unmapped.join(", "));
      const packNames = new Set(fs.readdirSync("deploy/packs").map((f) => f.match(/^pack-(.+)\.json$/)?.[1]).filter(Boolean));
      const unknownPacks = Object.values(m.MCP_TO_PACK).filter((pk) => !packNames.has(pk));
      if (unknownPacks.length) throw new Error("MCP_TO_PACK maps to nonexistent packs: " + unknownPacks.join(", "));
    });
  '
}

# ───────────────────────── #537 pins ─────────────────────────

@test "plugin_inventory_and_defaults_agree_on_loadable_ts_plugins" {
  # #537: the README doc must never be selectable, and the interactive
  # inventory must agree with the --defaults filter (single scanPluginNames
  # source — the old code drifted 6-vs-5 between the two paths).
  node -e '
    import("./installer/deploy-plan-items.mjs").then((m) => {
      const names = m.scanPluginNames("plugins");
      if (names.length !== 7) throw new Error("expected 7 .ts plugins, got " + names.length); // 7th = opencode-laya-guard.ts (#671)
      for (const n of names) if (!n.endsWith(".ts")) throw new Error("non-.ts selectable: " + n);
      if (names.some((n) => n.includes("README"))) throw new Error("README offered as a plugin");
    });
  '
  run node deploy/tui.mjs select-items --print-plan --defaults
  [ "$status" -eq 0 ]
  local count
  count=$(echo "$output" | node -e 'let d="";process.stdin.on("data",(c)=>d+=c).on("end",()=>{const p=JSON.parse(d);if(p.plugins.some((x)=>x.includes("README")))process.exit(3);console.log(p.plugins.length)})')
  [ "$count" = "7" ]
  [[ "$output" == *"opencode-ponytail-scoped.ts"* ]]
  [[ "$output" != *"README"* ]]
}

@test "list_items_dump_lists_real_packs_and_plugins" {
  # #537 headline gap: dump_catalog previously hardcoded empty packs/plugins
  # arrays — the catalog told users plugins were not installable. Sandboxed
  # HOME: end-to-end setup.sh runs touch ~/.opencode-setup.log via
  # init_logging — never the developer's real home
  # (unsandboxed-bats-run-deploys-into-real-home).
  local d; d="$(mktemp -d)"
  run bash -c "export HOME='$d'; ./deploy/setup.sh --list-items 2>/dev/null | sed -n '/^{/,/^}/p'" </dev/null
  [ "$status" -eq 0 ]
  local counts
  counts=$(echo "$output" | node -e 'let d="";process.stdin.on("data",(c)=>d+=c).on("end",()=>{const p=JSON.parse(d);if(!p.packs.includes("docling")||p.packs.some((x)=>x.includes("README")))process.exit(3);console.log(p.packs.length+"/"+p.plugins.length)})')
  [[ "$counts" == "7/7" ]] # 7 packs / 7 plugins (7th = laya-guard, #671)
  # cwd-independence (arch review WARN): node -e import() resolves relative
  # specifiers against process cwd — the module path must be argv-absolute.
  run bash -c "export HOME='$d'; cd /tmp && '$PWD/deploy/setup.sh' --list-items 2>/dev/null | grep -c '\"docling\"'" </dev/null
  [[ "$output" == "1" ]]
  rm -rf "$d"
}

@test "plugin_selection_deploys_companions_from_dependency_map" {
  # #537: picking the ponytail wrapper alone must land its companions — the
  # plugin is inert without ponytail/instructions.cjs — and vibeguard must
  # keep arming its config. Sources: dependency-map.json pluginCompanions.
  local d; d="$(mktemp -d)"
  printf '%s' '{"skills":[],"agents":[],"mcps":[],"packs":[],"plugins":["opencode-ponytail-scoped.ts"],"extras":[],"warnings":[]}' > "$d/plan-ponytail.json"
  run bash -c "source '$SETUP_SH' >/dev/null 2>&1
           CONFIG_DIR='$d/config'; SELECT_PLAN_FILE='$d/plan-ponytail.json'
           apply_selected_packs_extras >/dev/null 2>&1
           apply_selected_packs_extras >/dev/null 2>&1
           find '$d/config/plugins' -mindepth 1 2>/dev/null | sort" </dev/null
  [ "$status" -eq 0 ]
  [[ "$output" == *"opencode-ponytail-scoped.ts"* ]]
  [[ "$output" == *"ponytail/SKILL.md"* ]]
  [[ "$output" == *"ponytail/instructions.cjs"* ]]
  [[ "$output" == *"ATTRIBUTION.md"* ]]
  # Idempotency pin needs its TWO invocations (re-run-pin-single-invocation-
  # vacuous): without rm-first, the second apply nests plugins/ponytail/ponytail
  # and this count becomes 1.
  local nested
  nested=$(find "$d/config/plugins/ponytail" -mindepth 1 -type d | wc -l | tr -d ' ')
  [ "$nested" = "0" ]
  printf '%s' '{"skills":[],"agents":[],"mcps":[],"packs":[],"plugins":["opencode-vibeguard-v2.ts"],"extras":[],"warnings":[]}' > "$d/plan-vibeguard.json"
  run bash -c "source '$SETUP_SH' >/dev/null 2>&1
           CONFIG_DIR='$d/config2'; SELECT_PLAN_FILE='$d/plan-vibeguard.json'
           apply_selected_packs_extras >/dev/null 2>&1
           find '$d/config2/plugins' -mindepth 1 2>/dev/null | sort" </dev/null
  [[ "$output" == *"opencode-vibeguard-v2.ts"* ]]
  [[ "$output" == *"vibeguard.config.json"* ]]
  rm -rf "$d"
}

@test "plugin_companions_cover_ships_plugins_facts" {
  # Cross-surface pin (arch review Major): pluginCompanions is the ONE
  # declarative companion home — checked PER shipsPlugins edge (each edge's
  # artifacts ⊆ that edge's plugin's companions), so a future second
  # plugin-bearing edge is judged against its own key, not ponytail's.
  node -e '
    const m = JSON.parse(require("fs").readFileSync("installer/dependency-map.json", "utf8"));
    const pc = m.pluginCompanions || {};
    const edges = Object.entries(m.shipsPlugins || {});
    if (!edges.length) throw new Error("shipsPlugins empty - cross-surface pin vacuous");
    for (const [skill, arts] of edges) {
      const plugin = arts.find((a) => a.endsWith(".ts"));
      if (!plugin) throw new Error("shipsPlugins edge without a .ts plugin: " + skill);
      const comps = pc[plugin];
      if (!comps) throw new Error("pluginCompanions missing key " + plugin + " (edge " + skill + ")");
      for (const a of arts) {
        if (a === plugin) continue;
        if (!comps.includes(a)) throw new Error("pluginCompanions[" + plugin + "] missing " + a + " (edge " + skill + ")");
      }
    }
    if (!(pc["opencode-vibeguard-v2.ts"] || []).includes("vibeguard.config.json")) {
      throw new Error("vibeguard.config.json missing from pluginCompanions");
    }
  '
}

@test "apply_selected_packs_extras_hardcodes_no_plugin_names" {
  # The bash-case fork the arch review rejected: companion knowledge lives in
  # dependency-map.json, never in shell arms.
  local body
  body=$(sed -n "/^apply_selected_packs_extras()/,/^}/p" "$SETUP_SH")
  [[ "$body" != *"opencode-vibeguard"* ]]
  [[ "$body" != *"opencode-ponytail"* ]]
  [[ "$body" == *"pluginCompanions"* ]]
}

@test "menu_option_six_routes_to_picker_path" {
  # #537 discoverability: the interactive menu gains the picker. Direct
  # invocation harness (source → flag → build_plan) because a pty run of the
  # full path hangs on its interactive prompts — the fallback the arch
  # review pre-authorized. Option 6's only logic is the flag assignment.
  grep -q '6) Select items to deploy' "$SETUP_SH"
  local arm
  arm=$(sed -n '/^[[:space:]]*6)$/,/;;/p' "$SETUP_SH")
  [[ "$arm" == *"SELECT_ITEMS=true"* ]]
  local d; d="$(mktemp -d)"
  run bash -c "export HOME='$d'; source '$SETUP_SH' >/dev/null 2>&1; SELECT_ITEMS=true; build_plan; printf '%s\n' \"\${PLAN_STEPS[@]}\" > '$d/steps.txt'"
  grep -q 'select-items|Select items to deploy' "$d/steps.txt"
  grep -q 'deploy-selected-skills' "$d/steps.txt"
  # Negatives as run+status checks — standalone `! cmd` lines are errexit-
  # exempt and cannot fail a bats test (negated-assertions-errexit-exempt).
  run grep -q '|Deploy agents|' "$d/steps.txt"
  [ "$status" -eq 1 ]
  run grep -q '|Deploy plugins|' "$d/steps.txt"
  [ "$status" -eq 1 ]
  rm -rf "$d"
}
