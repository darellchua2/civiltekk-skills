#!/usr/bin/env bats

# Deploy plan model + executor pins (#470). The plan (build_plan) is the
# single authoritative mode→steps mapping; the executor (run_plan) owns
# failure semantics: non-critical continues, critical stops, exit code is
# truthful. Per-mode preconditions are steps (deps/node/opencode checks) —
# the #470 arch review's precondition matrix, pinned per mode.

SETUP_SH="deploy/setup.sh"

# Source once per test with a sandbox HOME; flags are set AFTER source
# (the sandbox-clobber rule) and build_plan is then called directly.
source_plan() {
    local d="$1"; shift
    HOME="$d" bash -c "source '$SETUP_SH' >/dev/null 2>&1; export $*; build_plan; printf '%s\n' \"\${PLAN_STEPS[@]}\""
}

@test "plan_full_mode_shape" {
    local d; d="$(mktemp -d)"
    run source_plan "$d" "QUICK_SETUP=false"
    rm -rf "$d"
    [ "$status" -eq 0 ]
    local first second third
    first=$(echo "$output" | head -1)
    second=$(echo "$output" | sed -n 2p)
    third=$(echo "$output" | sed -n 3p)
    # #673: runtime context is the new step 1 (read-only, non-critical banner)
    [[ "$first" == *"false|runtime-context|Print runtime context|detect_runtime_context"* ]]
    [[ "$second" == *"true|deps|Dependency check|check_dependencies_strict"* ]]
    # #573: detection is the next read-only step (non-critical); gh-cli moved to 3.
    [[ "$third" == *"false|detect-agents|"* ]]
    echo "$output" | grep -q 'false|gh-cli|'
    # content steps exist with correct criticality
    echo "$output" | grep -q 'true|config|Deploy config|setup_config'
    echo "$output" | grep -q 'true|agents|Deploy agents|deploy_agents'
    echo "$output" | grep -q 'true|plugins|Deploy plugins|deploy_plugins'
    echo "$output" | grep -q 'false|shell-vars|'
    # env steps present in full
    echo "$output" | grep -q 'false|nvm|'
    # #573: seeding rides right after credential capture (non-critical)
    echo "$output" | grep -q 'false|seed-agent-keys|Seed Z.AI key into detected agents|seed_agent_keys'
}

@test "plan_quick_mode_has_no_env_steps" {
    local d; d="$(mktemp -d)"
    run source_plan "$d" "QUICK_SETUP=true"
    rm -rf "$d"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q 'true|deps|'
    ! echo "$output" | grep -q '|nvm|'
    ! echo "$output" | grep -q '|gh-cli|'
}

@test "plan_skills_only_preconditions_are_steps" {
    local d; d="$(mktemp -d)"
    run source_plan "$d" "SKILLS_ONLY=true"
    rm -rf "$d"
    [ "$status" -eq 0 ]
    [[ "$output" == *"true|opencode-check|"* ]]
    [[ "$output" == *"true|deps|"* ]]
    echo "$output" | grep -q 'true|config|'
    echo "$output" | grep -q 'true|agents|'
    echo "$output" | grep -q 'true|plugins|'
    echo "$output" | grep -q 'false|init-symlink|'
}

@test "plan_models_only_manifest_update_is_noncritical_379" {
    local d; d="$(mktemp -d)"
    run source_plan "$d" "MODELS_ONLY=true"
    rm -rf "$d"
    [ "$status" -eq 0 ]
    [[ "$output" == *"true|node-check|"* ]]
    echo "$output" | grep -q 'true|resolver-config|'
    echo "$output" | grep -q 'false|manifest-update|'
}

@test "plan_check_update_is_single_step_critical_mode" {
    local d; d="$(mktemp -d)"
    run source_plan "$d" "CHECK_UPDATE_ONLY=true"
    rm -rf "$d"
    [ "$status" -eq 0 ]
    [[ "$output" == *"true|deps|"* ]]
    [[ "$output" == *"true|check-update|"* ]]
    [ "$(echo "$output" | wc -l)" -eq 2 ]
}

@test "executor_continues_past_noncritical_and_stops_on_critical" {
    local d; d="$(mktemp -d)"
    run bash -c "export HOME='$d'; source '$SETUP_SH' >/dev/null 2>&1
        stub_ok(){ return 0; }; stub_fail(){ return 1; }; stub_after(){ echo AFTER_RAN; }
        PLAN_STEPS=( 'false|a|A failing non-critical|stub_fail' 'true|b|B ok|stub_ok' 'false|c|C after|stub_after' )
        run_plan; echo \"rc=\$?\""
    rm -rf "$d"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Non-critical step failed (continuing): A failing non-critical"* ]]
    [[ "$output" == *"AFTER_RAN"* ]]
}

@test "executor_critical_failure_stops_and_reports" {
    local d; d="$(mktemp -d)"
    run bash -c "export HOME='$d'; source '$SETUP_SH' >/dev/null 2>&1
        stub_ok(){ return 0; }; stub_fail(){ return 1; }; stub_never(){ echo NEVER; }
        PLAN_STEPS=( 'true|boom|Critical boom|stub_fail' 'false|never|Never runs|stub_never' )
        if ! run_plan; then echo PLAN_FAILED; fi"
    rm -rf "$d"
    [[ "$output" == *"Critical step failed: Critical boom"* ]]
    [[ "$output" != *"NEVER"* ]]
    [[ "$output" == *"PLAN_FAILED"* ]]
}

@test "build_plan_dies_on_conflicting_modes" {
    local d; d="$(mktemp -d)"
    run bash -c "export HOME='$d'; source '$SETUP_SH' >/dev/null 2>&1; QUICK_SETUP=true; SKILLS_ONLY=true; build_plan"
    rm -rf "$d"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Mutually exclusive"* ]]
}

@test "d2_declined_config_survives_resolver_in_place_patch" {
    local d; d="$(mktemp -d)"
    mkdir -p "$d/.config/opencode"
    cat > "$d/.config/opencode/opencode.json" <<'JSON'
{ "custom_user_key": "keep-me", "theme": "user-theme" }
JSON
    bash -c "export HOME='$d'; source '$SETUP_SH' >/dev/null 2>&1
        DRY_RUN=false; SKIP_CONFIG_COPY=true; RESOLVER_CONFIG_ONLY=true
        run_resolver" >/dev/null 2>&1
    # The user's custom keys must survive the in-place patch (D2 contract).
    grep -q 'keep-me' "$d/.config/opencode/opencode.json"
    grep -q 'user-theme' "$d/.config/opencode/opencode.json"
    rm -rf "$d"
}

@test "d2_declined_with_no_config_writes_none" {
    local d; d="$(mktemp -d)"
    mkdir -p "$d/.config/opencode"
    bash -c "export HOME='$d'; source '$SETUP_SH' >/dev/null 2>&1
        DRY_RUN=false; SKIP_CONFIG_COPY=true; RESOLVER_CONFIG_ONLY=true
        run_resolver" >/dev/null 2>&1
    [ ! -f "$d/.config/opencode/opencode.json" ]
    rm -rf "$d"
}

@test "d2_without_skip_stock_template_wins" {
    local d; d="$(mktemp -d)"
    mkdir -p "$d/.config/opencode"
    cat > "$d/.config/opencode/opencode.json" <<'JSON'
{ "custom_user_key": "keep-me" }
JSON
    bash -c "export HOME='$d'; source '$SETUP_SH' >/dev/null 2>&1
        DRY_RUN=false; SKIP_CONFIG_COPY=false; RESOLVER_CONFIG_ONLY=true
        run_resolver" >/dev/null 2>&1
    # Stock base (config-src) overwrites — pre-existing behavior, pinned so
    # the D2 gate's absence is what this test failing means. run+status form:
    # bare `! grep` is errexit-exempt and would not fail the test.
    run grep -q 'keep-me' "$d/.config/opencode/opencode.json"
    [ "$status" -ne 0 ]
    rm -rf "$d"
}

@test "d2_decline_stale_model_key_deletion_is_expected" {
    # Arch review requirement: with no --provider, the resolver DELETES a stale
    # explicit "model" key (resolve-models.mjs:293-295) — that is documented
    # resolver behavior on the declined file, NOT a decline-contract bug. Pin
    # it so a future change is a conscious decision (LEARNINGS
    # decisions/resolver-omit-config-src-preserve-contract.md).
    local d; d="$(mktemp -d)"
    mkdir -p "$d/.config/opencode"
    cat > "$d/.config/opencode/opencode.json" <<'JSON'
{ "model": "stale/old", "custom_user_key": "keep-me" }
JSON
    bash -c "export HOME='$d'; source '$SETUP_SH' >/dev/null 2>&1
        DRY_RUN=false; SKIP_CONFIG_COPY=true; RESOLVER_CONFIG_ONLY=true
        run_resolver" >/dev/null 2>&1
    # Top-level model key deleted (agents.*.model keys legitimately remain).
    node -e 'const c=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")); if (c.model !== undefined) { console.error("stale top-level model survived:", c.model); process.exit(1); } if (c.custom_user_key !== "keep-me") { console.error("custom key lost"); process.exit(1); }' "$d/.config/opencode/opencode.json"
    rm -rf "$d"
}

@test "truthful_exit_models_only_failing_node_check_exits_nonzero" {
    local d; d="$(mktemp -d)"
    run bash -c "export HOME='$d'; source '$SETUP_SH' >/dev/null 2>&1
        command_exists(){ [ \"\$1\" = node ] && return 1 || return 0; }
        check_network(){ return 0; }; main --models-only --dry-run -y" </dev/null
    rm -rf "$d"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Node.js is required"* ]]
}

@test "trace_skills_only_dry_run_runs_plan_in_order" {
    local d; d="$(mktemp -d)"
    run bash -c "export HOME='$d'; source '$SETUP_SH' >/dev/null 2>&1
        check_dependencies(){ return 0; }; command_exists(){ return 0; }
        check_network(){ return 0; }; main --dry-run -y -s" </dev/null
    rm -rf "$d"
    [ "$status" -eq 0 ]
    # Steps appear in plan order
    local oc deps config agents plugins
    oc=$(echo "$output" | grep -n "Validate opencode install" | head -1 | cut -d: -f1)
    deps=$(echo "$output" | grep -n "Dependency check" | head -1 | cut -d: -f1)
    config=$(echo "$output" | grep -n "Plan step: Deploy config" | head -1 | cut -d: -f1)
    agents=$(echo "$output" | grep -n "Plan step: Deploy agents" | head -1 | cut -d: -f1)
    plugins=$(echo "$output" | grep -n "Plan step: Deploy plugins" | head -1 | cut -d: -f1)
    # One assertion per line — &&-chained assertions only enforce the final
    # link under bats errexit (bats-and-chain LEARNINGS).
    [ -n "$oc" ]
    [ -n "$deps" ]
    [ -n "$config" ]
    [ -n "$agents" ]
    [ -n "$plugins" ]
    [ "$oc" -lt "$deps" ]
    [ "$deps" -lt "$config" ]
    [ "$config" -lt "$agents" ]
    [ "$agents" -lt "$plugins" ]
}

# =============================================================================
# #491 — models-only/migrate presence gate (D2 alignment)
# =============================================================================

@test "models_only_existing_config_survives_in_place_patch" {
    local d; d="$(mktemp -d)"
    mkdir -p "$d/.config/opencode"
    cat > "$d/.config/opencode/opencode.json" <<'JSON'
{ "custom_user_key": "keep-me", "theme": "user-theme" }
JSON
    bash -c "export HOME='$d'; source '$SETUP_SH' >/dev/null 2>&1
        DRY_RUN=false; MODELS_ONLY=true; RESOLVER_CONFIG_ONLY=true
        run_resolver" >/dev/null 2>&1
    # Presence gate (#491): no --config-src ⇒ dest-fallback patches in place.
    grep -q 'keep-me' "$d/.config/opencode/opencode.json"
    grep -q 'user-theme' "$d/.config/opencode/opencode.json"
    rm -rf "$d"
}

@test "models_only_fresh_bootstrap_writes_stock" {
    local d; d="$(mktemp -d)"
    mkdir -p "$d/.config/opencode"
    bash -c "export HOME='$d'; source '$SETUP_SH' >/dev/null 2>&1
        DRY_RUN=false; MODELS_ONLY=true; RESOLVER_CONFIG_ONLY=true
        run_resolver" >/dev/null 2>&1
    # No existing config ⇒ stock base MUST still be written (bootstrap).
    [ -f "$d/.config/opencode/opencode.json" ]
    node -e 'JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"))' "$d/.config/opencode/opencode.json"
    rm -rf "$d"
}

@test "migrate_existing_config_survives_in_place_patch" {
    local d; d="$(mktemp -d)"
    mkdir -p "$d/.config/opencode"
    cat > "$d/.config/opencode/opencode.json" <<'JSON'
{ "custom_user_key": "keep-me", "theme": "user-theme" }
JSON
    bash -c "export HOME='$d'; source '$SETUP_SH' >/dev/null 2>&1
        DRY_RUN=false; MIGRATE_ONLY=true; RESOLVER_CONFIG_ONLY=true
        run_resolver" >/dev/null 2>&1
    grep -q 'keep-me' "$d/.config/opencode/opencode.json"
    grep -q 'user-theme' "$d/.config/opencode/opencode.json"
    rm -rf "$d"
}

@test "migrate_fresh_bootstrap_writes_stock" {
    local d; d="$(mktemp -d)"
    mkdir -p "$d/.config/opencode"
    bash -c "export HOME='$d'; source '$SETUP_SH' >/dev/null 2>&1
        DRY_RUN=false; MIGRATE_ONLY=true; RESOLVER_CONFIG_ONLY=true
        run_resolver" >/dev/null 2>&1
    [ -f "$d/.config/opencode/opencode.json" ]
    node -e 'JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"))' "$d/.config/opencode/opencode.json"
    rm -rf "$d"
}

@test "models_only_jsonc_sibling_parked_exactly_one_live_config" {
    # #491 AC3 (the #432 interaction through the presence gate): a live
    # opencode.jsonc means NO opencode.json ⇒ gate passes --config-src ⇒
    # stock base written ⇒ park_jsonc_sibling collapses the sibling so the
    # run ends with exactly one live config.
    local d; d="$(mktemp -d)"
    mkdir -p "$d/.config/opencode"
    cat > "$d/.config/opencode/opencode.jsonc" <<'JSONC'
{
  // user's jsonc-flavored config
  "theme": "user-jsonc-theme"
}
JSONC
    bash -c "export HOME='$d'; source '$SETUP_SH' >/dev/null 2>&1
        DRY_RUN=false; MODELS_ONLY=true; RESOLVER_CONFIG_ONLY=true
        run_resolver" >/dev/null 2>&1
    [ -f "$d/.config/opencode/opencode.json" ]
    [ ! -f "$d/.config/opencode/opencode.jsonc" ]
    [ -f "$d/.config/opencode/opencode.jsonc.legacy-ignored" ]
    rm -rf "$d"
}
