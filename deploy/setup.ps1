# deploy/setup.ps1 — Windows thin launcher (#474)
#
# ONE interactive implementation lives in deploy/setup.sh (bash). This file is
# a thin Windows bootstrap: it translates PowerShell parameters and forwards
# EVERYTHING to setup.sh via Git-Bash or WSL — named flags through params,
# subcommands (install|update|rollback|peonping|plan|check-catalog) and
# other positionals verbatim via $args. It performs no deployment selection
# logic of its own — the #470 plan model, the #471 credential capture, the
# #473 picker, and the #470 D2 decline contract are inherited by delegation
# (this resolves the parity-bug class: #465, #466, #469, and the #490
# disclosure items).
#
# Requires: Git-Bash (Git for Windows) or WSL, plus node >= 20 for setup
#           (node >= 26.4 only for -Select's dashboard; below it the picker
#           falls back to linear prompts).
#           OpenCode CLI v2 — install with: npm install -g @opencode/cli
#           (the legacy opencode-ai npm package is the frozen v1 line; #499).
#           Coding-agent detection + pi/codex Z.AI key seeding (#573) are
#           inherited the same way — they live in setup.sh only.
# Previous native-PowerShell behavior is preserved through the flag mapping
# below; old flags keep working as aliases. setup.sh remains the single
# validator — values are forwarded, never re-checked here.

param(
    [switch]$Quick,
    [switch]$SkillsOnly,
    [switch]$DryRun,
    [switch]$Yes,
    [switch]$Verbose,
    [switch]$Update,
    [switch]$CheckUpdate,
    [switch]$Rollback,
    [string]$RollbackTarget,
    [switch]$ModelsOnly,
    [switch]$Migrate,
    [switch]$Mix,
    [switch]$Select,
    [switch]$CheckCatalog,
    [switch]$ListItems,
    [string]$SavePreset,
    [string]$Preset,
    [string]$EnablePack,
    [string]$Provider,
    [string]$SkillProfile,
    [string]$KeepBackups,
    [string]$ScheduleUpdate,
    [switch]$NoZipBackup,
    [switch]$Force,
    [switch]$Help,
    [switch]$Peonping,
    [switch]$EnableAutoUpdate,
    [switch]$DisableAutoUpdate
)

$ErrorActionPreference = "Stop"

# ── Bash discovery: Git-Bash first, then WSL ──
# (Runs BEFORE the node gate: the -Help fast-path below needs bash only, so
#  help must print on machines without node >= 26.4.)
$bashExe = $null
$cmd = Get-Command bash.exe -ErrorAction SilentlyContinue
if ($cmd) { $bashExe = $cmd.Source }
if (-not $bashExe) {
    foreach ($candidate in @(
        "$env:ProgramFiles\Git\bin\bash.exe",
        "$env:ProgramFiles\Git\usr\bin\bash.exe",
        "${env:ProgramFiles(x86)}\Git\bin\bash.exe",
        "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe"
    )) {
        if (Test-Path $candidate) { $bashExe = $candidate; break }
    }
}
$useWsl = $false
if (-not $bashExe) {
    if (Get-Command wsl.exe -ErrorAction SilentlyContinue) { $useWsl = $true }
    else {
        Write-Error "No bash host found. Install Git for Windows (provides bash.exe) or enable WSL, then re-run."
        exit 1
    }
}

$setupSh = Join-Path $PSScriptRoot "setup.sh"

# ── -Help fast-path (#571): print setup.sh's help and exit before the node
#    bootstrap — printing help requires bash, never the picker's node floor ──
if ($Help) {
    if ($useWsl) {
        $wslScript = (wsl.exe wslpath -a "$($setupSh -replace '\\', '/')" | ForEach-Object { $_.Trim() })
        wsl.exe bash "$wslScript" --help
        exit $LASTEXITCODE
    }
    & $bashExe $setupSh --help
    exit $LASTEXITCODE
}

# ── Bootstrap: node is required (setup.sh's resolver + installer CLI run on
#    node). The node >= 26.4 floor is the --select PICKER DASHBOARD's only
#    (#473; deploy/tui.mjs falls back to linear prompts below it), so it gates
#    -Select alone — non-picker runs work on any Node >= 20 (#673; aligns the
#    launcher with README and setup.sh, which never had a version gate). ──
if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    Write-Error "node is required. Install Node.js 20+ (https://nodejs.org) or 'nvm install 20'."
    exit 1
}
if ($Select) {
    $nodeVersion = [version]((node --version) -replace '^v', '')
    if ($nodeVersion -lt [version]"26.4") {
        Write-Error "node >= 26.4 is required for -Select's dashboard (found $nodeVersion). Install Node.js 26.4+ or re-run without -Select (the linear-prompt picker runs on any node)."
        exit 1
    }
}
# Route marker for setup.sh's preflight context banner (#673): the banner
# prints "ps1-forwarded" when set, so support triage sees the invocation path.
$env:OPENCODE_SETUP_VIA_PS1 = "1"

# ── Flag translation: ps1 params → setup.sh args (setup.sh validates values) ──
$forward = @()
if ($Quick)            { $forward += "--quick" }
if ($SkillsOnly)       { $forward += "--skills-only" }
if ($DryRun)           { $forward += "--dry-run" }
if ($Yes)              { $forward += "--yes" }
if ($Verbose)          { $forward += "--verbose" }
if ($Update)           { $forward += "--update" }
if ($CheckUpdate)      { $forward += "--check-update" }
if ($ModelsOnly)       { $forward += "--models-only" }
if ($Migrate)          { $forward += "--migrate" }
if ($Mix)              { $forward += "--mix" }
if ($Select)           { $forward += "--select" }
if ($CheckCatalog)     { $forward += "--check-catalog" }
if ($ListItems)        { $forward += "--list-items" }
if ($SavePreset)       { $forward += @("--save-preset", $SavePreset) }
if ($Preset)           { $forward += @("--preset", $Preset) }
if ($EnablePack)       { $forward += @("--enable-pack", $EnablePack) }
if ($Provider)         { $forward += @("--provider", $Provider) }
if ($SkillProfile)     { $forward += @("--skill-profile", $SkillProfile) }
if ($KeepBackups)      { $forward += @("--keep-backups", $KeepBackups) }
if ($ScheduleUpdate)   { $forward += @("--schedule-update", $ScheduleUpdate) }
if ($NoZipBackup)      { $forward += "--no-zip-backup" }
if ($Force)            { $forward += "--force" }
if ($Peonping)         { $forward += "--peonping" }
if ($EnableAutoUpdate) { $forward += "--enable-auto-update" }
if ($DisableAutoUpdate){ $forward += "--disable-auto-update" }
if ($Rollback -or $RollbackTarget) {
    # -or: `-RollbackTarget latest` alone still means rollback-latest —
    # dropping the target silently (review NOTE, #571) reproduced the exact
    # silent-drop class this ticket closes.
    if ($RollbackTarget) { $forward += @("--rollback", $RollbackTarget) }
    else { $forward += "--rollback" }
}

# Positional subcommands (install|update|rollback|peonping|plan|
# check-catalog) and their trailing args forward verbatim — setup.sh parses
# its own subcommand tokens, so no translation table is needed. Without this
# they were silently dropped and `.\setup.ps1 rollback latest` fell through
# to the interactive-menu default instead of rolling back (#571).
$forward += $args

# ── Forward everything to the bash implementation ──
if ($useWsl) {
    # Resolve the script's real path inside WSL (the caller's cwd is NOT the
    # script dir — README invokes from the repo root, the script lives in
    # deploy/).
    $wslScript = (wsl.exe wslpath -a "$($setupSh -replace '\\', '/')" | ForEach-Object { $_.Trim() })
    wsl.exe bash "$wslScript" @forward
    exit $LASTEXITCODE
}

& $bashExe $setupSh @forward
exit $LASTEXITCODE
