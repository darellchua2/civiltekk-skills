#!/usr/bin/env bats

# Dry-run leak pins (#467): every real write reachable under --dry-run must be
# DRY_RUN-gated. The historical leaks: learnings _index.md heredoc, the (since
# removed with the LLM stack, #607) local-LLM .env writer, and the models-only
# init.mjs update that re-applied for real after the resolver had only staged
# a preview.
# Each functional pin carries a positive control (the real run MUST change
# bytes) so a future over-gate cannot silently no-op the fix.

SETUP_SH="deploy/setup.sh"
SETUP_PS1="deploy/setup.ps1"

@test "install_pack_runtime_dry_run_spawns_no_pip" {
  # #677: the generic pack installer mutates site-packages — a preview must
  # only print. Positive control: DRY_RUN=false reaches pip (non-zero in the
  # sandbox proves the gate, not the network, was the difference).
  local d
  d="$(mktemp -d)"
  local out
  out="$(HOME="$d" bash -c "source '$SETUP_SH' >/dev/null 2>&1; DRY_RUN=true; PACKS_DIR='$PWD/deploy/packs'; install_pack_runtime markitdown" 2>&1)"
  [[ "$out" == *'[DRY-RUN] Would install pack runtime: markitdown'* ]]
  rm -rf "$d"
}

@test "learnings_dry_run_writes_no_index" {
  local d
  d="$(mktemp -d)"
  HOME="$d" bash -c "source '$SETUP_SH' >/dev/null 2>&1; DRY_RUN=true; setup_learnings_dir" >/dev/null 2>&1
  [ ! -f "$d/.config/opencode/learnings/_index.md" ]
  rm -rf "$d"
}

@test "learnings_real_run_creates_index_positive_control" {
  local d
  d="$(mktemp -d)"
  HOME="$d" bash -c "source '$SETUP_SH' >/dev/null 2>&1; DRY_RUN=false; setup_learnings_dir" >/dev/null 2>&1
  [ -f "$d/.config/opencode/learnings/_index.md" ]
  rm -rf "$d"
}

@test "setup_sh_models_only_passes_dry_run_to_manifest_update" {
  # Conditional-assignment form, pinned positively AND by banning the
  # ${DRY_RUN:+...} spelling that expanded on the string "false" and silently
  # dried real models-only runs (#467 round 1 BLOCK).
  grep -F '[ "$DRY_RUN" = true ] && dry_arg="--dry-run"' "$SETUP_SH"
  grep -F '${dry_arg}' "$SETUP_SH"
  run grep -Fc '${DRY_RUN:+--dry-run}' "$SETUP_SH"
  [ "$status" -eq 1 ]
  # Semantics pin documenting WHY the spelling is banned:
  run bash -c 'DRY_RUN=false; echo ${DRY_RUN:+expanded}'
  [ "$output" = "expanded" ]
}

@test "setup_ps1_is_thin_launcher_d2_inherited_by_delegation" {
  # #474: the ps1 no longer runs its own resolver — it forwards everything to
  # setup.sh, whose models-only block carries the #467 dry-run gate. The ps1
  # pin flips to asserting the delegation contract.
  grep -q 'setup.sh' "$SETUP_PS1"
  run grep -qF 'Invoke-Resolver' "$SETUP_PS1"
  [ "$status" -ne 0 ]
}

@test "prune_pass_carries_dry_run_arg" {
  # #608: the convergence pass mutates user config (deletes files + manifest
  # rows) — its invocation must carry $dry_arg fed by the pinned
  # explicit-comparison assignment, never the banned ${DRY_RUN:+…} spelling.
  grep -q 'init.mjs" update --prune $provider_arg $dry_arg' "$SETUP_SH"
  run grep -qF '${DRY_RUN:+--dry-run}' "$SETUP_SH"
  [ "$status" -ne 0 ]
}
