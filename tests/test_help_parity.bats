#!/usr/bin/env bats

# #571 pins: --help UX fixes + setup.ps1 ↔ setup.sh flag parity. Grep-based,
# the repo's established launcher/CLI pin style (see test_setup_ps1_vars.bats).
# CI images carry no pwsh — PowerShell runtime proof is delegated to the
# undefined-variable audit in test_setup_ps1_vars.bats plus review of the
# translation table; everything here is statically checkable.

SETUP_PS1="deploy/setup.ps1"
SETUP_SH="deploy/setup.sh"
INIT_MJS="installer/init.mjs"

# ── setup.sh help footer (#571 AC1) ──

@test "setup_sh_help_points_at_this_repo_not_upstream" {
  grep -qF 'Report issues: https://github.com/darellchua2/civiltekk-opencode-claude-skills/issues' "$SETUP_SH"
  run grep -q anomalyco "$SETUP_SH"
  [ "$status" -ne 0 ]
}

@test "setup_sh_markitdown_bump_comment_names_only_pin_carriers" {
  # The ps1 carries no pin since #474; the ritual comment must not instruct
  # writing one there (test_setup_ps1_vars.bats fails the ps1 if it appears).
  # #607: the Dockerfile surface is gone. #677: the pin + bump ritual moved
  # into the pack JSON install block ($install-notes) — grep it there.
  grep -qF 'Bump ritual: bump the pin here' deploy/packs/pack-markitdown.json
  grep -qF 'this block is the only pin carrier' deploy/packs/pack-markitdown.json
  # setup.sh must no longer carry the pip pin (the generic installer is
  # pack-agnostic — pins are data).
  run grep -qF 'markitdown-mcp==0.0.1a7' "$SETUP_SH"
  [ "$status" -ne 0 ]
}

# ── installer/init.mjs help UX (#571 AC2/AC3) ──

@test "init_mjs_supports_short_h_help_flag" {
  grep -qF '"-h": "help"' "$INIT_MJS"
}

@test "init_mjs_help_has_npx_copy_paste_examples" {
  grep -qF 'npx github:darellchua2/civiltekk-opencode-claude-skills --list categories' "$INIT_MJS"
  grep -qF 'npx github:darellchua2/civiltekk-opencode-claude-skills add civiltekk-api-spec-skill' "$INIT_MJS"
  grep -qF 'npx github:darellchua2/civiltekk-opencode-claude-skills add office-document-router-skill --dry-run' "$INIT_MJS"
  grep -qF 'npx github:darellchua2/civiltekk-opencode-claude-skills add code-review-subagent --project .' "$INIT_MJS"
  grep -qF 'npx github:darellchua2/civiltekk-opencode-claude-skills add gsap-core --target claude' "$INIT_MJS"
}

# ── setup.ps1 parity (#571 AC4-AC6) ──

@test "setup_ps1_forwards_positional_subcommands_verbatim" {
  # Without this line `.\setup.ps1 rollback latest` fell through to the
  # interactive-menu default (positionals were silently dropped).
  grep -qF '$forward += $args' "$SETUP_PS1"
}

@test "setup_ps1_help_fast_path_precedes_node_gate" {
  local help_ln gate_ln
  help_ln=$(grep -nF 'if ($Help)' "$SETUP_PS1" | head -1 | cut -d: -f1)
  gate_ln=$(grep -nF 'required for --select' "$SETUP_PS1" | head -1 | cut -d: -f1)
  [ -n "$help_ln" ]
  [ -n "$gate_ln" ]
  [ "$help_ln" -lt "$gate_ln" ]
}

@test "setup_ps1_maps_every_setup_sh_flag_arm_same_line" {
  # Review #571 finding: the delta-only, name/flag-separate greps could not
  # catch a cross-wired arm or a re-dropped pre-existing flag (the #465/#466/
  # #469 class). Pin EVERY arm: the line reading `if ($Name)` must carry that
  # flag's literal on the SAME line; value flags ride @("--flag", $Name) pairs.
  local pairs=(
    'Quick:--quick'
    'SkillsOnly:--skills-only'
    'DryRun:--dry-run'
    'Yes:--yes'
    'Verbose:--verbose'
    'Update:--update'
    'CheckUpdate:--check-update'
    'EnableAutoUpdate:--enable-auto-update'
    'DisableAutoUpdate:--disable-auto-update'
    'ScheduleUpdate:--schedule-update'
    'Select:--select'
    'CheckCatalog:--check-catalog'
    'Peonping:--peonping'
    'KeepBackups:--keep-backups'
    'NoZipBackup:--no-zip-backup'
    'Provider:--provider'
    'ModelsOnly:--models-only'
    'Force:--force'
    'Migrate:--migrate'
    'Mix:--mix'
    'EnablePack:--enable-pack'
    'SkillProfile:--skill-profile'
    'ListItems:--list-items'
    'SavePreset:--save-preset'
    'Preset:--preset'
  )
  local pair name flag line
  for pair in "${pairs[@]}"; do
    name="${pair%%:*}"
    flag="${pair##*:}"
    line=$(grep -F "if (\$$name)" "$SETUP_PS1" | head -1)
    [ -n "$line" ] || { echo "no translation arm reads \$$name"; return 1; }
    echo "$line" | grep -qF -- "\"$flag\"" || { echo "\$$name arm does not forward $flag: $line"; return 1; }
  done
  # Rollback arm is multi-line: pin its value pair and bare form directly.
  grep -qF '@("--rollback", $RollbackTarget)' "$SETUP_PS1"
  grep -qF '$forward += "--rollback"' "$SETUP_PS1"
  # -Help rides the fast-path (bare --help literal), not the $forward table.
  grep -qF '$setupSh --help' "$SETUP_PS1"
}
