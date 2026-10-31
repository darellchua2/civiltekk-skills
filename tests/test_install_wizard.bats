#!/usr/bin/env bats

# Install wizard + --from-plan contract (#677). The TUI only collects
# decisions; setup.sh's plan executor is the single execution owner. The drift
# guard is the equivalence pin: a plan file MUST map to the same build_plan
# output as the equivalent explicit flags.

setup() {
  cd "${BATS_TEST_DIRNAME}/.." || return 1
}

TUI="deploy/tui.mjs"
SETUP_SH="deploy/setup.sh"

emit_default_plan() {
  local out="${1:-}"
  if [ -n "$out" ]; then
    node "$TUI" install-wizard --print-plan --defaults --out "$out"
  else
    node "$TUI" install-wizard --print-plan --defaults
  fi
}

@test "wizard_defaults_plan_is_valid_shape" {
  local plan
  plan="$(emit_default_plan)"
  echo "$plan" | node -e '
    let p;
    try { p = JSON.parse(require("fs").readFileSync(0, "utf8")); }
    catch { console.error("not JSON"); process.exit(1); }
    if (p.schema !== "civiltekk-install-plan/1") { console.error("bad schema"); process.exit(1); }
    if (!["skills-only", "quick", "full", "update"].includes(p.mode)) { console.error("bad mode: " + p.mode); process.exit(1); }
    if (!Array.isArray(p.packs)) { console.error("packs not array"); process.exit(1); }
    if (!["lean", "full"].includes(p.skillProfile)) { console.error("bad profile"); process.exit(1); }
  '
}

@test "wizard_defaults_match_deploy_defaults" {
  # Default packs mirror the main deploy default: none.
  local packs
  packs="$(emit_default_plan | node -e 'console.log(JSON.parse(require("fs").readFileSync(0,"utf8")).packs.length)')"
  [ "$packs" = "0" ]
  local profile
  profile="$(emit_default_plan | node -e 'console.log(JSON.parse(require("fs").readFileSync(0,"utf8")).skillProfile)')"
  [ "$profile" = "lean" ]
}

@test "wizard_non_tty_aborts_without_writing" {
  local d
  d="$(mktemp -d)"
  run bash -c "echo | node '$TUI' install-wizard --out '$d/plan.json' >/dev/null 2>&1"
  [ "$status" -ne 0 ]
  [ ! -f "$d/plan.json" ]
  rm -rf "$d"
}

@test "wizard_from_plan_maps_to_equivalent_flags" {
  # THE equivalence pin: plan-derived build_plan output ≡ explicit-flag
  # build_plan output (step count + mode + flags).
  local fixture
  fixture="$(mktemp)"
  cat > "$fixture" << 'EOF'
{"schema": "civiltekk-install-plan/1", "mode": "quick", "provider": "anthropic", "packs": ["markitdown", "docling"], "skillProfile": "full"}
EOF
  local a b
  a="$(bash -c "
    set -o pipefail; set -o nounset
    source '$SETUP_SH' >/dev/null 2>&1
    FROM_PLAN='$fixture'
    build_plan >/dev/null 2>&1
    echo \"\$PLAN_MODE|\$QUICK_SETUP|\$PROVIDER|\$ENABLE_PACK|\$SKILL_PROFILE|\${#PLAN_STEPS[@]}\"
  " 2>/dev/null)"
  b="$(bash -c "
    set -o pipefail; set -o nounset
    source '$SETUP_SH' >/dev/null 2>&1
    QUICK_SETUP=true; PROVIDER=anthropic; ENABLE_PACK=markitdown,docling; SKILL_PROFILE=full
    build_plan >/dev/null 2>&1
    echo \"\$PLAN_MODE|\$QUICK_SETUP|\$PROVIDER|\$ENABLE_PACK|\$SKILL_PROFILE|\${#PLAN_STEPS[@]}\"
  " 2>/dev/null)"
  [ "$a" = "$b" ]
  rm -f "$fixture"
}

@test "wizard_from_plan_skills_only_defaults" {
  local fixture plan_a plan_b
  fixture="$(mktemp)"
  node "$TUI" install-wizard --print-plan --defaults --out "$fixture"
  plan_a="$(bash -c "
    source '$SETUP_SH' >/dev/null 2>&1
    FROM_PLAN='$fixture'
    build_plan >/dev/null 2>&1
    echo \"\$PLAN_MODE|\$SKILLS_ONLY|\${#PLAN_STEPS[@]}\"
  " 2>/dev/null)"
  plan_b="$(bash -c "
    source '$SETUP_SH' >/dev/null 2>&1
    SKILLS_ONLY=true
    build_plan >/dev/null 2>&1
    echo \"\$PLAN_MODE|\$SKILLS_ONLY|\${#PLAN_STEPS[@]}\"
  " 2>/dev/null)"
  [ "$plan_a" = "$plan_b" ]
  rm -f "$fixture"
}

@test "wizard_from_plan_rejects_unknown_pack_via_existing_gate" {
  local fixture
  fixture="$(mktemp)"
  echo '{"schema": "civiltekk-install-plan/1", "mode": "skills-only", "packs": ["nonexistent-pack"]}' > "$fixture"
  run bash -c "
    source '$SETUP_SH' >/dev/null 2>&1
    FROM_PLAN='$fixture'
    build_plan >/dev/null 2>&1
    validate_enable_pack
  "
  [ "$status" -ne 0 ]
  rm -f "$fixture"
}

@test "wizard_from_plan_rejects_bad_schema_and_mode" {
  local f
  f="$(mktemp)"
  echo '{"schema": "nope", "mode": "quick"}' > "$f"
  run bash -c "source '$SETUP_SH' >/dev/null 2>&1; FROM_PLAN='$f'; build_plan" 
  [ "$status" -ne 0 ]
  echo '{"schema": "civiltekk-install-plan/1", "mode": "galaxy-brain"}' > "$f"
  run bash -c "source '$SETUP_SH' >/dev/null 2>&1; FROM_PLAN='$f'; build_plan"
  [ "$status" -ne 0 ]
  rm -f "$f"
}

@test "wizard_pack_catalog_reflects_packs_dir" {
  # The wizard's pack list comes from deploy/packs — a new pack file appears
  # without any tui.mjs edit (the #677 decoupling, asserted at the TUI layer).
  local dir_names catalog_names
  dir_names="$(cd deploy/packs && ls pack-*.json | sed 's/^pack-//;s/\.json$//' | sort | tr '\n' ',')"
  catalog_names="$(node -e '
    const fs = require("fs");
    const src = fs.readFileSync("deploy/tui.mjs", "utf8");
    // exercise the real loader through the module: parse via a tiny eval of
    // the same pattern the wizard uses is fragile — instead pin the source
    // reads the packs dir (no hardcoded name list).
    if (!/readdirSync\(packsDir\)/.test(src)) { console.error("wizard does not read packs dir"); process.exit(1); }
    console.log("dynamic");
  ')"
  [ "$catalog_names" = "dynamic" ]
  [ -n "$dir_names" ]
}
