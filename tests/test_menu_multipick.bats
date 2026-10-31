# Menu multi-pick (#673): parse_menu_selection, the validate_mode_conflicts
# add-on whitelist, and build_plan's select/peonping injection.
# Pattern: each case sources deploy/setup.sh in a child bash and disarms the
# ERR trap (the script installs an exit-on-error handler that would otherwise
# kill the assertion on the first non-zero return).

setup() {
    REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
}

snip() {
    bash -c "cd '$REPO' && source deploy/setup.sh >/dev/null 2>&1; trap - ERR; $1"
}

# ── parse_menu_selection ─────────────────────────────────────────────────────

@test "parse: blank pick defaults to base 2" {
    run snip 'parse_menu_selection ""; echo "base=$MENU_BASE"'
    [ "$status" -eq 0 ]
    [ "$output" = "base=2" ]
}

@test "parse: single base 3, no addons" {
    run snip 'parse_menu_selection "3"; echo "base=$MENU_BASE addons=$MENU_ADDON_PEONPING/$MENU_ADDON_SELECT"'
    [ "$status" -eq 0 ]
    [ "$output" = "base=3 addons=false/false" ]
}

@test "parse: 2,6 sets base + select addon" {
    run snip 'parse_menu_selection "2,6"; echo "base=$MENU_BASE sel=$MENU_ADDON_SELECT"'
    [ "$status" -eq 0 ]
    [ "$output" = "base=2 sel=true" ]
}

@test "parse: space separator works like comma (2 6)" {
    run snip 'parse_menu_selection "2 6"; echo "base=$MENU_BASE sel=$MENU_ADDON_SELECT"'
    [ "$status" -eq 0 ]
    [ "$output" = "base=2 sel=true" ]
}

@test "parse: 3,5,6 full base with both addons" {
    run snip 'parse_menu_selection "3,5,6"; echo "base=$MENU_BASE p=$MENU_ADDON_PEONPING s=$MENU_ADDON_SELECT"'
    [ "$status" -eq 0 ]
    [ "$output" = "base=3 p=true s=true" ]
}

@test "parse: 4 runs alone" {
    run snip 'parse_menu_selection "4"; echo "base=$MENU_BASE"'
    [ "$status" -eq 0 ]
    [ "$output" = "base=4" ]
}

@test "parse rejects base plus 4 (2,4)" {
    run snip 'parse_menu_selection "2,4"'
    [ "$status" -eq 1 ]
}

@test "parse rejects two bases (1,2)" {
    run snip 'parse_menu_selection "1,2"'
    [ "$status" -eq 1 ]
}

@test "parse rejects unknown token (9)" {
    run snip 'parse_menu_selection "9"'
    [ "$status" -eq 1 ]
}

# ── validate_mode_conflicts whitelist ────────────────────────────────────────

@test "validate accepts --skills-only --select" {
    run snip 'SKILLS_ONLY=true; SELECT_ITEMS=true; validate_mode_conflicts'
    [ "$status" -eq 0 ]
}

@test "validate accepts --quick --select" {
    run snip 'QUICK_SETUP=true; SELECT_ITEMS=true; validate_mode_conflicts'
    [ "$status" -eq 0 ]
}

@test "validate accepts select alone (plain full)" {
    run snip 'SELECT_ITEMS=true; validate_mode_conflicts'
    [ "$status" -eq 0 ]
}

@test "validate auto-demotes --quick --peonping to the add-on flag" {
    run snip 'QUICK_SETUP=true; PEONPING_ONLY=true; validate_mode_conflicts; echo "addon=$PEONPING_ADDON only=$PEONPING_ONLY"'
    [ "$status" -eq 0 ]
    [ "$output" = "addon=true only=false" ]
}

@test "validate rejects --update --select" {
    run snip 'UPDATE_ONLY=true; SELECT_ITEMS=true; validate_mode_conflicts'
    [ "$status" -eq 1 ]
}

@test "validate rejects --rollback --select" {
    run snip 'ROLLBACK_MODE=true; SELECT_ITEMS=true; validate_mode_conflicts'
    [ "$status" -eq 1 ]
}

@test "validate rejects --peonping --update (standalone stays exclusive)" {
    run snip 'PEONPING_ONLY=true; UPDATE_ONLY=true; validate_mode_conflicts'
    [ "$status" -eq 1 ]
}

@test "validate rejects peonping as both mode and add-on" {
    run snip 'PEONPING_ONLY=true; PEONPING_ADDON=true; validate_mode_conflicts'
    [ "$status" -eq 1 ]
}

@test "validate rejects two bases (--quick --skills-only)" {
    run snip 'QUICK_SETUP=true; SKILLS_ONLY=true; validate_mode_conflicts'
    [ "$status" -eq 1 ]
}

# ── build_plan injection ─────────────────────────────────────────────────────

@test "build_plan: skills-only + select injects picker, drops blanket agents" {
    run snip 'SKILLS_ONLY=true; SELECT_ITEMS=true; build_plan; echo "mode=$PLAN_MODE"; printf "%s\n" "${PLAN_STEPS[@]:-}"'
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "mode=skills-only" ]
    [[ "$output" == *"deploy_selected_skills"* ]]
    [[ "$output" != *"true|agents|Deploy agents|deploy_agents"* ]]
}

@test "build_plan: full + select keeps #473 behavior (helper parity)" {
    run snip 'SELECT_ITEMS=true; build_plan; echo "mode=$PLAN_MODE"; printf "%s\n" "${PLAN_STEPS[@]:-}"'
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "mode=full" ]
    [[ "$output" == *"deploy_selected_skills"* ]]
    [[ "$output" != *"true|agents|Deploy agents|deploy_agents"* ]]
}

@test "build_plan: skills-only + peonping addon appends a non-critical step" {
    run snip 'SKILLS_ONLY=true; PEONPING_ADDON=true; build_plan; printf "%s\n" "${PLAN_STEPS[@]:-}"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"false|peonping-addon|Install PeonPing sound notifications|setup_peonping"* ]]
}

@test "build_plan: quick + peonping addon lands on the full plan" {
    run snip 'QUICK_SETUP=true; PEONPING_ADDON=true; build_plan; echo "mode=$PLAN_MODE"; printf "%s\n" "${PLAN_STEPS[@]:-}"'
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "mode=full" ]
    [[ "$output" == *"peonping-addon"* ]]
}

@test "build_plan: standalone --peonping keeps its own mode" {
    run snip 'PEONPING_ONLY=true; build_plan; echo "mode=$PLAN_MODE"'
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "mode=peonping" ]
}

@test "build_plan: skills-only without addons keeps the blanket deploy" {
    run snip 'SKILLS_ONLY=true; build_plan; printf "%s\n" "${PLAN_STEPS[@]:-}"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"true|agents|Deploy agents|deploy_agents"* ]]
    [[ "$output" != *"deploy_selected_skills"* ]]
}

@test "parse: base 0 = guided wizard (#677)" {
    run snip 'parse_menu_selection "0"; echo "base=$MENU_BASE"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"base=0"* ]]
}

@test "parse: 0,6 = guided + select addon (#677)" {
    run snip 'parse_menu_selection "0,6"; echo "base=$MENU_BASE sel=$MENU_ADDON_SELECT"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"base=0 sel=true"* ]]
}

@test "parse: two bases including 0 rejected (#677)" {
    run snip 'parse_menu_selection "0,2"; echo "rc=$?"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"more than one base"* ]]
}
