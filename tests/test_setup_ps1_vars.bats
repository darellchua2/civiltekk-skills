#!/usr/bin/env bats

# deploy/setup.ps1 pins (#465 origin; #474 made the ps1 a thin launcher).
# The #465 StrictMode regressions lived in the native-PowerShell duplicate,
# which #474 replaced with a bootstrap that forwards everything to
# setup.sh — so the behavior pins flip to delegation assertions, and the
# class-level undefined-variable scan still guards the (small) launcher.

SETUP_PS1="deploy/setup.ps1"
SETUP_SH="deploy/setup.sh"

# =============================================================================
# The two #465 instances, pinned as literals
# =============================================================================

@test "setup_ps1_defines_no_dry_run_preview_dir_itself" {
  # #474: the launcher has no staging of its own — the preview-dir machinery
  # lives in setup.sh and is inherited by delegation.
  run grep -qE '^\$DryRunPreviewDir' "$SETUP_PS1"
  [ "$status" -ne 0 ]
  grep -q 'DRY_RUN_PREVIEW_DIR' "$SETUP_SH"
}

@test "setup_ps1_has_no_appdir_reference" {
  ! grep -q 'Join-Path \$AppDir' "$SETUP_PS1"
}

@test "setup_ps1_delegates_the_487_pinned_install_to_bash" {
  # #487's exact PyPI pin + mcp[cli] co-install moved to the pack JSON
  # install block (#677 — the pack is the only pin carrier); the launcher
  # keeps no pip logic and setup.sh carries only the generic installer.
  grep -qF 'markitdown-mcp==0.0.1a7' deploy/packs/pack-markitdown.json
  run grep -qF 'markitdown-mcp==0.0.1a7' "$SETUP_PS1"
  [ "$status" -ne 0 ]
  run grep -qF 'markitdown-mcp==0.0.1a7' "$SETUP_SH"
  [ "$status" -ne 0 ]
}

@test "setup_ps1_resolver_dry_run_inherited_by_delegation" {
  # resolve-models.mjs writes NOTHING on bare --dry-run; the resolver's
  # --preview-dir staging lives in setup.sh (pinned there) and the launcher
  # forwards --dry-run verbatim.
  grep -q -- '--preview-dir' "$SETUP_SH"
  grep -q '\$DryRun' "$SETUP_PS1"
  grep -q -- '"--dry-run"' "$SETUP_PS1"
}

# =============================================================================
# Class-level guard: zero undefined-variable reads in the whole file
# =============================================================================

@test "setup_ps1_has_zero_undefined_variable_reads" {
  command -v python3 >/dev/null || skip "python3 not available"
  python3 - "$SETUP_PS1" <<'PYEOF'
import re, sys
src = open(sys.argv[1]).read()
# Strip comments first: prose may legitimately mention $Var names.
src = re.sub(r'<#[\s\S]*?#>', '', src)
src = re.sub(r'(?m)#.*$', '', src)
param_vars = set()
for m in re.finditer(r'param\s*\(', src):
    i, depth = m.end(), 1
    while depth and i < len(src):
        if src[i] == '(': depth += 1
        elif src[i] == ')': depth -= 1
        i += 1
    param_vars |= set(re.findall(r'\$([A-Za-z][A-Za-z0-9_]*)', src[m.end():i]))
assigned = set(re.findall(r'\$([A-Za-z][A-Za-z0-9_]*)\s*(?:=[^=]|\+=)', src))
assigned |= set(re.findall(r'foreach\s*\(\s*\$([A-Za-z][A-Za-z0-9_]*)\s+in', src))
all_vars = set(re.findall(r'\$([A-Za-z][A-Za-z0-9_]*)', src))
auto = {'true','false','null','args','_','LASTEXITCODE','Matches','Error',
        'MyInvocation','PSItem','env','global','script','host','Input',
        'ErrorActionPreference','InformationPreference','VerbosePreference',
        'WarningPreference','ErrorAction','ProgressPreference','HOME',
        'PROFILE','PSScriptRoot','PSVersionTable'}
# Deliberately NOT whitelisted: $IsWindows/$IsLinux/$IsMacOS — automatic only
# in PowerShell Core. setup.ps1 targets 5.1+ (:27), where they are undefined
# under StrictMode, so a future `if ($IsWindows)` must FAIL this audit.
undefined = sorted(all_vars - assigned - param_vars - auto)
assert not undefined, f"undefined variables in {sys.argv[1]}: {undefined}"
PYEOF
}

@test "setup_ps1_keeps_no_config_src_logic" {
  # #491 AC4: the presence gate lives in setup.sh (single implementation —
  # the #474 launcher inherits it by delegation); no config logic may fork
  # back into the ps1.
  run grep -q 'config-src' "$SETUP_PS1"
  [ "$status" -ne 0 ]
  grep -q 'setup.sh' "$SETUP_PS1"
}
