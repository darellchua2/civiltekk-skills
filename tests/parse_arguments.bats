#!/usr/bin/env bats

PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
SETUP_SH="${PROJECT_ROOT}/deploy/setup.sh"

setup() {
    TEST_HOME="$(mktemp -d)"
    TEST_LOG="${TEST_HOME}/.opencode-setup.log"
    export HOME="$TEST_HOME"
    export LOG_FILE="$TEST_LOG"
    export BACKUP_DIR="${TEST_HOME}/.opencode-backup-$(date +%Y%m%d_%H%M%S)"
    export DRY_RUN=false
    export VERBOSE=true

    source "$SETUP_SH"

    KEEP_BACKUPS=5
}

teardown() {
    rm -rf "$TEST_HOME"
}

@test "default KEEP_BACKUPS is 5" {
    [ "$KEEP_BACKUPS" -eq 5 ]
}

@test "--keep-backups 3 sets KEEP_BACKUPS to 3" {
    parse_arguments --keep-backups 3
    [ "$KEEP_BACKUPS" -eq 3 ]
}

@test "-k 10 sets KEEP_BACKUPS to 10" {
    parse_arguments -k 10
    [ "$KEEP_BACKUPS" -eq 10 ]
}

@test "--keep-backups 0 sets KEEP_BACKUPS to 0" {
    parse_arguments --keep-backups 0
    [ "$KEEP_BACKUPS" -eq 0 ]
}

@test "--keep-backups -1 sets KEEP_BACKUPS to -1" {
    KEEP_BACKUPS=-1
    [ "$KEEP_BACKUPS" -eq -1 ]
}

@test "--keep-backups with negative value directly assigned works" {
    KEEP_BACKUPS=-1
    run cleanup_old_backups
    [ "$status" -eq 0 ]
}

@test "--keep-backups abc exits with error" {
    run parse_arguments --keep-backups abc
    [ "$status" -ne 0 ]
}

@test "--keep-backups with no argument exits with error" {
    run parse_arguments --keep-backups
    [ "$status" -ne 0 ]
}

@test "--keep-backups 1.5 exits with error (non-integer)" {
    run parse_arguments --keep-backups 1.5
    [ "$status" -ne 0 ]
}

@test "--dry-run flag sets DRY_RUN=true" {
    parse_arguments --dry-run
    [ "$DRY_RUN" = true ]
}

@test "--verbose flag sets VERBOSE=true" {
    VERBOSE=false
    parse_arguments --verbose
    [ "$VERBOSE" = true ]
}

@test "unknown option exits with error" {
    run parse_arguments --nonexistent
    [ "$status" -ne 0 ]
}

# =============================================================================
# #466: --peonping flag + mode-conflict validation
# =============================================================================

@test "--peonping sets PEONPING_ONLY" {
    parse_arguments --peonping
    [ "$PEONPING_ONLY" = true ]
}

@test "-P is an alias for --peonping" {
    parse_arguments -P
    [ "$PEONPING_ONLY" = true ]
}

@test "help mentions peonping on both help surfaces" {
    run bash "${PROJECT_ROOT}/deploy/setup.sh" --help
    [ "$status" -eq 0 ]
    count=$(echo "$output" | grep -ci peonping)
    [ "$count" -ge 2 ]
}

@test "validate_mode_conflicts accepts each single mode" {
    for mode in QUICK_SETUP SKILLS_ONLY UPDATE_ONLY MODELS_ONLY MIGRATE_ONLY ROLLBACK_MODE CHECK_UPDATE_ONLY PEONPING_ONLY; do
        run bash -c "source '$SETUP_SH' >/dev/null 2>&1; $mode=true; validate_mode_conflicts"
        [ "$status" -eq 0 ]
    done
}

@test "conflicting modes die with a named error" {
    run bash -c "source '$SETUP_SH' >/dev/null 2>&1; QUICK_SETUP=true; SKILLS_ONLY=true; validate_mode_conflicts"
    [ "$status" -ne 0 ]
    [[ "$output" == *"--quick --skills-only"* ]]
    [[ "$output" == *"Mutually exclusive"* ]]
}

@test "enable-pack dies with modes that never deploy config" {
    for mode in UPDATE_ONLY MODELS_ONLY MIGRATE_ONLY ROLLBACK_MODE CHECK_UPDATE_ONLY PEONPING_ONLY; do
        run bash -c "source '$SETUP_SH' >/dev/null 2>&1; $mode=true; ENABLE_PACK=markitdown; validate_mode_conflicts"
        [ "$status" -ne 0 ]
        [[ "$output" == *"--enable-pack has no effect"* ]]
    done
}

@test "enable-pack stays valid with config-deploying modes" {
    for mode in QUICK_SETUP SKILLS_ONLY; do
        run bash -c "source '$SETUP_SH' >/dev/null 2>&1; $mode=true; ENABLE_PACK=markitdown; validate_mode_conflicts"
        [ "$status" -eq 0 ]
    done
    # The no-mode default (bare full deploy) is the third valid combo — and
    # the one headless users actually hit.
    run bash -c "source '$SETUP_SH' >/dev/null 2>&1; ENABLE_PACK=markitdown; validate_mode_conflicts"
    [ "$status" -eq 0 ]
}

@test "--from-plan sets FROM_PLAN; --no-tui sets NO_TUI (#677)" {
    run bash -c "source '$SETUP_SH' >/dev/null 2>&1; parse_arguments --from-plan /tmp/p.json --no-tui; echo \"\$FROM_PLAN|\$NO_TUI\""
    [ "$status" -eq 0 ]
    [[ "$output" == *"/tmp/p.json|true"* ]]
}

@test "--from-plan with no argument errors (#677)" {
    run bash -c "source '$SETUP_SH' >/dev/null 2>&1; parse_arguments --from-plan"
    [ "$status" -ne 0 ]
}

@test "--from-plan conflicts with explicit mode flags (#677)" {
    run bash -c "source '$SETUP_SH' >/dev/null 2>&1; FROM_PLAN=/tmp/p.json; SKILLS_ONLY=true; validate_mode_conflicts"
    [ "$status" -ne 0 ]
    [[ "$output" == *"combines with no explicit mode flag"* ]]
}

@test "--from-plan alone passes mode validation (#677)" {
    run bash -c "source '$SETUP_SH' >/dev/null 2>&1; FROM_PLAN=/tmp/p.json; validate_mode_conflicts"
    [ "$status" -eq 0 ]
}
