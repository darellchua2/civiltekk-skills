#!/bin/bash

################################################################################
# OpenCode Configuration Setup Script
#
# Copyright 2026 CivilTekk OpenCode & Claude Skills Contributors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
################################################################################
#
# Description: Automated setup for OpenCode configuration with proper error
#              handling, logging, and user experience enhancements.
#
# Usage: ./setup.sh [OPTIONS]
#
# SETUP MODES:
#   ./setup.sh                    Interactive menu (recommended for first-time setup)
#   ./setup.sh --quick            Quick setup (config + skills only, no dependencies)
#   ./setup.sh --skills-only      Skills deployment only (requires @opencode/cli installed)
#   ./setup.sh --update           Update OpenCode CLI to latest version
#   ./setup.sh --rollback [TARGET]  Restore ~/.config/opencode/ from a previous backup
#                                   TARGET: TIMESTAMP | VERSION | latest | list
#
# OPTIONS:
#   -h, --help          Show detailed help with all options and examples
#   -q, --quick         Quick setup: copy opencode.json + AGENTS.md + skills/ folder
#   -s, --skills-only   Skills-only: deploy skills/ folder (validates @opencode/cli installed)
#   -d, --dry-run       Preview all actions without making changes
#   -y, --yes           Auto-accept all prompts (non-interactive mode)
#   -v, --verbose       Enable detailed debug output
#   -u, --update        Update OpenCode CLI only (skip config/skills)
#   -D, --disable-auto-update   Disable automatic updates
#   -S, --schedule-update <schedule>  Set update schedule: daily|weekly|monthly|manual
#   -C, --check-update  Check for available updates without installing
#   --rollback [TARGET] Restore from previous backup (see SETUP MODES above)
#   --no-zip-backup     Skip zip archive creation after flat-file backup
#
# REQUIREMENTS (for full setup):
#   - curl (for downloading)
#   - Node.js v20+ and npm (for @opencode/cli and MCP servers)
#   - nvm recommended (for Node.js version management on macOS/Linux)
#   - ZAI_API_KEY (required for web-reader MCP server)
#
################################################################################

# Strict error handling
set -o pipefail  # Catch errors in pipes
set -o nounset   # Error on undefined variables
# Note: We don't use 'set -e' because we want custom error handling

################################################################################
# GLOBAL VARIABLES
################################################################################

# Resolve directories (setup.sh lives in deploy/, repo root is one level up).
# Symlink-aware: invoked via a PATH shim (~/.local/bin/opencode-setup, npm bin
# links), BASH_SOURCE is the shim, not this file — follow the link chain first
# or REPO_DIR resolves to the shim's parent and deploys copy nothing.
OC_SETUP_SELF="${BASH_SOURCE[0]}"
while [ -L "$OC_SETUP_SELF" ]; do
    OC_SETUP_LINK="$(readlink "$OC_SETUP_SELF")"
    case "$OC_SETUP_LINK" in
        /*) OC_SETUP_SELF="$OC_SETUP_LINK" ;;
        *) OC_SETUP_SELF="$(dirname "$OC_SETUP_SELF")/$OC_SETUP_LINK" ;;
    esac
done
SCRIPT_DIR="$(cd "$(dirname "$OC_SETUP_SELF")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Read version from VERSION file
VERSION_FILE="${REPO_DIR}/VERSION"
if [ -f "$VERSION_FILE" ]; then
    SCRIPT_VERSION=$(cat "$VERSION_FILE" | tr -d '[:space:]')
else
    SCRIPT_VERSION="2.0.0"
    log_warn "VERSION file not found, using default: ${SCRIPT_VERSION}"
fi

# This is a configuration template repository (no package.json required)
LOG_FILE="${HOME}/.opencode-setup.log"
CONFIG_DIR="${HOME}/.config/opencode"
# OpenCode v2 only discovers opencode.json / opencode.jsonc — never config.json.
CONFIG_FILE="${CONFIG_DIR}/opencode.json"
LEGACY_CONFIG_FILE="${CONFIG_DIR}/config.json"
SKILLS_DIR="${CONFIG_DIR}/skills"
AGENTS_SRC_DIR="${REPO_DIR}/agents"
AGENTS_DEST_DIR="${CONFIG_DIR}/agents"
# Repo-owned plugins (auto-loaded by opencode from this dir). Mirrors the
# agents/skills deploy pattern. Currently: opencode-skill-counter-sync.
PLUGINS_SRC_DIR="${REPO_DIR}/plugins"
PLUGINS_DEST_DIR="${CONFIG_DIR}/plugins"
BACKUP_DIR="${HOME}/.opencode-backup-$(date +%Y%m%d_%H%M%S)"
LAST_UPDATE_CHECK="${CONFIG_DIR}/.last-update-check"
UPDATE_LOG="${CONFIG_DIR}/update.log"

# v2.0 model resolution (tier-based, provider-agnostic)
DEPLOY_DIR="${REPO_DIR}/deploy"
INSTALLER_DIR="${REPO_DIR}/installer"
RESOLVER_SCRIPT="${INSTALLER_DIR}/resolve-models.mjs"
MERGE_PACKS_SCRIPT="${DEPLOY_DIR}/merge-packs.mjs"
PACKS_DIR="${DEPLOY_DIR}/packs"
APPLY_SKILL_PROFILE_SCRIPT="${DEPLOY_DIR}/apply-skill-profile.mjs"
SKILL_PROFILES_FILE="${DEPLOY_DIR}/skill-profiles.json"
TUI_SCRIPT="${DEPLOY_DIR}/tui.mjs"
AGENT_TIERS="${INSTALLER_DIR}/agent-tiers.json"
MODELS_DEFAULT_MAP="${INSTALLER_DIR}/models.default.json"
PROVIDER_PRESETS="${INSTALLER_DIR}/provider-presets.json"
# Global user overrides (~/.config/opencode/)
USER_MODELS_MAP="${CONFIG_DIR}/models.json"
SELECT_PLAN_FILE="${CONFIG_DIR}/deploy-plan.json"
USER_OVERRIDES="${CONFIG_DIR}/agent-overrides.json"
# Project-local overrides (repo root .opencode/)
PROJECT_MODELS_MAP="${REPO_DIR}/.opencode/models.json"
PROJECT_OVERRIDES="${REPO_DIR}/.opencode/agent-overrides.json"
# Resolver state + migration marker
RESOLVED_SIDECAR="${CONFIG_DIR}/.resolved-models.json"
CONFIG_VERSION_FILE="${CONFIG_DIR}/.config-version"
SCHEMA_VERSION="2.0"
SOURCE_CONFIG="${REPO_DIR}/deploy/opencode.json"
# Where dry-run stages complete resolved files (mirrors what would land in ~/.config)
DRY_RUN_PREVIEW_DIR="${CONFIG_DIR}/.dry-run-preview"

################################################################################
# PLATFORM AND SHELL DETECTION
################################################################################

# Detect operating system
detect_platform() {
    case "$(uname -s)" in
        Darwin)
            echo "macOS"
            ;;
        Linux*)
            # Check if running under WSL
            if grep -q Microsoft /proc/version 2>/dev/null; then
                echo "Windows-WSL"
            else
                echo "Linux"
            fi
            ;;
        CYGWIN*|MINGW*|MSYS*)
            echo "Windows"
            ;;
        MINGW64_NT-*)
            # Git Bash on Windows
            echo "Windows-GitBash"
            ;;
        *)
            # Check for Windows environment variables
            # ${OS:-} guards against nounset abort when $OS is not exported
            if [ -n "${OS:-}" ] && [[ "$OS" == "Windows_NT" ]]; then
                echo "Windows"
            else
                echo "Unknown"
            fi
            ;;
    esac
}

DETECTED_OS=$(detect_platform)
OS_VERSION=$(sw_vers 2>/dev/null || uname -r)

# Check if a command exists (defined early, used by detect_package_manager)
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Detect package manager and distribution based on platform
detect_package_manager() {
    local platform="$1"

    case "$platform" in
        macOS)
            # Check for Homebrew
            if command_exists brew; then
                echo "brew"
            else
                echo "none"
            fi
            ;;
        Linux*)
            # Detect distribution and package manager
            if [ -f /etc/debian_version ]; then
                # Debian-based: Ubuntu, Debian, Linux Mint, etc.
                local distro_id
                distro_id=$(grep "^ID=" /etc/os-release 2>/dev/null | cut -d= -f2 | cut -d\" -f1)
                echo "apt:${distro_id}"
            elif [ -f /etc/redhat-release ]; then
                # RHEL-based: Fedora, RHEL, CentOS, Rocky, etc.
                local distro_id
                distro_id=$(grep "^ID=" /etc/os-release 2>/dev/null | cut -d= -f2 | cut -d\" -f1)
                echo "dnf:${distro_id}"
            elif [ -f /etc/arch-release ]; then
                # Arch-based: Arch, Manjaro, EndeavourOS, etc.
                local distro_id
                distro_id=$(grep "^ID=" /etc/os-release 2>/dev/null | cut -d= -f2 | cut -d\" -f1)
                echo "pacman:${distro_id}"
            elif [ -f /etc/SUSE-brand ] || [ -f /etc/SUSE-release ]; then
                # SUSE-based: openSUSE, SUSE Linux
                echo "zypper:opensuse"
            elif command_exists zypper; then
                # Check for zypper as fallback
                echo "zypper:unknown"
            elif [ -f /etc/alpine-release ]; then
                # Alpine Linux
                echo "apk:alpine"
            elif command_exists pacman; then
                # Fallback to pacman
                echo "pacman:unknown"
            elif command_exists apk; then
                # Fallback to apk
                echo "apk:unknown"
            elif command_exists dnf; then
                # Fallback to dnf
                echo "dnf:unknown"
            elif command_exists apt-get; then
                # Fallback to apt
                echo "apt:unknown"
            else
                echo "none"
            fi
            ;;
        Windows*|Windows-GitBash)
            # Check for winget
            if command_exists winget; then
                echo "winget"
            # Check for chocolatey
            elif command_exists choco; then
                echo "chocolatey"
            else
                echo "none"
            fi
            ;;
        *)
            echo "none"
            ;;
    esac
}

PACKAGE_MANAGER=$(detect_package_manager "$DETECTED_OS")

# Extract distribution name from package manager
get_distribution_name() {
    local pkg_manager="$1"
    case "$pkg_manager" in
        apt:*|dnf:*|pacman:*)
            echo "${pkg_manager#*:}"
            ;;
        zypper:*)
            echo "opensuse"
            ;;
        apk:*)
            echo "alpine"
            ;;
        brew|winget|chocolatey)
            echo "$pkg_manager"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

DISTRIBUTION_NAME=$(get_distribution_name "$PACKAGE_MANAGER")

# Detect shell (bash, zsh, or powershell)
detect_shell() {
    if [ -n "${ZSH_VERSION:-}" ]; then
        echo "zsh"
    elif [ -n "$BASH_VERSION" ]; then
        echo "bash"
    elif [ -n "$PSVersionTable" ]; then
        echo "powershell"
    else
        # Fallback: check $0
        case "$0" in
            *zsh*)
                echo "zsh"
                ;;
            *bash*)
                echo "bash"
                ;;
            *)
                echo "bash"
                ;;
        esac
    fi
}

DETECTED_SHELL=$(detect_shell)

# Determine shell config file based on OS and shell
determine_shell_config() {
    local shell="$1"
    local os="$2"

    case "${os}:${shell}" in
        macOS:zsh)
            echo "${HOME}/.zshrc"
            ;;
        macOS:bash)
            if [ -f "${HOME}/.bash_profile" ]; then
                echo "${HOME}/.bash_profile"
            else
                echo "${HOME}/.bashrc"
            fi
            ;;
        Linux:bash|Linux:*)
            echo "${HOME}/.bashrc"
            ;;
        Windows:powershell)
            echo "${PROFILE}"
            ;;
        *)
            # Default to bashrc
            echo "${HOME}/.bashrc"
            ;;
    esac
}

SHELL_CONFIG_FILE=$(determine_shell_config "$DETECTED_SHELL" "$DETECTED_OS")

# Flags
QUICK_SETUP=false
SKILLS_ONLY=false
DRY_RUN=false
AUTO_ACCEPT=false
VERBOSE=false
SKIP_CONFIG_COPY=false
UPDATE_ONLY=false
PEONPING_ONLY=false       # --peonping (sound-notification installer only)
ENABLE_AUTO_UPDATE=false
UPDATE_SCHEDULE="manual"
CHECK_UPDATE_ONLY=false
CHECK_CATALOG_ONLY=false    # --check-catalog (models.dev drift check)
SELECT_ITEMS=false          # --select (per-item deploy picker)
LIST_ITEMS=false            # --list-items (registry catalog dump)
SAVE_PRESET_NAME=""         # --save-preset <name>
LOAD_PRESET_NAME=""         # --preset <name>
KEEP_BACKUPS=5

# Rollback mode (set by --rollback)
ROLLBACK_MODE=false
ROLLBACK_TARGET=""
# Zip backup toggle (default on; --no-zip-backup disables)
ZIP_BACKUP=true
# v2.0 model-resolution flags
PROVIDER=""              # --provider <preset>
MODELS_ONLY=false        # --models-only (provider + resolve only)
FORCE_RESOLVE=false      # --force (ignore preserve-edits)
MIGRATE_ONLY=false       # --migrate (migration + resolve only)
MIX_MODE=false           # --mix (per-category provider/model editor)
ENABLE_PACK=""           # --enable-pack <csv> (provider packs: markitdown,nextjs,docling,chrome-devtools,playwright,alpha-vantage,nanobanana)
SKILL_PROFILE="lean"     # --skill-profile lean|full (default lean: primary-visible skills per deploy/skill-profiles.json; full = the shipped opencode.json skill set)

# API Keys (initialize to empty to avoid unbound variable errors)
# Capture from environment if they exist
GITHUB_PAT=""
ZAI_API_KEY="${ZAI_API_KEY:-}"


# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

################################################################################
# LOGGING FUNCTIONS
################################################################################

# Initialize logging
init_logging() {
    local log_dir=$(dirname "$LOG_FILE")
    mkdir -p "$log_dir" 2>/dev/null || true

    if [ ! -f "$LOG_FILE" ]; then
        touch "$LOG_FILE" 2>/dev/null || true
    fi

    log "INFO" "=== OpenCode Setup Started at $(date) ==="
    log "INFO" "Script version: ${SCRIPT_VERSION}"
    log "INFO" "User: ${USER:-${LOGNAME:-unknown}}"
    log "INFO" "Working directory: ${PWD}"
}

# Log message with level
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Log to file
    if [ -w "$LOG_FILE" ] 2>/dev/null; then
        echo "[${timestamp}] [${level}] ${message}" >> "$LOG_FILE"
    fi

    # Print to stderr for errors, stdout for everything else
    if [ "$level" = "ERROR" ]; then
        echo -e "${RED}[${level}]${NC} ${message}" >&2
    elif [ "$level" = "WARNING" ]; then
        echo -e "${YELLOW}[${level}]${NC} ${message}"
    elif [ "$level" = "SUCCESS" ]; then
        echo -e "${GREEN}[${level}]${NC} ${message}"
    elif [ "$VERBOSE" = true ] || [ "$level" != "DEBUG" ]; then
        echo "[${level}] ${message}"
    fi
}

log_debug() { log "DEBUG" "$@"; }
log_info() { log "INFO" "$@"; }
log_warn() { log "WARNING" "$@"; }
log_error() { log "ERROR" "$@"; }
log_success() { log "SUCCESS" "$@"; }

# Count active SKILL.md files in a directory. Used by banners/status listings
# so skill counts can never drift from disk. BT-157.
count_skills() {
    [ -d "$1" ] || { echo 0; return; }
    find "$1" -type f -name "SKILL.md" 2>/dev/null | wc -l
}

count_agents() {
    [ -d "$1" ] || { echo 0; return; }
    find "$1" -maxdepth 1 -type f -name "*.md" 2>/dev/null | wc -l
}

# Auto-derive per-category counts from skill frontmatter (category: field).
# Drift-proof replacement for the hand-maintained listings.
# Prints "Category (N)" lines sorted by count desc. BT-157.
print_skill_categories() {
    [ -d "$1" ] || return
    find "$1" -type f -name "SKILL.md" -exec grep -hE '^[[:space:]]*category:' {} + 2>/dev/null \
        | sed -E 's/^[[:space:]]*category:[[:space:]]*//' \
        | sort | uniq -c | sort -rn \
        | while read -r n c; do [ -n "$c" ] && echo "    - ${c} (${n})"; done
}

################################################################################
# ERROR HANDLING
################################################################################

# Global error handler
error_handler() {
    local line_number=$1
    local error_code=$2
    log_error "Script failed at line ${line_number} with exit code ${error_code}"

    # Print the call stack so the user can see WHERE the failure happened.
    # FUNCNAME / BASH_LINENO / BASH_SOURCE are parallel arrays — same length,
    # indexed from the innermost (current) function outward.
    if [ "${#FUNCNAME[@]}" -gt 1 ]; then
        log_error "Call stack:"
        local i
        for ((i = 1; i < ${#FUNCNAME[@]}; i++)); do
            log_error "  ${BASH_SOURCE[$i]:-setup.sh}:${BASH_LINENO[$((i-1))]:-?}  ${FUNCNAME[$i]}"
        done
    fi

    log_error "Check ${LOG_FILE} for details"

    # Suggest recovery actions
    echo ""
    echo "=== Recovery Suggestions ==="
    echo "1. Check the log file: ${LOG_FILE}"
    echo "2. Restore from backup: ${BACKUP_DIR}"
    echo "3. Try running with --verbose flag for more details"
    echo "4. Check network connectivity and try again"
    echo ""

    cleanup_on_error
    exit 1
}

# Cleanup on error
cleanup_on_error() {
    log_warn "Performing cleanup..."

    # Remove partial installations
    if [ -d "${BACKUP_DIR}" ]; then
        log_info "Backup preserved at: ${BACKUP_DIR}"
    fi
}

# Trap errors — capture the actual failing line via BASH_LINENO, not the trap
# definition site. Without this, every error reports the trap's own line number.
trap 'error_handler "${BASH_LINENO[0]:-0}" "$?"' ERR

# Trap interruption
trap 'echo ""; log_warn "Setup interrupted by user"; exit 130' INT

################################################################################
# UTILITY FUNCTIONS
################################################################################

# Show usage information
show_help() {
    cat << EOF
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                    OpenCode Configuration Setup v${SCRIPT_VERSION}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

USAGE:
    ./setup.sh [OPTIONS]

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                            SETUP MODES
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  MODE                    WHAT IT DOES                          WHEN TO USE
  ─────────────────────────────────────────────────────────────────────────────
  Interactive (default)   Full setup with guided prompts       First-time setup
                           1. GitHub CLI check
                           2. Z.AI API key setup
                          3. nvm installation/update
                          4. Node.js v24 installation
                          5. @opencode/cli installation
                          6. opencode.json deployment
                          7. skills/ deployment
                          8. Environment variable persistence

  --quick                 Copy config files only                Already have
                          1. opencode.json → ~/.config/opencode/  dependencies installed
                          2. AGENTS.md → ~/.config/opencode/
                          3. skills/* → ~/.config/opencode/skills/
                          (Skips all dependency checks)

  --skills-only           Deploy skills only                    @opencode/cli already
                          1. Validates @opencode/cli installed  installed, just need
                          2. Copies skills/* to config dir      updated skills

  --update                Update @opencode/cli only             Keep CLI current
                          (No config changes)

  --peonping              Install PeonPing sound notifications  Headless /
                          (menu option 5 as a flag)             scripted installs

  SUBCOMMANDS (aliases over the flags):
    install | update | rollback | peonping | plan | check-catalog

  --select                Pick skills/agents/packs/plugins per item   Custom
                          (interactive picker; emits a deploy plan)  deploys

  --check-catalog         Compare provider-models.json with the live  Model-pin
                          models.dev catalog (warnings only)     maintenance

  --rollback [TARGET]     Restore from a previous backup         Undo a bad deploy
                          TARGET:
                            (omitted)   Interactive picker
                            TIMESTAMP   e.g. 20260719_070926
                            VERSION     e.g. 1.76.0 (closest backup <= tag)
                            latest      Most recent backup
                            list        List available backups and exit
                          Safety: creates a pre-rollback backup first
                          Combine with --yes to skip confirmation prompt

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                            OPTIONS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  SETUP OPTIONS:
    -q, --quick           Quick setup mode (config + skills only, no dependencies)
    -s, --skills-only     Skills-only deployment mode
    -u, --update          Update OpenCode CLI to latest version
    -P, --peonping        Install PeonPing sound notifications only
    --select              Pick deploy items interactively (per-item deploy)
    --list-items          Dump the deploy item catalog (skills/agents/…)
    --save-preset <name>  Save models.json + deploy-plan.json as a preset
    --preset <name>       Restore a saved preset (models.json; deploy-plan.json
                          is only consumed together with --select)
    --check-catalog       Warn if provider model pins drifted from models.dev
    --rollback [TARGET]   Restore from previous backup (see SETUP MODES above)

  UPDATE MANAGEMENT:
    -A, --enable-auto-update      (removed) schedule updates externally, e.g. cron
    -D, --disable-auto-update     Disable automatic updates
    -S, --schedule-update <schedule>  Set update check frequency:
                                      daily, weekly, monthly, manual (default)
    -C, --check-update    Check for updates without installing

  UTILITY OPTIONS:
    -h, --help            Show this detailed help message
    -d, --dry-run         Preview all actions without making changes
    -y, --yes             Auto-accept all prompts (non-interactive)
    -v, --verbose         Enable detailed debug logging
    -k, --keep-backups <N>  Keep only N most recent backups (default: 5)
                            0 = delete all old backups, negative = keep all
    --no-zip-backup       Skip zip archive creation (zip is created by default
                            alongside the flat-file backup for portability)

  MODEL RESOLUTION (v2.0):
    --provider <name>     Non-interactive provider preset: zai|anthropic|openai|
                          openrouter|local-llm|vllm|ollama (writes ~/.config/opencode/models.json)
    --models-only         Provider selection + model resolution only (no other setup)
    --migrate             Run v1.x -> v2.0 migration + model resolution only
    --force               Re-resolve all agents (ignore preserved hand-edits)
    --mix                 Per-category provider/model editor (mix providers across
                          primary/reasoning/fast/docs/vision, e.g. vision on OpenAI)

  PROVIDER PACKS (deploy-time MCP toggle):
    --enable-pack <csv>   Enable provider pack(s) — flips mcp.servers.<server>.disabled
                          and appends v2 permissions-array allow rules for the
                          named packs. Available
                          packs: markitdown, nextjs, docling, chrome-devtools, playwright, alpha-vantage, nanobanana
                          (comma-separated, e.g. --enable-pack markitdown,docling).
                          No-op if omitted; default state of every pack is OFF.

  SKILL PROFILE (deploy-time primary visibility):
    --skill-profile <p>   lean (default) | full. lean rewrites the DEPLOYED
                           config's skill permissions (permissions array) to the
                           lean-profile skill set + "*": "deny" (subagents
                           unaffected — they self-scope via frontmatter allows);
                           full deploys the shipped allowlist verbatim.


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                            EXAMPLES
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  First-time setup:
    ./setup.sh                      # Interactive full setup with menu
    ./setup.sh -y                   # Full setup, auto-accept all prompts

  Quick deployment:
    ./setup.sh --quick              # Copy config and skills (no deps)
    ./setup.sh --skills-only        # Deploy skills only
    ./setup.sh -y -q                # Quick setup, non-interactive

  Provider packs (deploy-time MCP toggle):
    ./setup.sh --enable-pack markitdown           # Enable the markitdown MCP server
    ./setup.sh --enable-pack markitdown,docling   # Enable multiple packs
    ./setup.sh --quick --enable-pack markitdown   # Combine with other modes

  Model resolution + skill profile:
    ./setup.sh --provider anthropic -y            # Deploy with Anthropic models
    ./setup.sh --mix                              # Mix providers per tier (interactive)
    ./setup.sh --models-only --force              # Re-resolve models only
    ./setup.sh --skill-profile full               # Primary sees all shipped skills

  Common combinations (headless / CI):
    ./setup.sh -y -q --provider zai                  # Quick deploy, Z.AI, no prompts
    ./setup.sh -y --enable-pack markitdown,nextjs    # Defaults + packs, non-interactive
    ./setup.sh -y --provider openai --enable-pack markitdown --skill-profile lean
    ./setup.sh --dry-run -y --enable-pack docling   # Preview a combo before running

  Preview and update:
    ./setup.sh --dry-run            # Preview what would be done
    ./setup.sh --update             # Update @opencode/cli CLI
    ./setup.sh -C                   # Check for available updates

  Auto-update management:
    ./setup.sh -A                   # Enable auto-updates (manual schedule)
    ./setup.sh -A -S daily          # Enable with daily checks
    ./setup.sh -A -S weekly         # Enable with weekly checks
    ./setup.sh -D                   # Disable auto-updates

  Backup and rollback:
    ./setup.sh --rollback list      # List available backups (timestamp + size + zip)
    ./setup.sh --rollback latest    # Restore from most recent backup
    ./setup.sh --rollback 20260719_070926  # Restore from specific timestamp
    ./setup.sh --rollback 1.76.0    # Restore from backup closest to version 1.76.0
    ./setup.sh --rollback           # Interactive picker
    ./setup.sh --rollback latest -y # Restore without confirmation prompt
    ./setup.sh --rollback latest -d # Dry-run: preview restore, change nothing
    ./setup.sh --no-zip-backup      # Deploy without creating zip archive

  Note: Every deploy creates BOTH a flat-file backup (~/.opencode-backup-TIMESTAMP/)
        AND a zip archive (~/.opencode-backup-TIMESTAMP.zip) for portability.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                         CONFIGURED FEATURES
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

   CODING AGENT DETECTION (#573):
    Setup probes for installed coding agents (opencode, pi, codex, claude,
    kimi, kilo) and prints a found/missing table in the banner + summary.
    With pi/codex present and a Z.AI key captured, it seeds a zai provider:
      pi    -> ~/.pi/agent/models.json (apiKey via $ZAI_API_KEY interpolation)
      codex -> ~/.codex/config.toml    (env_key; activate: codex --profile zai)
    After a NEW key is seeded the opencode background service is restarted
    (announced first) so {env:} MCP substitution picks up the key; unchanged
    credentials skip the restart entirely. (setup.ps1 inherits this via
    delegation to setup.sh.)

   AGENTS ($(count_agents "${REPO_DIR}/agents")):
    build (default)      Full-featured coding agent with all tools
    plan                 Planning agent (read-only, edits need approval)
    explore              Fast codebase exploration and analysis
    general              General-purpose multi-step research
    scout                External docs and dependency research
    explorer             Codebase exploration and analysis (subagent)
    code-review          Code review with SOLID/clean-code analysis
    language-reviewer    Multi-language code review (Python, TS/JS, Go, Rust, Java)
    testing              Test generation with framework detection
    pr-workflow          PR creation with quality gates and JIRA integration
    linting              Code linting with auto-fix for Python/JS/TS
    repo-ops-specialist  Git repository operations (release, branch protection, labels)
    architecture-review  Architecture review with clean architecture principles
    tdd                  Test Driven Development workflow guidance
    coverage             Test coverage reporting and badges
    documentation        Docstring generation (PEP 257, JSDoc, Javadoc)
    loop-operator        Autonomous loop execution with self-correction
    pptx-specialist      PowerPoint orchestration (routes to generate-slide/template-modifier)
    docx-creation        Word document creation and manipulation
    xlsx-specialist      Spreadsheet creation and analysis
    image-analyzer       Images/screenshots to code, OCR, error diagnosis
    error-resolver       Error diagnosis with stack trace analysis
    opencode-tooling     OpenCode config creation and maintenance
    startup-founder      Startup founder business operations agent
    startup-ceo          Investor-ready pitch decks and board updates
    office-document      Office document specialist: Word, PowerPoint, Excel
     nextjs-specialist  Next.js scaffolding + runtime MCP diagnosis
    opentofu-explorer    OpenTofu/Terraform infrastructure management
    cad-specialist       CAD, robotics, hardware design orchestration
    discovery-specialist Customer-facing discovery: Vision docs + wireframes
    requirements-specialist  BRD + SRS drafting (BABOK/IIBA + IEEE 830)
    technical-design-specialist  Technical design + ADRs (engineering 'how' stage)

    Usage: opencode --agent build "implement auth feature"
           opencode --agent explore "find all API routes"

  MCP SERVERS:
    Auto-start (enabled by default):
      codegraph           Pre-indexed code knowledge graph (100% local)
      zai-web-reader      Web page content extraction (remote, needs ZAI_API_KEY)
      zai-web-search      Web search with cited results (remote, needs ZAI_API_KEY)

    Available but disabled (opt-in — enable per-project via
    opencode.json or opencode-repo-setup-skill):
      atlassian           JIRA and Confluence integration (first use opens browser OAuth)
      next-devtools      Next.js DevTools integration
      markitdown         Document-to-Markdown (upstream markitdown-mcp, stdio, plugins off)
      docling            Layout-aware document extraction (heavy ~3-4 GB)
      chrome-devtools    Live Chrome automation: perf traces, network/console, Lighthouse, heap snapshots
                          (privacy-hardened: telemetry + CrUX OFF; throwaway profile; enable via --enable-pack chrome-devtools)
      playwright         Logged-in web automation via accessibility snapshots (Microsoft, Apache-2.0)
      alpha-vantage      Market/macro/commodities data with cited figures (remote; needs ALPHA_VANTAGE_API_KEY)
      nanobanana         Google Nano Banana image generation: 4K, multi-reference editing (needs GEMINI_API_KEY)

    SKILLS ($(count_skills "${REPO_DIR}/skills")):

$(print_skill_categories "${REPO_DIR}/skills")

     Run 'opencode --list-skills' for detailed descriptions
    Run 'opencode --skill <name> "prompt"' to invoke a skill

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                           REQUIREMENTS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Required (for full setup):
    curl                  For downloading files
    Node.js v20+          For @opencode/cli and MCP servers
    npm                   Comes with Node.js

  Recommended:
    nvm                   Node Version Manager (macOS/Linux)
    git                   For version control integration

  API Keys (prompted during setup):
     ZAI_API_KEY           Required for: web-reader, web-search
                           Get from: https://z.ai

   GitHub Auth:
     GitHub CLI (gh)      Recommended for GitHub MCP features
                           Install: https://cli.github.com/
                           Or use OAuth: opencode mcp auth github

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                            FILE LOCATIONS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Configuration:        ~/.config/opencode/opencode.json
  Agents config:        ~/.config/opencode/AGENTS.md
  Skills directory:     ~/.config/opencode/skills/
  Learnings directory:  ~/.config/opencode/learnings/
  Setup log:            ~/.opencode-setup.log
  Update log:           ~/.config/opencode/update.log
  Backups:              ~/.opencode-backup-YYYYMMDD_HHMMSS/        (flat-file)
                        ~/.opencode-backup-YYYYMMDD_HHMMSS.zip     (zip archive)
                         Retention: 5 most recent (configurable with --keep-backups)
                         Rollback:  ./setup.sh --rollback list

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

For more information: https://opencode.ai
Report issues: https://github.com/darellchua2/civiltekk-opencode-claude-skills/issues

EOF
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -q|--quick)
                QUICK_SETUP=true
                shift
                ;;
            -s|--skills-only)
                SKILLS_ONLY=true
                shift
                ;;
            -d|--dry-run)
                DRY_RUN=true
                log_warn "Dry-run mode enabled - no changes will be made"
                shift
                ;;
            -y|--yes)
                AUTO_ACCEPT=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
             -u|--update)
                UPDATE_ONLY=true
                shift
                ;;
            -A|--enable-auto-update)
                # Auto-update was removed (#474): accepted no-op so existing
                # scripts keep working.
                ENABLE_AUTO_UPDATE=false
                echo "Auto-update has been removed - schedule updates externally, e.g. cron: ./setup.sh --update"
                shift
                ;;
            -D|--disable-auto-update)
                ENABLE_AUTO_UPDATE=false
                shift
                ;;
            -S|--schedule-update)
                if [ -z "$2" ]; then
                    log_error "--schedule-update requires an argument (daily, weekly, monthly, manual)"
                    exit 1
                fi
                case "$2" in
                    daily|weekly|monthly|manual)
                        # Removed with auto-update (#474): accepted no-op with a hint.
                        UPDATE_SCHEDULE="$2"
                        echo "Auto-update has been removed - this flag is accepted but does nothing."
                        ;;
                    *)
                        log_error "Invalid --schedule-update value: '$2' (allowed: daily, weekly, monthly, manual)"
                        exit 1
                        ;;
                esac
                shift 2
                ;;
            -C|--check-update)
                CHECK_UPDATE_ONLY=true
                shift
                ;;
            --check-catalog)
                CHECK_CATALOG_ONLY=true
                shift
                ;;
            --select)
                SELECT_ITEMS=true
                shift
                ;;
            -P|--peonping)
                PEONPING_ONLY=true
                shift
                ;;
            -k|--keep-backups)
                if [ -n "$2" ] && [[ "$2" =~ ^-?[0-9]+$ ]]; then
                    KEEP_BACKUPS="$2"
                else
                    log_error "--keep-backups requires a numeric argument"
                    exit 1
                fi
                shift 2
                ;;
            --rollback)
                ROLLBACK_MODE=true
                # Optional positional: TIMESTAMP | VERSION | latest | list
                if [ -n "${2:-}" ] && [[ "$2" != --* ]]; then
                    ROLLBACK_TARGET="$2"
                    shift 2
                else
                    shift
                fi
                ;;
            --no-zip-backup)
                ZIP_BACKUP=false
                shift
                ;;
            --provider)
                if [ -n "$2" ]; then
                    PROVIDER="$2"
                else
                    log_error "--provider requires an argument (zai|anthropic|openai|openrouter|local-llm|vllm|ollama)"
                    exit 1
                fi
                shift 2
                ;;
            --models-only)
                MODELS_ONLY=true
                shift
                ;;
            --force)
                FORCE_RESOLVE=true
                shift
                ;;
            --migrate)
                MIGRATE_ONLY=true
                shift
                ;;
            --mix)
                MIX_MODE=true
                shift
                ;;
            --enable-pack)
                # Accept any value including "" (empty = no-op, handled by
                # merge-packs.mjs). Only error if no following token at all.
                if [ $# -lt 2 ]; then
                    log_error "--enable-pack requires an argument (csv: markitdown,nextjs,docling,chrome-devtools,playwright,alpha-vantage,nanobanana)"
                    exit 1
                fi
                ENABLE_PACK="$2"
                shift 2
                ;;
            --skill-profile)
                if [ -n "$2" ] && { [ "$2" = "lean" ] || [ "$2" = "full" ]; }; then
                    SKILL_PROFILE="$2"
                else
                    log_error "--skill-profile requires an argument (lean|full)"
                    exit 1
                fi
                shift 2
                ;;
            --list-items)
                LIST_ITEMS=true
                shift
                ;;
            --save-preset)
                if [ $# -lt 2 ] || [ -z "$2" ]; then
                    log_error "--save-preset requires a name"
                    exit 1
                fi
                SAVE_PRESET_NAME="$2"
                shift 2
                ;;
            --preset)
                if [ $# -lt 2 ] || [ -z "$2" ]; then
                    log_error "--preset requires a name"
                    exit 1
                fi
                LOAD_PRESET_NAME="$2"
                shift 2
                ;;
            install)
                shift
                ;;
            update)
                UPDATE_ONLY=true
                shift
                ;;
            rollback)
                ROLLBACK_MODE=true
                shift
                if [ $# -gt 0 ] && [[ "$1" != -* ]]; then
                    ROLLBACK_TARGET="$1"
                    shift
                fi
                ;;
            peonping)
                PEONPING_ONLY=true
                shift
                ;;
            plan)
                SELECT_ITEMS=true
                shift
                ;;
            check-catalog)
                CHECK_CATALOG_ONLY=true
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Use -h or --help for usage information"
                exit 1
                ;;
        esac
    done
}

# Mode exclusivity (#466): the early-exit modes are mutually exclusive, and
# --enable-pack only makes sense for modes that deploy config content (the
# pack merger runs from deploy_agents). Previously contradictory flags were
# silently ignored, e.g. `--update --enable-pack markitdown` deployed no pack.
# NOTE: per-flag semantic validation (e.g. --provider with --update) lands
# with the plan model (#470), not here.
validate_mode_conflicts() {
    local modes=()
    [ "$QUICK_SETUP" = true ] && modes+=("--quick")
    [ "$SKILLS_ONLY" = true ] && modes+=("--skills-only")
    [ "$UPDATE_ONLY" = true ] && modes+=("--update")
    [ "$MODELS_ONLY" = true ] && modes+=("--models-only")
    [ "$MIGRATE_ONLY" = true ] && modes+=("--migrate")
    [ "$ROLLBACK_MODE" = true ] && modes+=("--rollback")
    [ "$CHECK_UPDATE_ONLY" = true ] && modes+=("--check-update")
    [ "$CHECK_CATALOG_ONLY" = true ] && modes+=("--check-catalog")
    [ "$PEONPING_ONLY" = true ] && modes+=("--peonping")
    [ "$SELECT_ITEMS" = true ] && modes+=("--select")
    [ "$LIST_ITEMS" = true ] && modes+=("--list-items")
    [ -n "$SAVE_PRESET_NAME" ] && modes+=("--save-preset")
    if [ "${#modes[@]}" -gt 1 ]; then
        log_error "Mutually exclusive modes combined: ${modes[*]}. Choose one."
        exit 1
    fi
    if [ -n "$ENABLE_PACK" ]; then
        local packless=()
        [ "$UPDATE_ONLY" = true ] && packless+=("--update")
        [ "$MODELS_ONLY" = true ] && packless+=("--models-only")
        [ "$MIGRATE_ONLY" = true ] && packless+=("--migrate")
        [ "$ROLLBACK_MODE" = true ] && packless+=("--rollback")
        [ "$CHECK_UPDATE_ONLY" = true ] && packless+=("--check-update")
        [ "$CHECK_CATALOG_ONLY" = true ] && packless+=("--check-catalog")
        [ "$PEONPING_ONLY" = true ] && packless+=("--peonping")
        if [ "${#packless[@]}" -gt 0 ]; then
            log_error "--enable-pack has no effect with ${packless[*]} (packs merge into the deployed config, which these modes never write). Drop --enable-pack or use a config-deploy mode."
            exit 1
        fi
    fi
}

# Validate --enable-pack <csv> against deploy/packs/pack-<name>.json.
# Fail fast (exit 1) on any unknown pack before any config work begins, so the
# non-zero exit isn't swallowed by the `deploy_agents || true` calls in main.
validate_enable_pack() {
    local packs_dir="${PACKS_DIR:-${DEPLOY_DIR}/packs}"
    if [ ! -d "$packs_dir" ]; then
        log_error "--enable-pack: packs directory not found: ${packs_dir}"
        exit 1
    fi
    # Empty/whitespace → no-op (handled gracefully downstream), don't error.
    local requested
    requested=$(echo "$ENABLE_PACK" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -v '^$' || true)
    if [ -z "$requested" ]; then
        return 0
    fi
    local available
    available=$(cd "$packs_dir" && ls pack-*.json 2>/dev/null | sed 's/^pack-//;s/\.json$//' | sort | tr '\n' ' ')
    local unknown=""
    while IFS= read -r name; do
        [ -z "$name" ] && continue
        if [ ! -f "${packs_dir}/pack-${name}.json" ]; then
            unknown="${unknown} ${name}"
        fi
    done <<< "$requested"
    if [ -n "$unknown" ]; then
        log_error "--enable-pack: unknown pack(s):${unknown}"
        echo "  Available packs: ${available:-<none>}" >&2
        echo "  See deploy/packs/ for the pack partials." >&2
        exit 1
    fi
    log_info "Provider packs requested: $(echo "$requested" | tr '\n' ',' | sed 's/,$//')"
}

# Safe execution with dry-run support.
# Supports two calling conventions:
#   - Multi-arg (preferred):  run_cmd cp "$src" "$dest"      # preserves spaces
#   - Single-string (legacy): run_cmd "cp $src $dest"        # eval'd for back-comat
# Prefer the multi-arg form in new code — it survives paths with spaces, quotes,
# and glob chars without an eval injection risk.
run_cmd() {
    log_debug "Executing: $*"

    if [ "$DRY_RUN" = true ]; then
        echo "[DRY-RUN] Would execute: $*"
        return 0
    fi

    if [ $# -gt 1 ]; then
        # Multi-arg: execute directly so each arg is its own word.
        "$@"
    else
        # Single-string legacy form: requires eval for word-splitting.
        eval "$1"
    fi
}

# Extract a bare x.y.z semver from a version banner ("opencode v2.0.11" ->
# "2.0.11"). Empty or unparseable banners normalize to "unknown". Every
# version compare AND display site goes through this so equality checks and
# summaries agree on the format (#499).
normalize_version() {
    local v
    v=$(printf '%s' "${1:-}" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1) || v="unknown"
    [ -n "$v" ] || v="unknown"
    echo "$v"
}

# Prompt user with default
prompt_user() {
    local prompt_message="$1"
    local default_value="${2:-}"
    local result

    if [ "$AUTO_ACCEPT" = true ] && [ -n "$default_value" ]; then
        log_debug "Auto-accepting with default: ${default_value}"
        echo "$default_value"
        return 0
    fi

    if [ -n "$default_value" ]; then
        read -p "${prompt_message} [${default_value}]: " result
        echo "${result:-$default_value}"
    else
        read -p "${prompt_message}: " result
        echo "$result"
    fi
}

# Prompt yes/no with default
prompt_yes_no() {
    local prompt_message="$1"
    local default_value="${2:-n}"
    local result

    if [ "$AUTO_ACCEPT" = true ]; then
        result="$default_value"
    else
        while true; do
            read -p "${prompt_message} [${default_value}]: " result
            result="${result:-$default_value}"
            if [[ "$result" =~ ^[YyNn]$ ]]; then
                break
            fi
            echo "Invalid input. Please enter y or n."
        done
    fi

    [[ "$result" =~ ^[Yy]$ ]]
}

# Create backup of existing files
create_backup() {
    local file_to_backup="$1"
    local backup_path="${BACKUP_DIR}/$(basename "$file_to_backup")"

    if [ ! -d "$BACKUP_DIR" ]; then
        mkdir -p "$BACKUP_DIR"
        log_info "Created backup directory: ${BACKUP_DIR}"
    fi

    if [ -f "$file_to_backup" ]; then
        run_cmd cp "$file_to_backup" "$backup_path"
        log_info "Backed up: ${file_to_backup} -> ${backup_path}"
    fi
}

cleanup_old_backups() {
    local keep_count="${KEEP_BACKUPS}"

    if [ "$keep_count" -lt 0 ]; then
        log_debug "Backup cleanup disabled (KEEP_BACKUPS=$keep_count)"
        return 0
    fi

    local all_backups
    # Use find -type d to avoid matching sibling .zip files (which the glob
    # would otherwise count as separate backups, inflating the keep total).
    all_backups=$(find "${HOME}" -maxdepth 1 -type d \( -name ".opencode-backup-*" -o -name ".opencode-update-backup-*" \) 2>/dev/null | sort -r)

    if [ -z "$all_backups" ]; then
        log_debug "No old backups found"
        return 0
    fi

    local total_count
    total_count=$(echo "$all_backups" | grep -c . 2>/dev/null || echo 0)

    if [ "$total_count" -le "$keep_count" ]; then
        log_debug "Found $total_count backup(s) (within retention limit of $keep_count)"
        return 0
    fi

    local to_delete
    to_delete=$(echo "$all_backups" | tail -n +"$((keep_count + 1))")
    local delete_count
    delete_count=$(echo "$to_delete" | grep -c . 2>/dev/null || echo 0)

    log_info "Cleaning up old backups (keeping $keep_count of $total_count)..."

    echo "$to_delete" | while read -r dir; do
        if [ -n "$dir" ] && [ -d "$dir" ]; then
            if [ "$DRY_RUN" = true ]; then
                echo "[DRY-RUN] Would remove old backup: ${dir}"
                [ -f "${dir}.zip" ] && echo "[DRY-RUN] Would remove old backup zip: ${dir}.zip"
            else
                rm -rf "${dir}"
                log_info "Removed old backup: ${dir}"
                # Also remove associated zip archive (sibling file)
                if [ -f "${dir}.zip" ]; then
                    rm -f "${dir}.zip"
                    log_info "Removed old backup zip: ${dir}.zip"
                fi
            fi
        fi
    done

    log_success "Cleaned up $delete_count old backup(s)"
}

################################################################################
# ZIP BACKUP AND ROLLBACK FUNCTIONS
################################################################################

# Create a zip archive of the backup directory for portability.
# Zip path: ${BACKUP_DIR}.zip (sibling of flat-file dir, same timestamp).
# Uses `zip -r` if available; falls back to `tar -czf` (.tar.gz) if not.
# Respects DRY_RUN and ZIP_BACKUP toggle.
create_zip_backup() {
    # Respect toggle (--no-zip-backup disables)
    if [ "$ZIP_BACKUP" != true ]; then
        log_debug "Zip backup disabled (ZIP_BACKUP=$ZIP_BACKUP)"
        return 0
    fi

    # No backup dir → nothing to zip
    if [ ! -d "$BACKUP_DIR" ]; then
        log_debug "Skipping zip: BACKUP_DIR does not exist ($BACKUP_DIR)"
        return 0
    fi

    # Empty backup dir → nothing to zip
    if [ ! "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]; then
        log_debug "Skipping zip: BACKUP_DIR is empty ($BACKUP_DIR)"
        return 0
    fi

    local zip_path="${BACKUP_DIR}.zip"
    local archive_name
    archive_name=$(basename "$BACKUP_DIR")

    if [ "$DRY_RUN" = true ]; then
        if command_exists zip; then
            echo "[DRY-RUN] Would execute: zip -qr ${zip_path} ${BACKUP_DIR}/"
        else
            echo "[DRY-RUN] Would execute: tar -czf ${zip_path}.tar.gz -C ${HOME} ${archive_name}"
        fi
        return 0
    fi

    if command_exists zip; then
        log_info "Creating zip archive: ${zip_path}"
        # -r: recursive, paths KEPT (a backup tree contains many same-named
        # files — e.g. every skill's SKILL.md — and junking paths (-j) makes
        # zip abort with "cannot repeat names in zip file"; seen 2026-09-27)
        if zip -qr "$zip_path" "$BACKUP_DIR"/; then
            log_success "Zip archive created: ${zip_path}"
            return 0
        else
            log_warn "zip command failed; archive not created"
            return 1
        fi
    else
        # Fallback: tar.gz (named .tar.gz so consumers can detect format)
        local tar_path="${zip_path}.tar.gz"
        log_info "'zip' not available; creating tar.gz archive: ${tar_path}"
        if tar -czf "$tar_path" -C "$HOME" "$archive_name"; then
            log_success "Tar.gz archive created: ${tar_path}"
            return 0
        else
            log_warn "tar command failed; archive not created"
            return 1
        fi
    fi
}

# List available backups (newest-first) with timestamp, size, and zip availability.
# Output format (tabular, human-readable):
#   TIMESTAMP        TYPE       SIZE       ZIP     PATH
list_backups() {
    # Combine all backup-prefix directories, newest first.
    # Use find (not ls) so non-matching globs don't fail with pipefail.
    local all_dirs
    all_dirs=$(find "${HOME}" -maxdepth 1 -type d \( \
        -name ".opencode-backup-*" -o \
        -name ".opencode-update-backup-*" -o \
        -name ".opencode-pre-rollback-backup-*" \
        \) 2>/dev/null | sort -r)

    if [ -z "$all_dirs" ]; then
        echo "No backups found in ${HOME}/"
        echo ""
        echo "Backups are created automatically by:"
        echo "  - ./setup.sh (full deploy)"
        echo "  - ./setup.sh --rollback (pre-rollback safety)"
        return 0
    fi

    printf "%-17s %-22s %-10s %-5s %s\n" "TIMESTAMP" "TYPE" "SIZE" "ZIP" "PATH"
    printf -- "--------------------------------------------------------------------------------------------\n"

    local dir
    while IFS= read -r dir; do
        [ -z "$dir" ] && continue
        local name
        name=$(basename "$dir")
        local ts=""
        local btype="backup"

        # Classify and extract timestamp
        case "$name" in
            .opencode-backup-*)
                ts="${name#.opencode-backup-}"
                btype="backup"
                ;;
            .opencode-update-backup-*)
                ts="${name#.opencode-update-backup-}"
                btype="update"
                ;;
            .opencode-pre-rollback-backup-*)
                ts="${name#.opencode-pre-rollback-backup-}"
                btype="pre-rollback"
                ;;
            *)
                ts="?"
                ;;
        esac

        # Compute human-readable size of the dir
        local size_str="?"
        if command_exists du; then
            size_str=$(du -sh "$dir" 2>/dev/null | cut -f1)
        fi

        # Check for sibling .zip or .tar.gz
        local zip_str="-"
        if [ -f "${dir}.zip" ]; then
            zip_str="zip"
        elif [ -f "${dir}.zip.tar.gz" ]; then
            zip_str="tgz"
        fi

        printf "%-17s %-22s %-10s %-5s %s\n" "$ts" "$btype" "$size_str" "$zip_str" "$dir"
    done <<< "$all_dirs"

    # Also list orphan zip files (where the flat dir no longer exists).
    # Use find (not ls) to avoid pipefail on non-matching globs.
    local orphan_zips
    orphan_zips=$(find "${HOME}" -maxdepth 1 -type f \( \
        -name ".opencode-backup-*.zip" -o \
        -name ".opencode-backup-*.zip.tar.gz" -o \
        -name ".opencode-update-backup-*.zip" -o \
        -name ".opencode-pre-rollback-backup-*.zip" \
        \) 2>/dev/null | sort -r)
    if [ -n "$orphan_zips" ]; then
        echo ""
        echo "Orphan archives (no matching flat dir):"
        while IFS= read -r zpath; do
            [ -z "$zpath" ] && continue
            local zname
            zname=$(basename "$zpath")
            local zsize="?"
            if command_exists du; then
                zsize=$(du -sh "$zpath" 2>/dev/null | cut -f1)
            fi
            printf "  %-40s %-10s %s\n" "$zname" "$zsize" "$zpath"
        done <<< "$orphan_zips"
    fi
}

# Get the most recent backup directory (flat-file only, any prefix).
# Echoes the absolute path; returns 1 if none found.
get_latest_backup() {
    local latest
    latest=$(find "${HOME}" -maxdepth 1 -type d \( \
        -name ".opencode-backup-*" -o \
        -name ".opencode-update-backup-*" -o \
        -name ".opencode-pre-rollback-backup-*" \
        \) 2>/dev/null | sort -r | head -n1)
    if [ -z "$latest" ]; then
        return 1
    fi
    echo "$latest"
}

# Resolve a user-provided rollback target to a concrete backup directory.
# Accepts:
#   - TIMESTAMP (YYYYMMDD_HHMMSS)
#   - VERSION  (vX.Y.Z or X.Y.Z) — resolves via VERSION file git history
# Echoes the absolute path; returns 1 if not found.
resolve_backup_target() {
    local target="$1"

    # TIMESTAMP pattern: 8 digits, underscore, 6 digits
    if [[ "$target" =~ ^[0-9]{8}_[0-9]{6}$ ]]; then
        for prefix in ".opencode-backup-" ".opencode-update-backup-" ".opencode-pre-rollback-backup-"; do
            local candidate="${HOME}/${prefix}${target}"
            if [ -d "$candidate" ]; then
                echo "$candidate"
                return 0
            fi
        done
        # Also accept zip-only backup
        for prefix in ".opencode-backup-" ".opencode-update-backup-" ".opencode-pre-rollback-backup-"; do
            if [ -f "${HOME}/${prefix}${target}.zip" ]; then
                echo "${HOME}/${prefix}${target}.zip"
                return 0
            fi
        done
        return 1
    fi

    # VERSION pattern: vX.Y.Z or X.Y.Z
    if [[ "$target" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        local clean_ver="${target#v}"
        log_info "Resolving version ${clean_ver} via VERSION file git history..."

        # Get the commit date when VERSION was set to this value
        local version_commit_date=""
        if command_exists git && [ -d "${REPO_DIR}/.git" ]; then
            # Find the commit where VERSION content matched this value
            version_commit_date=$(cd "$REPO_DIR" && git log -1 --format=%ci -- VERSION 2>/dev/null | head -1)
            # Also try by tag
            if [ -z "$version_commit_date" ]; then
                version_commit_date=$(cd "$REPO_DIR" && git log -1 --format=%ai "v${clean_ver}" 2>/dev/null | head -1)
            fi
            # Try by content of VERSION file at commits
            if [ -z "$version_commit_date" ]; then
                local matching_commit
                matching_commit=$(cd "$REPO_DIR" && git log --format=%H -- VERSION 2>/dev/null | while read -r commit; do
                    local content
                    content=$(cd "$REPO_DIR" && git show "${commit}:VERSION" 2>/dev/null | tr -d '[:space:]')
                    if [ "$content" = "$clean_ver" ]; then
                        echo "$commit"
                        break
                    fi
                done | head -1)
                if [ -n "$matching_commit" ]; then
                    version_commit_date=$(cd "$REPO_DIR" && git log -1 --format=%ci "${matching_commit}" 2>/dev/null | head -1)
                fi
            fi
        fi

        if [ -z "$version_commit_date" ]; then
            log_warn "Could not resolve version ${clean_ver} to a git commit date"
            return 1
        fi

        # Convert git date (e.g. "2026-07-19 12:34:56 -0500") to comparable numeric form YYYYMMDDHHMMSS
        local git_ts_numeric
        git_ts_numeric=$(echo "$version_commit_date" | awk '{
            # Parse "YYYY-MM-DD HH:MM:SS ±ZZZZ"
            gsub(/-/, "", $1)
            gsub(/:/, "", $2)
            print $1 $2
        }')

        if [ -z "$git_ts_numeric" ]; then
            return 1
        fi

        log_info "Version ${clean_ver} corresponds to commit timestamp ${git_ts_numeric}"

        # Find the latest backup whose timestamp is <= git_ts_numeric
        local best_dir=""
        local best_ts=""
        local prefixes=(".opencode-backup-" ".opencode-update-backup-" ".opencode-pre-rollback-backup-")
        for prefix in "${prefixes[@]}"; do
            while IFS= read -r dir; do
                [ -z "$dir" ] && continue
                local name
                name=$(basename "$dir")
                local ts="${name#${prefix}}"
                # Only compare against valid timestamp suffixes
                [[ "$ts" =~ ^[0-9]{8}_[0-9]{6}$ ]] || continue
                # Strip underscore for numeric comparison
                local ts_numeric="${ts%_*}${ts#*_}"
                if [ "$ts_numeric" -le "$git_ts_numeric" ]; then
                    if [ -z "$best_ts" ] || [ "$ts_numeric" -gt "$best_ts" ]; then
                        best_ts="$ts_numeric"
                        best_dir="$dir"
                    fi
                fi
            done < <(find "${HOME}" -maxdepth 1 -type d -name "${prefix}*" 2>/dev/null)
        done

        if [ -n "$best_dir" ]; then
            echo "$best_dir"
            return 0
        fi
        return 1
    fi

    # Unknown format
    return 1
}

# Extract a zip/tar backup to a temporary directory.
# Echoes the temp dir path; caller MUST clean up.
# Returns 1 on failure.
extract_backup_archive() {
    local archive="$1"
    local tmp_dir
    tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/opencode-rollback-XXXXXX")
    if [ $? -ne 0 ]; then
        log_error "Could not create temp dir for extraction"
        return 1
    fi

    case "$archive" in
        *.zip.tar.gz)
            if ! tar -xzf "$archive" -C "$tmp_dir"; then
                log_error "Failed to extract tar.gz: $archive"
                rm -rf "$tmp_dir"
                return 1
            fi
            ;;
        *.zip)
            if command_exists unzip; then
                if ! unzip -q "$archive" -d "$tmp_dir"; then
                    log_error "Failed to extract zip: $archive"
                    rm -rf "$tmp_dir"
                    return 1
                fi
            else
                # Fallback: python's zipfile
                if command_exists python3; then
                    python3 -c "import zipfile; zipfile.ZipFile('$archive').extractall('$tmp_dir')" 2>/dev/null
                    if [ $? -ne 0 ]; then
                        log_error "Failed to extract zip (no unzip, python fallback failed): $archive"
                        rm -rf "$tmp_dir"
                        return 1
                    fi
                else
                    log_error "Cannot extract $archive: neither unzip nor python3 available"
                    rm -rf "$tmp_dir"
                    return 1
                fi
            fi
            ;;
        *)
            log_error "Unknown archive format: $archive"
            rm -rf "$tmp_dir"
            return 1
            ;;
    esac

    # If the extracted content has a single top-level dir that matches the
    # backup name pattern, descend into it so callers see flat content.
    local first_child
    first_child=$(ls -1 "$tmp_dir" 2>/dev/null | head -n1)
    if [ $(ls -1 "$tmp_dir" 2>/dev/null | wc -l) -eq 1 ] && [ -d "${tmp_dir}/${first_child}" ]; then
        echo "${tmp_dir}/${first_child}"
    else
        echo "$tmp_dir"
    fi
}

# Restore files from a backup directory into $CONFIG_DIR.
# Handles both backup layouts:
#   - flat files (opencode.json, AGENTS.md) + subdirs (skills/, skills-backup/, agents-backup/)
#   - update backups (opencode.json, AGENTS.md, skills/, agents/)
# Pre-v2.1 backups stored the config as config.json — restored under the new
# name, since OpenCode v2 only discovers opencode.json(c).
restore_from_dir() {
    local src_dir="$1"

    # Restore opencode.json
    if [ -f "${src_dir}/opencode.json" ]; then
        mkdir -p "$CONFIG_DIR"
        cp -f "${src_dir}/opencode.json" "${CONFIG_DIR}/opencode.json"
        log_info "Restored: opencode.json"
    elif [ -f "${src_dir}/config.json" ]; then
        mkdir -p "$CONFIG_DIR"
        cp -f "${src_dir}/config.json" "${CONFIG_DIR}/opencode.json"
        log_info "Restored: opencode.json (from legacy config.json backup)"
    fi

    # Restore AGENTS.md
    if [ -f "${src_dir}/AGENTS.md" ]; then
        mkdir -p "$CONFIG_DIR"
        cp -f "${src_dir}/AGENTS.md" "${CONFIG_DIR}/AGENTS.md"
        log_info "Restored: AGENTS.md"
    fi

    # Restore skills — prefer "skills" over "skills-backup"
    if [ -d "${src_dir}/skills" ]; then
        rm -rf "$SKILLS_DIR"
        cp -r "${src_dir}/skills" "$SKILLS_DIR"
        log_info "Restored: skills/"
    elif [ -d "${src_dir}/skills-backup" ]; then
        rm -rf "$SKILLS_DIR"
        cp -r "${src_dir}/skills-backup" "$SKILLS_DIR"
        log_info "Restored: skills/ (from skills-backup/)"
    fi

    # Restore agents
    if [ -d "${src_dir}/agents" ]; then
        rm -rf "$AGENTS_DEST_DIR"
        cp -r "${src_dir}/agents" "$AGENTS_DEST_DIR"
        log_info "Restored: agents/"
    elif [ -d "${src_dir}/agents-backup" ]; then
        rm -rf "$AGENTS_DEST_DIR"
        cp -r "${src_dir}/agents-backup" "$AGENTS_DEST_DIR"
        log_info "Restored: agents/ (from agents-backup/)"
    fi

    # Restore any other top-level files (*.json, *.md) that aren't opencode.json/AGENTS.md
    for f in "${src_dir}"/*; do
        [ -e "$f" ] || continue
        local fname
        fname=$(basename "$f")
        # Skip already-handled and known subdirs
        case "$fname" in
            config.json|opencode.json|AGENTS.md|skills|skills-backup|agents|agents-backup) continue ;;
        esac
        # Only restore regular files (skip shell configs etc. — those go to $HOME)
        if [ -f "$f" ]; then
            case "$fname" in
                *.json|*.md)
                    cp -f "$f" "${CONFIG_DIR}/${fname}"
                    log_info "Restored: ${fname}"
                    ;;
            esac
        fi
    done
}

# Create a safety backup before rollback (so rollback is reversible).
# Stored in ~/.opencode-pre-rollback-backup-TIMESTAMP/
create_pre_rollback_backup() {
    local ts
    ts=$(date +%Y%m%d_%H%M%S)
    local pre_dir="${HOME}/.opencode-pre-rollback-backup-${ts}"
    mkdir -p "$pre_dir"

    log_info "Creating pre-rollback safety backup..."

    if [ -f "$CONFIG_FILE" ]; then
        cp -f "$CONFIG_FILE" "${pre_dir}/opencode.json"
    fi
    if [ -f "${CONFIG_DIR}/AGENTS.md" ]; then
        cp -f "${CONFIG_DIR}/AGENTS.md" "${pre_dir}/AGENTS.md"
    fi
    if [ -f "${CONFIG_DIR}/vibeguard.config.json" ]; then
        cp -f "${CONFIG_DIR}/vibeguard.config.json" "${pre_dir}/vibeguard.config.json"
    fi
    if [ -d "$SKILLS_DIR" ]; then
        cp -r "$SKILLS_DIR" "${pre_dir}/skills"
    fi
    if [ -d "$AGENTS_DEST_DIR" ]; then
        cp -r "$AGENTS_DEST_DIR" "${pre_dir}/agents"
    fi

    log_success "Pre-rollback backup created: ${pre_dir}"
    echo "$pre_dir"
}

# Rollback: restore ~/.config/opencode/ from a previous backup.
# Uses ROLLBACK_TARGET (set by parse_arguments) to select the backup.
rollback() {
    local target="${ROLLBACK_TARGET:-}"

    # Sub-mode: list
    if [ "$target" = "list" ]; then
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "                📦 Available Backups"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        list_backups
        return 0
    fi

    # Resolve target → backup path (dir, or zip file)
    local backup_path=""

    if [ -z "$target" ]; then
        # Interactive: list and pick
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "                📦 Select Backup to Restore"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        list_backups
        echo ""
        if [ "$AUTO_ACCEPT" != true ]; then
            local pick
            read -p "Enter TIMESTAMP to restore (or 'q' to cancel): " pick
            if [ "$pick" = "q" ] || [ -z "$pick" ]; then
                log_info "Rollback cancelled"
                return 0
            fi
            target="$pick"
        else
            log_error "Interactive rollback requires a TARGET (cannot prompt with --yes)"
            log_info "Use: ./setup.sh --rollback TIMESTAMP"
            log_info "Or:  ./setup.sh --rollback latest"
            return 1
        fi
    fi

    if [ "$target" = "latest" ]; then
        backup_path=$(get_latest_backup)
        if [ -z "$backup_path" ]; then
            log_error "No backups available to restore from"
            return 1
        fi
    else
        backup_path=$(resolve_backup_target "$target")
        if [ -z "$backup_path" ]; then
            log_error "No backup found for target: '${target}'"
            log_info "Available backups:"
            list_backups
            return 1
        fi
    fi

    log_info "Resolved backup: ${backup_path}"

    # DRY-RUN: print what would happen, change nothing
    if [ "$DRY_RUN" = true ]; then
        echo ""
        echo "[DRY-RUN] Rollback plan:"
        echo "  Source: ${backup_path}"
        echo "  Target: ${CONFIG_DIR}/"
        echo "  Steps:"
        echo "    1. Create pre-rollback backup of current state"
        echo "    2. Confirm (or skip with --yes)"
        if [[ "$backup_path" == *.zip ]]; then
            echo "    3. Extract archive to temp location"
            echo "    4. Copy files to ${CONFIG_DIR}/"
        else
            echo "    3. Copy files to ${CONFIG_DIR}/"
        fi
        echo ""
        return 0
    fi

    # Confirmation prompt (unless --yes)
    if [ "$AUTO_ACCEPT" != true ]; then
        echo ""
        echo "⚠️  This will replace files in ${CONFIG_DIR}/ with content from:"
        echo "    ${backup_path}"
        echo ""
        if ! prompt_yes_no "Continue with rollback?" "n"; then
            log_info "Rollback cancelled by user"
            return 0
        fi
    fi

    # STEP 1: Safety backup (always — even with --yes)
    local pre_dir
    pre_dir=$(create_pre_rollback_backup)

    # STEP 2: Resolve src_dir (extract zip if needed)
    local src_dir="$backup_path"
    local extracted_tmp=""
    if [[ "$backup_path" == *.zip ]]; then
        log_info "Extracting zip archive..."
        extracted_tmp=$(extract_backup_archive "$backup_path")
        if [ $? -ne 0 ] || [ -z "$extracted_tmp" ]; then
            log_error "Failed to extract backup archive"
            log_info "Your current state is unchanged"
            return 1
        fi
        src_dir="$extracted_tmp"
    elif [ ! -d "$backup_path" ]; then
        log_error "Backup path is neither a directory nor a zip: ${backup_path}"
        return 1
    fi

    # STEP 3: Restore
    log_info "Restoring files to ${CONFIG_DIR}/..."
    mkdir -p "$CONFIG_DIR"
    restore_from_dir "$src_dir"

    # Cleanup temp dir
    if [ -n "$extracted_tmp" ]; then
        # Extracted tmp may be a subdir of mktemp base — remove the base
        local tmp_base
        tmp_base=$(echo "$extracted_tmp" | sed -E 's|^(.*)/opencode-rollback-[A-Za-z0-9]+.*$|\1/opencode-rollback-XXXXXX|' 2>/dev/null)
        # Safer: just remove the parent that mktemp created
        local tmp_parent
        tmp_parent="$extracted_tmp"
        # Walk up until we hit a path containing opencode-rollback-
        while [ "$tmp_parent" != "/" ] && [[ "$(basename "$tmp_parent")" != opencode-rollback-* ]]; do
            tmp_parent=$(dirname "$tmp_parent")
        done
        if [[ "$(basename "$tmp_parent")" == opencode-rollback-* ]]; then
            rm -rf "$tmp_parent"
        fi
    fi

    echo ""
    log_success "Rollback complete!"
    log_info "Restored from: ${backup_path}"
    log_info "Pre-rollback backup saved to: ${pre_dir}"
    log_info "If rollback was wrong, run: ./setup.sh --rollback $(basename "$pre_dir" | sed 's/^\.opencode-pre-rollback-backup-//')"
    return 0
}

################################################################################
# VALIDATION FUNCTIONS
################################################################################

# Validate API key format
validate_api_key() {
    local key="$1"
    local key_name="$2"

    if [ -z "$key" ]; then
        log_warn "No ${key_name} provided"
        return 1
    fi

    # Basic validation - adjust regex as needed
    if [ ${#key} -lt 10 ]; then
        log_warn "${key_name} seems too short (minimum 10 characters)"
        return 1
    fi

    return 0
}

# Validate network connectivity
check_network() {
    log_info "Checking network connectivity..."

    local test_urls=("https://api.github.com" "https://registry.npmjs.org")
    local connectivity_ok=true

    for url in "${test_urls[@]}"; do
        if curl -s --head --connect-timeout 5 "$url" > /dev/null 2>&1; then
            log_debug "Connected to: ${url}"
        else
            log_warn "Cannot reach: ${url}"
            connectivity_ok=false
        fi
    done

    if [ "$connectivity_ok" = false ]; then
        log_error "Network connectivity issues detected"
        return 1
    fi

    log_success "Network connectivity OK"
    return 0
}

# Check dependencies
check_dependencies() {
    log_info "Checking basic dependencies..."

    local missing_deps=()

    # Check for curl
    if ! command_exists curl; then
        missing_deps+=("curl")
    fi

    # Check for git (optional but recommended)
    if ! command_exists git; then
        log_warn "git is not installed (recommended but not required)"
    fi

    # Check for rg (optional but recommended)
    if ! command_exists rg; then
        log_warn "rg (ripgrep) is not installed (recommended but not required)"
        log_warn "  Install with: apt install ripgrep (Debian/Ubuntu) | brew install ripgrep (macOS) | pacman -S ripgrep (Arch)"
    fi

    if [ ${#missing_deps[@]} -gt 0 ]; then
        log_error "Missing required dependencies: ${missing_deps[*]}"
        log_info "Please install missing dependencies and try again"
        return 1
    fi

    log_success "All required dependencies are installed"
    return 0
}

# Safe file download with retry
download_file() {
    local url="$1"
    local output="$2"
    local max_retries=3
    local retry_count=0

    while [ $retry_count -lt $max_retries ]; do
        if curl -fsSL --connect-timeout 10 --max-time 30 "$url" -o "$output" 2>/dev/null; then
            return 0
        fi

        retry_count=$((retry_count + 1))
        log_warn "Download failed (attempt ${retry_count}/${max_retries}): ${url}"

        if [ $retry_count -lt $max_retries ]; then
            local wait_time=$((retry_count * 2))
            log_info "Waiting ${wait_time}s before retry..."
            sleep $wait_time
        fi
    done

    log_error "Failed to download after ${max_retries} attempts: ${url}"
    return 1
}

################################################################################
# PROGRESS INDICATORS
################################################################################

# Show spinning progress

################################################################################
# SETUP FUNCTIONS
################################################################################

# Report one coding agent's presence (helper for detect_installed_agents).
agent_report() {
    local name="$1" found="$2"
    if [ "$found" = true ]; then
        echo "  ✓ ${name}: found"
    else
        echo "  ✗ ${name}: not found"
    fi
}

# Detect installed coding-agent harnesses (#573). Read-only and idempotent —
# callable from print_summary without the plan step having run (quick and
# skills-only epilogues included). Sets the boolean globals the seed step
# consumes (PI_INSTALLED, CODEX_INSTALLED) and prints a found/missing table.
# Binary probe OR config-dir fallback: an installed-but-off-PATH agent still
# reports (and still seeds — the config dir is where the seed writes).
detect_installed_agents() {
    local opencode_ok=false pi_ok=false codex_ok=false claude_ok=false kimi_ok=false kilo_ok=false
    command_exists opencode && opencode_ok=true
    { command_exists pi || [ -d "${HOME}/.pi/agent" ]; } && pi_ok=true
    { command_exists codex || [ -d "${HOME}/.codex" ]; } && codex_ok=true
    { command_exists claude || [ -d "${HOME}/.claude" ]; } && claude_ok=true
    [ -d "${HOME}/.kimi-code" ] && kimi_ok=true
    { [ -d "${HOME}/.kilo" ] || [ -d "${HOME}/.config/kilo" ]; } && kilo_ok=true

    PI_INSTALLED="$pi_ok"
    CODEX_INSTALLED="$codex_ok"

    echo "Coding Agents Detected:"
    agent_report "opencode" "$opencode_ok"
    agent_report "pi" "$pi_ok"
    agent_report "codex" "$codex_ok"
    agent_report "claude" "$claude_ok"
    agent_report "kimi" "$kimi_ok"
    agent_report "kilo" "$kilo_ok"
    return 0
}

# Check GitHub CLI
setup_github_cli() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "              🔑 GitHub CLI Setup"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    if command_exists gh; then
        if gh auth status >/dev/null 2>&1; then
            local gh_user
            gh_user=$(gh api user --jq '.login' 2>/dev/null || echo "unknown")
            log_success "GitHub CLI is installed and authenticated as: ${gh_user}"
            log_info "Run 'opencode mcp auth github' to configure GitHub MCP authentication"
        else
            log_warn "GitHub CLI is installed but not authenticated."
            echo ""
            echo "  To authenticate, run:"
            echo "    gh auth login"
            echo ""
            echo "  Then re-run this setup or run: opencode mcp auth github"
        fi
    else
        log_warn "GitHub CLI (gh) is not installed."
        echo ""
        echo "  Install GitHub CLI:"
        case "$DETECTED_OS" in
            macOS*)
                echo "    brew install gh"
                ;;
            Windows*|Windows-GitBash)
                echo "    winget install GitHub.cli"
                echo "    -- or --"
                echo "    choco install gh"
                ;;
            Linux*)
                echo "    See: https://cli.github.com/"
                ;;
            *)
                echo "    See: https://cli.github.com/"
                ;;
        esac
        echo ""
        echo "  After installing, run: gh auth login"
        echo "  Then re-run this setup or run: opencode mcp auth github"
    fi
}

# Setup Z.AI API Key
setup_zai_api_key() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "                  🔑 Z.AI API Key Setup"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "This setup requires a Z.AI API Key for MCP services."
    echo ""

    # Check if already set
    # On Windows, also check the registry for setx-persisted values
    if is_windows && [ -z "$ZAI_API_KEY" ]; then
        local _reg_key
        _reg_key=$(reg query "HKCU\\Environment" /v ZAI_API_KEY 2>/dev/null | grep -oP 'REG_SZ\s+\K.*' || true)
        if [ -n "$_reg_key" ]; then
            ZAI_API_KEY="$_reg_key"
        fi
    fi

    if [ -n "$ZAI_API_KEY" ]; then
        echo "ZAI_API_KEY is already set in your environment."
        echo "Current key (masked): ${ZAI_API_KEY:0:8}...${ZAI_API_KEY: -4}"
        echo ""

        if prompt_yes_no "Use existing key?" "y"; then
            log_info "Using existing ZAI_API_KEY"
            return 0
        fi
    fi

    echo "Please enter your Z.AI API Key:"
    read -s ZAI_API_KEY
    echo ""

    if ! validate_api_key "$ZAI_API_KEY" "ZAI_API_KEY"; then
        log_error "No valid ZAI_API_KEY provided"

        if ! prompt_yes_no "Continue without API key? Some MCP services will not work." "n"; then
            # Non-critical plan step (#470): return, never exit — the executor
            # warns and continues, and the epilogue still runs.
            log_warn "Skipping Z.AI key setup - re-run this script to configure it."
            return 1
        fi
    else
        log_success "API Key accepted: ${ZAI_API_KEY:0:8}...${ZAI_API_KEY: -4}"
    fi
}

# Skills-only deploy: shared by the --skills-only flag path, menu option 2,
# and the headless no-TTY default (#466). One body, three entry points —
# duplicating it per site is how drift bugs are born (see #469).

# Setup PeonPing (AI agent sound notifications)
setup_peonping() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "              🔊 PeonPing Sound Notifications Setup"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "PeonPing plays game character voice lines when your AI agent"
    echo "finishes work or needs permission. Works with OpenCode!"
    echo ""
    echo "Features:"
    echo "  - Voice notifications from Warcraft, StarCraft, Portal, and more"
    echo "  - Desktop notifications when agent needs attention"
    echo "  - 160+ sound packs available"
    echo ""

    if ! prompt_yes_no "Install PeonPing?" "y"; then
        log_info "Skipping PeonPing installation"
        return 0
    fi

    # Check if peon command exists
    if command_exists peon; then
        log_info "PeonPing is already installed"
        if prompt_yes_no "Reinstall/update PeonPing?" "n"; then
            log_info "Updating PeonPing..."
        else
            log_info "Keeping existing PeonPing installation"
            return 0
        fi
    fi

    # Install based on platform
    case "$DETECTED_OS" in
        macOS|Linux*|Windows-WSL)
            log_info "Installing PeonPing via Homebrew or curl..."
            
            if command_exists brew; then
                log_info "Using Homebrew..."
                run_cmd "brew install PeonPing/tap/peon-ping"
            else
                log_info "Using curl installer..."
                run_cmd "curl -fsSL https://peonping.com/install | bash"
            fi
            ;;
        Windows*|Windows-GitBash)
            log_info "Installing PeonPing via PowerShell..."
            log_info "Run this in PowerShell as Administrator:"
            echo "  Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/PeonPing/peon-ping/main/install.ps1' -UseBasicParsing | Invoke-Expression"
            echo ""
            if prompt_yes_no "Have you completed the PowerShell installation?" "y"; then
                log_success "PeonPing installation completed"
            else
                log_warn "Please complete PeonPing installation manually"
                return 0
            fi
            ;;
        *)
            log_warn "Unsupported platform for automatic PeonPing installation"
            log_info "Install manually: https://github.com/PeonPing/peon-ping"
            return 0
            ;;
    esac

    # Verify installation
    if command_exists peon; then
        log_success "PeonPing installed successfully"
        
        # Run setup
        log_info "Running PeonPing setup..."
        run_cmd "peon-ping-setup 2>/dev/null || peon packs install peon 2>/dev/null || true"
        
        echo ""
        echo "✓ PeonPing installed successfully!"
        echo ""
        echo "Quick commands:"
        echo "  peon status          - Check if active"
        echo "  peon preview         - Play test sounds"
        echo "  peon packs list      - List installed packs"
        echo "  peon packs list --registry  - Browse 160+ packs"
        echo "  peon packs install <name>   - Install a pack"
        echo "  peon volume 0.5      - Set volume (0.0-1.0)"
        echo "  peon toggle          - Mute/unmute sounds"
        echo ""
        
        # Ask about configuring OpenCode plugin
        if prompt_yes_no "Install PeonPing TypeScript plugin for OpenCode?" "y"; then
            setup_peonping_hooks
        fi
    else
        log_warn "PeonPing installation may not have completed correctly"
        log_info "Try: brew install PeonPing/tap/peon-ping"
    fi
}

# Setup PeonPing plugin for OpenCode
# Note: OpenCode uses a TypeScript plugin system, NOT shell hooks.
# The opencode.sh adapter is an installer script that downloads the TS plugin.
setup_peonping_hooks() {
    echo ""
    log_info "Configuring PeonPing for OpenCode..."
    
    local OPENCODE_PLUGINS_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode/plugins"
    local PEON_PLUGIN="${OPENCODE_PLUGINS_DIR}/peon-ping.ts"
    
    # Check if plugin already installed
    if [ -f "$PEON_PLUGIN" ]; then
        log_info "PeonPing plugin already installed at ${PEON_PLUGIN}"
        if prompt_yes_no "Reinstall PeonPing plugin?" "n"; then
            log_info "Reinstalling..."
        else
            log_info "Keeping existing PeonPing plugin"
            return 0
        fi
    fi
    
    local peon_adapter=""
    
    # Find the PeonPing adapter script (installer)
    if [ -f "${HOME}/.claude/hooks/peon-ping/adapters/opencode.sh" ]; then
        peon_adapter="${HOME}/.claude/hooks/peon-ping/adapters/opencode.sh"
    elif [ -f "/opt/homebrew/opt/peon-ping/libexec/adapters/opencode.sh" ]; then
        peon_adapter="/opt/homebrew/opt/peon-ping/libexec/adapters/opencode.sh"
    elif [ -f "/usr/local/opt/peon-ping/libexec/adapters/opencode.sh" ]; then
        peon_adapter="/usr/local/opt/peon-ping/libexec/adapters/opencode.sh"
    else
        log_warn "PeonPing adapter script not found"
        log_info "Downloading adapter directly..."
        
        # Download and run the adapter directly from GitHub
        mkdir -p "${OPENCODE_PLUGINS_DIR}"
        local ADAPTER_URL="https://raw.githubusercontent.com/PeonPing/peon-ping/main/adapters/opencode.sh"
        
        if command_exists curl; then
            log_info "Running PeonPing OpenCode adapter installer..."
            curl -fsSL "$ADAPTER_URL" | bash
            
            if [ -f "$PEON_PLUGIN" ]; then
                log_success "PeonPing plugin installed successfully"
            else
                log_error "Failed to install PeonPing plugin"
                return 1
            fi
        else
            log_error "curl is required to download the adapter"
            return 1
        fi
        return 0
    fi
    
    log_info "Found adapter: ${peon_adapter}"
    
    # Run the adapter installer
    # This downloads peon-ping.ts to ~/.config/opencode/plugins/
    # And creates config at ~/.config/opencode/peon-ping/config.json
    log_info "Running PeonPing OpenCode adapter installer..."
    run_cmd "bash ${peon_adapter}"
    
    if [ -f "$PEON_PLUGIN" ]; then
        log_success "PeonPing plugin installed successfully"
        echo ""
        echo "Plugin installed to:"
        echo "  - Plugin: ${OPENCODE_PLUGINS_DIR}/peon-ping.ts"
        echo "  - Config: ${XDG_CONFIG_HOME:-$HOME/.config}/opencode/peon-ping/config.json"
        echo "  - Packs:  ~/.openpeon/packs/"
        echo ""
        echo "Restart OpenCode to activate the plugin."
        echo ""
    else
        log_error "PeonPing plugin installation failed"
        return 1
    fi
}

# Setup nvm
setup_nvm() {
    echo ""
    echo "=== Checking nvm (Node Version Manager) ==="

    # Check if nvm is installed
    if [ -d "$HOME/.nvm" ] || command_exists nvm; then
        local installed_version
        installed_version=$(nvm --version 2>/dev/null || echo "unknown")
        log_info "nvm is already installed (v${installed_version})"

        # Try to get latest version
        local latest_version
        if latest_version=$(curl -s https://api.github.com/repos/nvm-sh/nvm/releases/latest 2>/dev/null | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' | sed 's/v//'); then
            log_info "Latest version: v${latest_version}"

            if [ "$installed_version" != "$latest_version" ]; then
                echo ""
                log_warn "A newer version of nvm is available!"

                if prompt_yes_no "Would you like to update nvm to v${latest_version}?" "n"; then
                    log_info "Updating nvm..."
                    run_cmd "curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v${latest_version}/install.sh | bash"

                    export NVM_DIR="$HOME/.nvm"
                    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

                    log_success "nvm updated successfully"
                else
                    log_info "Skipping nvm update"
                fi
            else
                log_success "nvm is already up to date"
            fi
        fi
    else
        log_info "nvm is not installed"

        if prompt_yes_no "Install nvm?" "y"; then
            local latest_version
            latest_version=$(curl -s https://api.github.com/repos/nvm-sh/nvm/releases/latest 2>/dev/null | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' | sed 's/v//' || echo "latest")

            log_info "Installing nvm v${latest_version}..."
            run_cmd "curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v${latest_version}/install.sh | bash"

            export NVM_DIR="$HOME/.nvm"
            [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

            if command_exists nvm; then
                log_success "nvm installed successfully (v$(nvm --version))"
            else
                log_error "nvm installation failed"
                return 1
            fi
        else
            log_warn "Skipping nvm installation"
            log_warn "Note: nvm is required for Node.js management. Continuing may fail."
        fi
    fi

    return 0
}

# Setup Node.js
setup_nodejs() {
    echo ""
    echo "=== Installing Node.js v24 ==="

    # Check platform and install accordingly
    case "$DETECTED_OS" in
        Windows*|Windows-GitBash)
            # Windows: Check if Node.js is already installed
            if command_exists node; then
                log_info "Node.js is already installed ($(node --version))"

                if prompt_yes_no "Install a newer version of Node.js?" "n"; then
                    log_info "To install/update Node.js on Windows:"
                    echo "  1. Download from https://nodejs.org/"
                    echo "  2. Use winget: winget install OpenJS.NodeJS.LTS"
                    echo "  3. Use chocolatey: choco install nodejs"
                    echo "  4. Follow the installer prompts"
                fi
            else
                log_info "Node.js is not installed on Windows"
                echo ""
                echo "To install Node.js on Windows:"
                echo "  Option 1: Download from https://nodejs.org/"
                echo "  Option 2: Use winget (Windows 10+):"
                echo "           winget install OpenJS.NodeJS.LTS"
                echo "  Option 3: Use chocolatey:"
                echo "           choco install nodejs"
                echo ""

                if prompt_yes_no "Would you like to install Node.js now?" "y"; then
                    if command_exists winget; then
                        log_info "Installing Node.js via winget..."
                        run_cmd "winget install OpenJS.NodeJS.LTS"
                    elif command_exists choco; then
                        log_info "Installing Node.js via chocolatey..."
                        run_cmd "choco install nodejs"
                    else
                        log_error "No package manager found (winget or chocolatey)"
                        log_info "Please install Node.js manually from https://nodejs.org/"
                    fi
                fi
            fi
            ;;

        macOS|Linux*)
            # Unix-like systems: Use nvm
            # Ensure nvm is available
            if ! command_exists nvm; then
                log_error "nvm is not available. Cannot install Node.js."
                return 1
            fi

            # Load nvm
            export NVM_DIR="$HOME/.nvm"
            [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

    if prompt_yes_no "Install/switch to Node.js v24?" "y"; then
        log_info "Installing Node.js v24..."
        run_cmd "nvm install 26"
        run_cmd "nvm use 26"

        if command_exists node; then
            log_success "Node.js $(node --version) installed and active"
        else
            log_error "Node.js installation failed"
            return 1
        fi
        else
            log_info "Skipping Node.js v24 installation"
        fi
        ;;
    esac

    return 0
}

# Setup OpenCode — installs the v2 CLI from the scoped npm package @opencode/cli
# (the legacy opencode-ai package is the frozen v1 line; #499).
setup_opencode() {
    echo ""
    echo "=== Installing/Updating OpenCode ==="

    # Ensure npm/node is available
    if ! command_exists npm; then
        log_error "npm is not available. Cannot install @opencode/cli."
        return 1
    fi

    # Check if already installed
    if command_exists opencode; then
        local current_version
        # Normalize to a bare semver — `opencode --version` prints "opencode v2.0.11".
        current_version=$(normalize_version "$(opencode --version 2>/dev/null)")
        local latest_version
        latest_version=$(npm view @opencode/cli version 2>/dev/null || echo "unknown")

        # v1 detection (#499): the v1 npm package opencode-ai is frozen at 1.x; v2
        # ships as @opencode/cli. Per the v2 migrate-v1 docs, remove the
        # package-managed v1 install BEFORE installing v2 — the two packages
        # fight over the same `opencode` bin link.
        case "$current_version" in
            1.*)
                log_warn "OpenCode v1 detected (v${current_version}) — the v1 package opencode-ai is frozen; v2 ships as @opencode/cli"
                if prompt_yes_no "Migrate v1 to v2 now? (npm uninstall -g opencode-ai, then npm install -g @opencode/cli@latest)" "y"; then
                    run_cmd npm uninstall -g opencode-ai
                    run_cmd npm install -g @opencode/cli@latest

                    if command_exists opencode; then
                        log_success "OpenCode v2 installed ($(opencode --version 2>/dev/null))"
                    else
                        log_error "v1 to v2 migration failed"
                        return 1
                    fi
                else
                    log_warn "Skipping v1 to v2 migration — the v1 binary silently ignores the deployed config's v2 plugins key; re-run ./deploy/setup.sh to migrate"
                fi
                return 0
                ;;
        esac

        log_info "@opencode/cli is already installed (v${current_version})"
        log_info "Latest version: v${latest_version}"

        if [ "$current_version" != "$latest_version" ]; then
            echo ""
            log_warn "An update is available for @opencode/cli!"

            if prompt_yes_no "Would you like to update to the latest version?" "y"; then
                log_info "Updating @opencode/cli..."
                run_cmd "npm install -g @opencode/cli@latest"

                if command_exists opencode; then
                    log_success "@opencode/cli updated successfully to $(opencode --version)"
                else
                    log_error "@opencode/cli update failed"
                    return 1
                fi
            else
                log_info "Skipping @opencode/cli update"
            fi
        else
            log_success "@opencode/cli is already up to date"

            if prompt_yes_no "Reinstall @opencode/cli anyway?" "n"; then
                log_info "Reinstalling @opencode/cli..."
                run_cmd "npm install -g @opencode/cli"
                log_success "@opencode/cli reinstalled successfully"
            fi
        fi
    else
        log_info "@opencode/cli is not installed"

        if prompt_yes_no "Install OpenCode v2 now? (npm install -g @opencode/cli)" "y"; then
            log_info "Installing @opencode/cli..."
            run_cmd "npm install -g @opencode/cli"

            if command_exists opencode; then
                log_success "@opencode/cli installed successfully"
            else
                log_error "@opencode/cli installation failed"
                return 1
            fi
        else
            log_warn "Skipping @opencode/cli installation"
        fi
    fi

    return 0
}

# Update OpenCode CLI only — targets the v2 package @opencode/cli (#499)
update_opencode_cli() {
    echo ""
    echo "=== Updating OpenCode CLI ==="
    echo ""

    # Ensure npm/node is available
    if ! command_exists npm; then
        log_error "npm is not available. Cannot update @opencode/cli."
        log_info "Please install Node.js first: https://nodejs.org/"
        return 1
    fi

    # Check if opencode is installed
    if ! command_exists opencode; then
        log_warn "@opencode/cli is not installed."
        if prompt_yes_no "Would you like to install OpenCode v2 now? (npm install -g @opencode/cli)" "y"; then
            log_info "Installing @opencode/cli..."
            run_cmd "npm install -g @opencode/cli"
            
            if command_exists opencode; then
                log_success "@opencode/cli installed successfully (v$(normalize_version "$(opencode --version 2>/dev/null)"))"
                return 0
            else
                log_error "@opencode/cli installation failed"
                return 1
            fi
        else
            log_info "Skipping @opencode/cli installation"
            return 0
        fi
    fi

    # Get current version (normalized to a bare semver — the binary prints
    # "opencode v2.0.11")
    local current_version
    current_version=$(normalize_version "$(opencode --version 2>/dev/null)")
    log_info "Current version: v${current_version}"

    # v1 detection (#499): migrate to @opencode/cli per the v2 migrate-v1 docs —
    # remove the package-managed v1 install BEFORE installing v2 (bin-link fight).
    case "$current_version" in
        1.*)
            log_warn "OpenCode v1 detected (v${current_version}) — the v1 package opencode-ai is frozen; v2 ships as @opencode/cli"
            if prompt_yes_no "Migrate v1 to v2 now? (npm uninstall -g opencode-ai, then npm install -g @opencode/cli@latest)" "y"; then
                run_cmd npm uninstall -g opencode-ai
                run_cmd npm install -g @opencode/cli@latest

                if command_exists opencode; then
                    log_success "OpenCode v2 installed ($(opencode --version 2>/dev/null))"
                else
                    log_error "v1 to v2 migration failed"
                    return 1
                fi
            else
                log_warn "Skipping v1 to v2 migration — the v1 binary silently ignores the deployed config's v2 plugins key; re-run ./deploy/setup.sh to migrate"
            fi
            return 0
            ;;
    esac

    # Get latest version
    local latest_version
    log_info "Checking for updates..."
    latest_version=$(npm view @opencode/cli version 2>/dev/null || echo "unknown")
    
    if [ "$latest_version" = "unknown" ]; then
        log_error "Could not fetch latest version from npm registry"
        log_info "Check your internet connection and try again"
        return 1
    fi

    log_info "Latest version: v${latest_version}"

    # Compare versions
    if [ "$current_version" = "$latest_version" ]; then
        log_success "@opencode/cli is already up to date!"
        echo ""
        
        if prompt_yes_no "Force reinstall anyway?" "n"; then
            log_info "Reinstalling @opencode/cli..."
            run_cmd "npm install -g @opencode/cli@${latest_version}"
            log_success "@opencode/cli reinstalled successfully"
        fi
        
        return 0
    fi

    echo ""
    log_info "Update available: v${current_version} → v${latest_version}"
    
    # Check if auto-update is enabled
    if [ "$AUTO_ACCEPT" = true ]; then
        log_info "Auto-updating to latest version..."
        run_cmd "npm install -g @opencode/cli@latest"
        
        local new_version
        new_version=$(normalize_version "$(opencode --version 2>/dev/null)")
        
        if [ "$new_version" = "$latest_version" ]; then
            log_success "@opencode/cli updated successfully to v${new_version}"
        else
            log_error "Update failed. Current version: v${new_version}"
            return 1
        fi
    else
        if prompt_yes_no "Update @opencode/cli to v${latest_version}?" "y"; then
            log_info "Updating @opencode/cli..."
            run_cmd "npm install -g @opencode/cli@latest"
            
            local new_version
            new_version=$(normalize_version "$(opencode --version 2>/dev/null)")
            
            if [ "$new_version" = "$latest_version" ]; then
                log_success "@opencode/cli updated successfully to v${new_version}"
            else
                log_error "Update failed. Current version: v${new_version}"
                return 1
            fi
        else
            log_info "Update cancelled by user"
        fi
    fi

    return 0
}

# Setup configuration file
# Park a coexisting opencode.jsonc (#432): OpenCode v2 docs define no .json vs
# .jsonc tie-break when both live in one directory, so a leftover sibling has
# undefined precedence. Guard on BOTH files present — a jsonc-only machine
# keeps its sole live config. run_cmd keeps --dry-run preview-only. Called
# from the config phase and after an apply-mode resolver run, so every run
# that writes opencode.json ends with exactly one live config.
park_jsonc_sibling() {
    if [ -f "$CONFIG_FILE" ] && [ -f "${CONFIG_DIR}/opencode.jsonc" ]; then
        run_cmd mv "${CONFIG_DIR}/opencode.jsonc" "${CONFIG_DIR}/opencode.jsonc.legacy-ignored"
        log_warn "Stale opencode.jsonc found (undefined precedence vs opencode.json); renamed to opencode.jsonc.legacy-ignored"
    fi
}

setup_config() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "                  📁 Configuration Setup"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Create config directory
    run_cmd mkdir -p "$CONFIG_DIR"
    log_info "Created ${CONFIG_DIR} directory"

    # Copy AGENTS.md from project to global config
    if [ -f "${SCRIPT_DIR}/.AGENTS.md" ]; then
        if [ -f "${CONFIG_DIR}/AGENTS.md" ]; then
            if diff -q "${SCRIPT_DIR}/.AGENTS.md" "${CONFIG_DIR}/AGENTS.md" >/dev/null 2>&1; then
                log_info "AGENTS.md already up to date at ${CONFIG_DIR}/AGENTS.md"
            else
                log_warn "AGENTS.md at ${CONFIG_DIR}/AGENTS.md is STALE — it differs from the source ${SCRIPT_DIR}/.AGENTS.md"
                log_warn "Stale shipped instructions can cause incorrect agent behavior. Recommend overwriting."
                if prompt_yes_no "Overwrite with the current source version?" "y"; then
                    create_backup "${CONFIG_DIR}/AGENTS.md"
                    run_cmd cp "${SCRIPT_DIR}/.AGENTS.md" "${CONFIG_DIR}/AGENTS.md"
                    log_success "AGENTS.md updated successfully (renamed from .AGENTS.md)"
                else
                    log_warn "Kept stale AGENTS.md — shipped agent instructions may be out of date."
                fi
            fi
        else
            run_cmd cp "${SCRIPT_DIR}/.AGENTS.md" "${CONFIG_DIR}/AGENTS.md"
            log_success "AGENTS.md copied successfully (renamed from .AGENTS.md)"
        fi
    else
        log_warn ".AGENTS.md not found in ${SCRIPT_DIR}"
    fi

    # Migrate legacy deploy: setup.sh used to deploy the config as config.json,
    # which OpenCode v2 never reads (it only discovers opencode.json(c)). Adopt
    # the legacy file as the live config so the preservation logic below applies
    # to it; if both exist, park the stale legacy copy instead of deleting it.
    if [ ! -f "$CONFIG_FILE" ] && [ -f "$LEGACY_CONFIG_FILE" ]; then
        run_cmd mv "$LEGACY_CONFIG_FILE" "$CONFIG_FILE"
        log_info "Migrated legacy config.json -> opencode.json (OpenCode v2 only reads opencode.json|opencode.jsonc)"
    elif [ -f "$CONFIG_FILE" ] && [ -f "$LEGACY_CONFIG_FILE" ]; then
        run_cmd mv "$LEGACY_CONFIG_FILE" "${LEGACY_CONFIG_FILE}.legacy-ignored"
        log_warn "Stale legacy config.json found (ignored by OpenCode v2); renamed to config.json.legacy-ignored"
    fi

    # Park a coexisting opencode.jsonc (#432) — both-exist + dry-run-safe helper.
    park_jsonc_sibling

    # Check if the config already exists
    if [ -f "$CONFIG_FILE" ]; then
        echo ""
        log_warn "opencode.json already exists at ${CONFIG_FILE}"

        if ! prompt_yes_no "Do you want to overwrite it?" "n"; then
            log_info "Skipping config copy. Existing configuration preserved."
            SKIP_CONFIG_COPY=true
            return 0
        fi

        # Create backup
        create_backup "$CONFIG_FILE"
    else
        # Config doesn't exist, prompt to copy
        if ! prompt_yes_no "Copy opencode.json to ${CONFIG_DIR}/?" "y"; then
            log_info "Skipping config copy"
            SKIP_CONFIG_COPY=true
            return 0
        fi
    fi

    # Copy the config from the single source of truth (deploy/opencode.json).
    # Historically this copied deploy/config.json, but maintaining a duplicate
    # caused drift (see PLAN-BT-74 Phase 12.2). The resolver (run later in
    # deploy_agents) patches this file in-place for explore/general models (and
    # primary only if --provider/--mix was chosen — local deploys ship no
    # baked-in primary; the end user picks at runtime).
    if [ "$SKIP_CONFIG_COPY" != true ]; then
        if [ -f "$SOURCE_CONFIG" ]; then
            run_cmd cp "$SOURCE_CONFIG" "$CONFIG_FILE"
            log_success "opencode.json copied successfully (from ${SOURCE_CONFIG})"

            # Copied config may now coexist with a jsonc (accepted copy on a
            # jsonc-only machine): restore the one-live-config end state.
            park_jsonc_sibling

            # Install the upstream markitdown MCP server (#487: markitdown-mcp from PyPI)
            # only when the pack is requested — the server ships disabled:true, and
            # markitdown[all] is a large install, so never on a plain deploy.
            # Best-effort — non-fatal on offline/pip-missing.
            if echo "$ENABLE_PACK" | grep -qw "markitdown"; then
                install_markitdown_mcp
            fi

            # Install docling-mcp if --enable-pack docling was requested (PLAN-GIT-308).
            # Heavy (~3-4 GB) — only runs when explicitly opted in.
            install_docling

            # Deploy vibeguard secret-masking config (PLAN-GIT-315).
            local vg_src="${REPO_DIR}/plugins/vibeguard.config.json"
            if [ -f "$vg_src" ]; then
                run_cmd cp "$vg_src" "${CONFIG_DIR}/vibeguard.config.json"
                log_success "vibeguard.config.json deployed (secret masking active)"
                echo "✓ Secret masking: active (vibeguard)"
            fi

            echo ""
        echo "✓ Configured $(count_agents "${REPO_DIR}/agents") agents:"
        echo "    - build (default) - Full-featured coding agent"
        echo "    - plan - Planning agent (read-only)"
        echo "    - explore - Codebase exploration and analysis"
        echo "    - image-analyzer-subagent - Image/screenshot analysis"
        echo "    - zai-media-subagent - Media production: image/video gen, ASR, OCR (delegated)"
        echo "    - discovery-specialist-subagent - Customer-facing discovery: Vision docs + wireframes"
        echo "    - ... and $(($(count_agents "${REPO_DIR}/agents") - 6)) more agents"
            echo ""
             echo "✓ Configured MCP servers:"
             echo "    Auto-start: codegraph, web-reader, web-search"
              echo "    Opt-in per-project (.opencode/opencode.json): atlassian"
              echo "    Available but disabled (opt-in): next-devtools, markitdown, docling, chrome-devtools, playwright, alpha-vantage, nanobanana"
              echo "    Enable a group with: ./setup.sh --enable-pack <markitdown|nextjs|docling|chrome-devtools|playwright|alpha-vantage|nanobanana>"
            echo ""
        else
            log_error "opencode.json source not found: ${SOURCE_CONFIG}"
            return 1
        fi
    fi

    # Skills deploy moved to the single install path (#379): deploy_content()
    # (invoked from deploy_agents, after migration) installs skills + agents via
    # the installer CLI — manifest-tracked. Only the directory is ensured here.
    run_cmd mkdir -p "$SKILLS_DIR"

    return 0
}

# ─────────────────────────────────────────────────────────────────────────────
# MARKITDOWN MCP INSTALL (#487 — upstream markitdown-mcp from PyPI)
# ─────────────────────────────────────────────────────────────────────────────

# Install the official markitdown-mcp MCP server (microsoft/markitdown) from
# PyPI onto the user's PATH so OpenCode can spawn it via the `command` field in
# opencode.json. Replaces the former in-repo vendored launcher
# (markitdown-local-mcp) — #487. Uses pip (already a soft dep via
# codegraph/python tooling).
#
# Why the exact pin: upstream publishes only alpha releases (0.0.1a1–0.0.1a7);
# plain `pip install markitdown-mcp` fails ("no matching distribution") because
# pip skips pre-releases. An exact pre-release pin installs without --pre and
# keeps pre-release candidates out of transitive resolution. Bump ritual:
# the pin lives in deploy/setup.sh only (deploy/setup.ps1 is a thin launcher
# since #474 and carries no pin; tests/test_setup_ps1_vars.bats enforces its
# absence there).
#
# Why the mcp[cli] co-install: docling-mcp>=3.0 requires mcp[cli]>=2.0,<3.0 and
# upstream markitdown-mcp requires mcp>=2.1.1,<3.0.0 — installing both specs in
# one resolve keeps the shared MCP SDK at 2.x for both servers (the retired
# vendored pin mcp<2.0 was mutually exclusive with docling and broke both).
#
# Why --user: avoids polluting system site-packages; console-script lands in
# ~/.local/bin (Linux/macOS). Python 3.12+ auto-adds ~/.local/bin to PATH on
# most distros.
install_markitdown_mcp() {
    echo ""

    # Dry-run contract (#467): the pip uninstall/install below mutate the
    # user's site-packages — never during a preview.
    if [ "$DRY_RUN" = true ]; then
        echo "[DRY-RUN] Would ensure markitdown-mcp==0.0.1a7 (pip --user)"
        return 0
    fi

    log_info "Installing markitdown-mcp (upstream, PyPI)..."

    # Migrate old installs: the retired vendored launcher must not linger on
    # PATH beside the new entry point (best-effort — absent is fine). PEP 668
    # blocks plain uninstalls on externally-managed systems — retry once with
    # --break-system-packages (mirrors the install path below).
    python3 -m pip uninstall -y markitdown-local-mcp >/dev/null 2>&1 \
        || python3 -m pip uninstall -y --break-system-packages markitdown-local-mcp >/dev/null 2>&1 \
        || true

    # Idempotency: skip the network round-trip when the PINNED version is
    # already installed AND importable. Version-aware on purpose: a plain
    # `pip show` + import probe passes for ANY installed version, so pin
    # bumps would never reach machines with a working older alpha. `pip
    # show` alone hides broken installs (e.g. the mcp SDK dependency
    # missing), which surfaces later as "MCP error -32000: Connection
    # closed" when the server crashes on import.
    if python3 -m pip show markitdown-mcp 2>/dev/null | grep -qF "Version: 0.0.1a7" \
        && python3 -c "from markitdown_mcp.__main__ import main" >/dev/null 2>&1; then
        log_success "markitdown-mcp 0.0.1a7 already installed — skipping pip install"
        return 0
    fi

    # Prerequisite: python3 + pip
    if ! command_exists python3; then
        log_warn "python3 not found — cannot install markitdown-mcp. Install Python 3.10+ and re-run."
        return 0
    fi

    if ! python3 -m pip --version >/dev/null 2>&1; then
        log_warn "pip not available for python3 — cannot install markitdown-mcp. Install pip and re-run."
        return 0
    fi

    # Dry-run safe (#470 class sweep): this is a real network install into the
    # user's Python user-site — never during a preview.
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Would pip install markitdown-local-mcp from ${launcher_dir}"
        return 0
    fi

    # Install (network required; non-fatal if offline). PEP 668
    # (externally-managed-environment, Debian 12+/Ubuntu 23.04+) blocks plain
    # `pip install --user` — retry once with --break-system-packages; --user
    # keeps the install isolated to ~/.local, which is the risk PEP 668 guards.
    log_info 'pip install --user "markitdown-mcp==0.0.1a7" "mcp[cli]>=2.1.1,<3.0.0"'
    local pip_err
    pip_err="$(mktemp)"
    if python3 -m pip install --user --no-warn-script-location "markitdown-mcp==0.0.1a7" "mcp[cli]>=2.1.1,<3.0.0" >/dev/null 2>"$pip_err" \
        || { grep -q "externally-managed-environment" "$pip_err" \
            && python3 -m pip install --user --break-system-packages --no-warn-script-location "markitdown-mcp==0.0.1a7" "mcp[cli]>=2.1.1,<3.0.0" >/dev/null 2>>"$pip_err"; }; then
        rm -f "$pip_err"
        log_success "markitdown-mcp installed"

        # PATH check — warn (don't fail) if ~/.local/bin not on PATH
        local user_bin="${HOME}/.local/bin"
        case ":${PATH}:" in
            *":${user_bin}:"*)
                # All good
                ;;
            *)
                log_warn "${user_bin} is not on your PATH. Add it to your shell rc to use markitdown-mcp:"
                echo "    export PATH=\"${user_bin}:\$PATH\"" >&2
                ;;
        esac
    else
        log_warn "pip install failed for markitdown-mcp (offline?). The server is opt-in (disabled: true) — OpenCode will work without it. Re-run setup when online to enable."
        log_warn "pip stderr (last 3 lines):"
        tail -n 3 "$pip_err" >&2
        rm -f "$pip_err"
    fi
}

# Install docling-mcp (heavy ~3-4 GB) — only when --enable-pack docling is
# requested. Like markitdown, docling-mcp comes from
# PyPI. First convert downloads ~hundreds of MB of models from huggingface.co.
install_docling() {
    if ! echo "$ENABLE_PACK" | grep -qw "docling"; then
        return 0
    fi

    echo ""
    log_info "Installing docling-mcp[local] (~3-4 GB with models)..."

    if ! command_exists python3; then
        log_warn "python3 not found — cannot install docling-mcp. Install Python 3.10+ and re-run."
        return 0
    fi

    if ! python3 -m pip --version >/dev/null 2>&1; then
        log_warn "pip not available for python3 — cannot install docling-mcp. Install pip and re-run."
        return 0
    fi

    # PEP 668 (externally-managed-environment, Debian 12+/Ubuntu 23.04+)
    # blocks plain `pip install --user` — retry once with
    # --break-system-packages; --user keeps it isolated to ~/.local.
    log_info "pip install --user docling-mcp[local]"
    local pip_err
    pip_err="$(mktemp)"
    if python3 -m pip install --user --no-warn-script-location "docling-mcp[local]" >/dev/null 2>"$pip_err" \
        || { grep -q "externally-managed-environment" "$pip_err" \
            && python3 -m pip install --user --break-system-packages --no-warn-script-location "docling-mcp[local]" >/dev/null 2>>"$pip_err"; }; then
        rm -f "$pip_err"
        log_success "docling-mcp installed"
        log_info "NOTE: first 'docling convert' will download ~hundreds of MB of models from huggingface.co (cached thereafter)."
    else
        log_warn "pip install failed for docling-mcp (offline, OOM, or PEP 668?). The pack is opt-in — OpenCode will work without it. Re-run setup when online to enable."
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# v2.0 MODEL RESOLUTION HELPERS
# ─────────────────────────────────────────────────────────────────────────────

# Run the model resolver: injects concrete models into deployed agent .md files
# and patches opencode.json (explore + general always; primary only if
# --provider/--mix chosen — local deploys omit a baked-in primary). Honors
# global/project overrides + provider preset. Preserve-edits via sidecar unless
# --force.
run_resolver() {
    if [ ! -f "$RESOLVER_SCRIPT" ]; then
        log_error "Resolver not found: $RESOLVER_SCRIPT"
        return 1
    fi

    # #379 single install path: when RESOLVER_CONFIG_ONLY=true the call omits the
    # agents args — the installer CLI (deploy_content) owns agent-file writing.
    # --models-only / --migrate-only / lift-only keep the full resolver behavior.
    local agents_args=""
    if [ "${RESOLVER_CONFIG_ONLY:-false}" != "true" ]; then
        agents_args="--agents-src ${AGENTS_SRC_DIR} --agents-dest ${AGENTS_DEST_DIR}"
    fi

    local extra_args=""
    if [ "$FORCE_RESOLVE" = true ]; then
        extra_args="$extra_args --force"
    fi
    if [ -n "$PROVIDER" ]; then
        extra_args="$extra_args --provider ${PROVIDER} --presets ${PROVIDER_PRESETS}"
    fi
    # Deploy-time exposed-model guard (#281): fail-fast if a tier/source pin
    # references a model its provider doesn't serve. Guarded by file presence so
    # older deploys without provider-models.json are unaffected.
    if [ -f "${INSTALLER_DIR}/provider-models.json" ]; then
        extra_args="$extra_args --provider-models ${INSTALLER_DIR}/provider-models.json"
    fi

    local project_map_arg=""
    [ -f "$PROJECT_MODELS_MAP" ] && project_map_arg="--project-map ${PROJECT_MODELS_MAP}"
    local project_overrides_arg=""
    [ -f "$PROJECT_OVERRIDES" ] && project_overrides_arg="--project-overrides ${PROJECT_OVERRIDES}"

    local dry_arg=""
    if [ "$DRY_RUN" = true ]; then
        rm -rf "$DRY_RUN_PREVIEW_DIR"
        dry_arg="--dry-run --preview-dir ${DRY_RUN_PREVIEW_DIR}"
    fi

    # D2 (#470): declining the config overwrite means the existing
    # opencode.json wins — omit --config-src so the resolver bases its
    # in-place model patch on the existing file (resolve-models.mjs :283-284
    # fallback). No existing file ⇒ the resolver writes no config at all.
    # #491: models-only/migrate have no decline prompt — presence decides.
    # An existing config wins (dest-fallback); a fresh machine keeps the
    # stock base so bootstrap still writes. jsonc siblings are unaffected:
    # presence is checked on opencode.json only, and park_jsonc_sibling (the
    # #432 interaction) still collapses a live .jsonc after a stock write.
    local config_src_arg=""
    if [ "$SKIP_CONFIG_COPY" = true ]; then
        log_info "Config copy declined - resolver patches the existing config in place (or writes none)"
    elif { [ "$MODELS_ONLY" = true ] || [ "$MIGRATE_ONLY" = true ]; } && [ -f "$CONFIG_FILE" ]; then
        log_info "Existing config found - resolver patches it in place (models-only/migrate presence gate)"
    else
        config_src_arg="--config-src ${SOURCE_CONFIG}"
    fi

    node "$RESOLVER_SCRIPT" \
        $agents_args \
        --tiers "$AGENT_TIERS" \
        --default-map "$MODELS_DEFAULT_MAP" \
        --user-map "$USER_MODELS_MAP" \
        $project_map_arg \
        --overrides "$USER_OVERRIDES" \
        $project_overrides_arg \
        $config_src_arg \
        --config-dest "$CONFIG_FILE" \
        --state "$RESOLVED_SIDECAR" \
        $dry_arg \
        $extra_args
    local resolver_rc=$?
    # Declined-copy migration (#625): when the user keeps their existing
    # config, its skill-allow rules are frozen at the last accepted write —
    # renames/consolidations on main then dead-end apply-skill-profile's
    # lean typo-guard. Reconcile skill allows against the shipped config:
    # add missing shipped allows, drop rules whose resource no longer exists
    # (repo OR deployed skills dirs), preserve everything non-skill.
    # Preview-only under --dry-run. Failure warns — apply-skill-profile
    # remains the loud failure point downstream.
    if [ "$SKIP_CONFIG_COPY" = true ] && [ "$resolver_rc" -eq 0 ] && [ -f "$CONFIG_FILE" ]; then
        local reconcile_dry_args=""
        if [ "$DRY_RUN" = true ]; then
            reconcile_dry_args="--dry-run"
        fi
        node "$APPLY_SKILL_PROFILE_SCRIPT" \
            --reconcile-shipped "$SOURCE_CONFIG" \
            --config "$CONFIG_FILE" \
            --skills-dir "${REPO_DIR}/skills" \
            --deployed-skills-dir "${CONFIG_DIR}/skills" \
            $reconcile_dry_args || log_warn "skill-allow reconcile failed — apply-skill-profile may report stale allows (see its remediation hint)"
    fi
    # An apply-mode resolver write can create opencode.json beside a live
    # jsonc (decline-copy path, --models-only/--migrate-only): park it here so
    # every run that writes the config ends with exactly one live config
    # (#432). Dry-run stages to the preview dir and moves nothing.
    if [ "$resolver_rc" -eq 0 ] && [ "$DRY_RUN" != true ]; then
        park_jsonc_sibling
    fi
    return "$resolver_rc"
}

# Run the provider-pack merger (PLAN #268): deep-merges selected pack partials
# (deploy/packs/pack-<name>.json) into the resolved config, flipping
# mcp.<server>.enabled + the root permission "<ns>*": "allow" for the packs.
#
# B1 (critical): the target config path MUST match where run_resolver wrote its
# output. In normal mode the resolver writes $CONFIG_FILE; in dry-run it stages
# to $DRY_RUN_PREVIEW_DIR/opencode.json (the run_cmd cp at setup_config is a
# no-op in dry-run). Pointing at the wrong path makes dry-run ACs silently pass.
#
# No-op (return 0) if $ENABLE_PACK is empty. Errors propagate to deploy_agents.
run_pack_merger() {
    if [ -z "$ENABLE_PACK" ]; then
        return 0
    fi

    if [ ! -f "$MERGE_PACKS_SCRIPT" ]; then
        log_error "Pack merger not found: $MERGE_PACKS_SCRIPT"
        return 1
    fi
    if [ ! -d "$PACKS_DIR" ]; then
        log_error "Packs directory not found: $PACKS_DIR"
        return 1
    fi

    # D2 (#470): a declined config with no existing file means there is
    # nothing to merge into — skip instead of a cryptic merge failure.
    if [ "$SKIP_CONFIG_COPY" = true ] && [ ! -f "$CONFIG_FILE" ]; then
        log_warn "Packs require a config you declined to create - skipping pack merge."
        return 0
    fi

    local target_config="$CONFIG_FILE"
    if [ "$DRY_RUN" = true ]; then
        target_config="${DRY_RUN_PREVIEW_DIR}/opencode.json"
        if [ ! -f "$target_config" ]; then
            log_error "Dry-run preview config not found: ${target_config}"
            log_error "The resolver must run first to stage the preview. Aborting pack merge."
            return 1
        fi
    fi

    # NOTE: we intentionally do NOT pass --dry-run to merge-packs.mjs here.
    # setup.sh's dry-run contract (matching run_resolver) is "stage real files
    # into $DRY_RUN_PREVIEW_DIR so the user can inspect them". The resolver
    # writes to the preview for real; merge-packs must do the same so the
    # preview reflects the would-be-merged result. merge-packs's own --dry-run
    # flag is for standalone CLI use only.
    log_info "Applying provider packs: ${ENABLE_PACK}"
    node "$MERGE_PACKS_SCRIPT" \
        --config "$target_config" \
        --packs-dir "$PACKS_DIR" \
        --packs "$ENABLE_PACK"
    local rc=$?
    if [ "$rc" -ne 0 ]; then
        log_error "Provider-pack merge failed (exit ${rc})"
        return 1
    fi

    # Install-on-enable: markitdown's Python server is pip-installed from PyPI,
    # not baked into the target config — without this the enabled server fails
    # to spawn. Mirrors install_docling gating. Skipped in dry-run
    # (nothing real is deployed) and when the pack wasn't requested.
    # grep -qw (not anchored) is safe: validate_enable_pack fail-fast restricts
    # --enable-pack to real pack names, so no 'markitdown2' false positives.
    if [ "$DRY_RUN" != true ] && echo "$ENABLE_PACK" | grep -qw "markitdown"; then
        install_markitdown_mcp
    fi
    return 0
}

# Choose a model provider (interactive TUI or --provider flag) and write the
# global ~/.config/opencode/models.json tier map. Skipped silently in
# non-interactive mode unless --provider is set (defaults apply).
setup_model_provider() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "                  🧠 Model Provider (v2.0)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    if [ -n "$PROVIDER" ] && [ "$MIX_MODE" = false ]; then
        log_info "Provider preset: ${PROVIDER} (writing ${USER_MODELS_MAP})"
        node "$TUI_SCRIPT" provider-picker \
            --presets "$PROVIDER_PRESETS" --provider "$PROVIDER" \
            --out "$USER_MODELS_MAP"
        return $?
    fi

    # --mix: per-category provider/model editor (interactive). Base = $PROVIDER or zai.
    if [ "$MIX_MODE" = true ]; then
        local base="${PROVIDER:-zai}"
        log_info "Mix mode: choose a provider/model per category (base: ${base})"
        node "$TUI_SCRIPT" tier-editor \
            --presets "$PROVIDER_PRESETS" --provider "$base" \
            --out "$USER_MODELS_MAP" \
            || log_warn "Mix editor cancelled (using default models)"
        return $?
    fi

    if [ -t 0 ] && [ "$AUTO_ACCEPT" = false ]; then
        echo "  1) Single provider (recommended)"
        echo "  2) Mix providers per category (e.g. vision on OpenAI, rest on Z.AI)"
        local provider_choice
        provider_choice=$(prompt_user "Select option [1]" "1")
        case "$provider_choice" in
            2)
                node "$TUI_SCRIPT" tier-editor \
                    --presets "$PROVIDER_PRESETS" --provider "${PROVIDER:-zai}" \
                    --out "$USER_MODELS_MAP" \
                    || log_warn "Mix editor cancelled (using default models)"
                ;;
            *)
                if prompt_yes_no "Choose a model provider? (default: Z.AI)" "n"; then
                    node "$TUI_SCRIPT" provider-picker \
                        --presets "$PROVIDER_PRESETS" \
                        --out "$USER_MODELS_MAP" \
                        || log_warn "Provider selection skipped (using default models)"
                else
                    log_info "Using default Z.AI models"
                fi
                ;;
        esac
    else
        log_info "Non-interactive: using default models (use --provider <name> or --mix to choose)"
    fi
}

# Lift unknown (non-z.ai-default) model customizations from an existing deployed
# agent set into ~/.config/opencode/agent-overrides.json so they survive the
# re-resolve as first-class managed overrides rather than being clobbered.
lift_customizations() {
    [ -d "$AGENTS_DEST_DIR" ] || return 0
    local dry_arg=""
    [ "$DRY_RUN" = true ] && dry_arg="--dry-run"
    node "$RESOLVER_SCRIPT" --lift-only \
        --agents-dest "$AGENTS_DEST_DIR" \
        --default-map "$MODELS_DEFAULT_MAP" \
        --overrides "$USER_OVERRIDES" \
        $dry_arg
}

# Detect a pre-v2 install and run the one-time migration: backup, lift
# customizations, mark the config version. Idempotent (no-op once at v2.0).
run_migration() {
    local current_version="0"
    [ -f "$CONFIG_VERSION_FILE" ] && current_version=$(tr -d '[:space:]' < "$CONFIG_VERSION_FILE")

    # current_version >= SCHEMA_VERSION  ->  skip (input is ascending iff SCHEMA <= current)
    if printf '%s\n%s\n' "$SCHEMA_VERSION" "$current_version" | sort -V -C 2>/dev/null; then
        log_debug "Config already at v${SCHEMA_VERSION}, no migration needed"
        return 0
    fi

    echo ""
    log_warn "v2.0 major upgrade detected (current config: v${current_version:-unknown})"
    log_warn "Agent models are now resolved from tiers (see MIGRATION.md). Existing"
    log_warn "agents will be backed up and re-resolved. Custom models are preserved."

    if [ "$AUTO_ACCEPT" = false ]; then
        if ! prompt_yes_no "Run migration now?" "y"; then
            log_warn "Migration skipped. Agents re-resolved from tiers (custom models NOT lifted)."
            return 0
        fi
    fi

    # Backup existing agents + config (skip actual copy in dry-run)
    if [ "$DRY_RUN" = true ]; then
        if [ -d "$AGENTS_DEST_DIR" ] && [ "$(ls -A "$AGENTS_DEST_DIR" 2>/dev/null)" ]; then
            log_info "[DRY-RUN] Would back up agents -> ${BACKUP_DIR}/agents-backup"
        fi
        [ -f "$CONFIG_FILE" ] && log_info "[DRY-RUN] Would back up opencode.json"
    else
        if [ -d "$AGENTS_DEST_DIR" ] && [ "$(ls -A "$AGENTS_DEST_DIR" 2>/dev/null)" ]; then
            mkdir -p "$BACKUP_DIR"
            if [ ! -d "$BACKUP_DIR/agents-backup" ]; then
                cp -r "$AGENTS_DEST_DIR" "$BACKUP_DIR/agents-backup"
                log_info "Backed up agents to ${BACKUP_DIR}/agents-backup"
            fi
        fi
        [ -f "$CONFIG_FILE" ] && create_backup "$CONFIG_FILE"
    fi

    # Lift customizations into agent-overrides.json BEFORE re-resolve
    lift_customizations

    # Mark migrated (skip write in dry-run)
    if [ "$DRY_RUN" = true ]; then
        log_success "[DRY-RUN] Would mark config as v${SCHEMA_VERSION}"
    else
        echo "$SCHEMA_VERSION" > "$CONFIG_VERSION_FILE"
        log_success "Migration to v${SCHEMA_VERSION} complete"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# PLUGIN DEPLOYMENT
# ─────────────────────────────────────────────────────────────────────────────

# Copy repo-owned plugins (plugins/*) into the global
# plugins dir so opencode auto-loads them. Mirrors the skills deploy pattern.
# These are NOT npm packages (those live in opencode.json `plugins[]`); they are
# local TS plugins auto-discovered from ~/.config/opencode/plugins/.
deploy_plugins() {
    echo ""
    log_info "Setting up plugins..."

    if [ ! -d "$PLUGINS_SRC_DIR" ]; then
        log_info "No repo plugins to deploy (${PLUGINS_SRC_DIR} not found). Skipping."
        return 0
    fi

    run_cmd mkdir -p "$PLUGINS_DEST_DIR"

    # #456 migration: plugins renamed with the opencode- prefix — drop stale
    # pre-rename copies so the same plugin never loads twice.
    for legacy in vibeguard.ts ponytail-scoped.ts question-repair.ts learnings-autoinject.ts learnings-autoinject.README.md; do
        run_cmd rm -f "$PLUGINS_DEST_DIR/$legacy"
    done

    # Copy each plugin subdirectory (skip dotfiles, node_modules).
    # Pre-copy change detection (activation gate): compare source vs the
    # CURRENT destination so the signal is identical in real runs and --dry-run
    # (the copy itself is a no-op in preview). diff -r -q is POSIX-portable.
    local count=0
    local changed=false
    for legacy in vibeguard.ts ponytail-scoped.ts question-repair.ts learnings-autoinject.ts learnings-autoinject.README.md; do
        [ -e "$PLUGINS_DEST_DIR/$legacy" ] && changed=true
    done
    for item in "${PLUGINS_SRC_DIR}"/*; do
        [ -e "$item" ] || continue  # robust against empty glob
        local name
        name=$(basename "$item")
        case "$name" in
            .*|node_modules) continue ;;
        esac
        if [ ! -e "${PLUGINS_DEST_DIR}/${name}" ] || ! diff -r -q "$item" "${PLUGINS_DEST_DIR}/${name}" >/dev/null 2>&1; then
            changed=true
        fi
        run_cmd cp -r "$item" "${PLUGINS_DEST_DIR}/"
        count=$((count + 1))
    done

    if [ "$count" -gt 0 ]; then
        log_success "Plugins copied successfully to ${PLUGINS_DEST_DIR} (${count} plugin$([ "$count" -ne 1 ] && echo s))"
    else
        log_info "No repo plugins found to deploy."
    fi

    # Activation: the background service loads plugins only at start, so a
    # changed plugin set takes effect after `opencode service restart`.
    # #588 lesson: routine re-deploys of an UNCHANGED set never restart (no
    # live-session interruptions). TTY-gated on purpose — headless contexts
    # (tests, CI, agent-driven runs) get the printed instruction instead of a
    # restart that would kill the very session running setup.sh. Bounded and
    # non-fatal: deploy_plugins is a critical plan step, a failed restart
    # warns and the deploy still succeeds.
    if [ "$changed" != true ]; then
        log_info "Plugin set unchanged - no service restart needed"
        return 0
    fi
    if ! command_exists opencode; then
        log_warn "Plugin set changed but opencode not found - run 'opencode service restart' manually to activate"
        return 0
    fi
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Would restart the opencode background service (plugin set changed)"
        return 0
    fi
    if [ ! -t 0 ]; then
        log_info "Plugin set changed - activate with: opencode service restart (restarts interrupt live opencode sessions)"
        return 0
    fi
    local restart_cmd=(opencode service restart)
    command_exists timeout && restart_cmd=(timeout 15 "${restart_cmd[@]}")
    log_info "Restarting opencode background service (plugin set changed) - live opencode sessions will be interrupted"
    if "${restart_cmd[@]}" >/dev/null 2>&1; then
        log_success "opencode service restarted - new plugins are active"
    else
        log_warn "opencode service restart failed - run it manually to activate the new plugins"
    fi
    return 0
}

# ─────────────────────────────────────────────────────────────────────────────
# AGENT DEPLOYMENT (v2.0 — resolver-driven)
# ─────────────────────────────────────────────────────────────────────────────
# Apply the skill profile (GIT-333): rewrites ONLY the skill rules
# (action:"skill") inside the permissions array of the DEPLOYED config
# (never the source deploy/opencode.json).
#   lean (default) -> 70 primary-visible skills + "*": "deny"
#   full           -> verified no-op (shipped allowlist stays verbatim)
# Mirrors run_pack_merger's dry-run contract (B1): in dry-run the resolver
# stages the preview config at $DRY_RUN_PREVIEW_DIR/opencode.json — patch that.
run_skill_profile() {
    if [ ! -f "$APPLY_SKILL_PROFILE_SCRIPT" ]; then
        log_error "Skill-profile applier not found: ${APPLY_SKILL_PROFILE_SCRIPT}"
        return 1
    fi
    if [ ! -f "$SKILL_PROFILES_FILE" ]; then
        log_error "Skill profiles file not found: ${SKILL_PROFILES_FILE}"
        return 1
    fi

    # D2 (#470): same declined-config guard as run_pack_merger.
    if [ "$SKIP_CONFIG_COPY" = true ] && [ ! -f "$CONFIG_FILE" ]; then
        log_warn "Skill profile requires a config you declined to create - skipping."
        return 0
    fi

    local target_config="$CONFIG_FILE"
    if [ "$DRY_RUN" = true ]; then
        target_config="${DRY_RUN_PREVIEW_DIR}/opencode.json"
        if [ ! -f "$target_config" ]; then
            log_error "Dry-run preview config not found: ${target_config}"
            log_error "The resolver must run first to stage the preview. Aborting skill-profile apply."
            return 1
        fi
    fi

    log_info "Applying skill profile: ${SKILL_PROFILE}"
    node "$APPLY_SKILL_PROFILE_SCRIPT" \
        --config "$target_config" \
        --profiles "$SKILL_PROFILES_FILE" \
        --profile "$SKILL_PROFILE"
    local rc=$?
    if [ "$rc" -ne 0 ]; then
        log_error "Skill-profile application failed (exit ${rc})"
        return 1
    fi
    return 0
}

# Single install path (#379): all content installs flow through the installer
# CLI so every deploy is manifest-tracked (update/remove work after this).
# Snapshots existing content first — the old prompt-default-no overwrite gate
# is replaced by an explicit backup-then-force-copy contract.
deploy_content() {
    echo ""
    log_info "Deploying content via installer CLI (manifest-tracked)..."

    if ! command_exists node; then
        log_error "Node.js is required by the installer CLI."
        return 1
    fi

    # Pre-overwrite snapshot (ARCH-4): preserve user edits before force-copy.
    # Unconditional mkdir — BACKUP_DIR may not exist yet on --yes redeploy (the
    # config-overwrite prompt auto-declines, so create_backup never ran).
    local content_backup="${BACKUP_DIR}/content-backup"
    if [ -d "$SKILLS_DIR" ] && [ -n "$(ls -A "$SKILLS_DIR" 2>/dev/null)" ]; then
        run_cmd mkdir -p "$content_backup"
        run_cmd cp -r "$SKILLS_DIR" "${content_backup}/skills"
        log_info "Snapshotted existing skills to ${content_backup}/skills"
    fi
    if [ -d "$AGENTS_DEST_DIR" ] && [ -n "$(ls -A "$AGENTS_DEST_DIR" 2>/dev/null)" ]; then
        run_cmd mkdir -p "$content_backup"
        run_cmd cp -r "$AGENTS_DEST_DIR" "${content_backup}/agents"
        log_info "Snapshotted existing agents to ${content_backup}/agents"
    fi

    local provider_arg=""
    [ -n "$PROVIDER" ] && provider_arg="--provider ${PROVIDER}"
    local dry_arg=""
    [ "$DRY_RUN" = true ] && dry_arg="--dry-run"

    node "${INSTALLER_DIR}/init.mjs" add --all --yes $provider_arg $dry_arg
    local rc=$?
    if [ "$rc" -ne 0 ]; then
        log_error "installer CLI failed (exit ${rc})"
        return "$rc"
    fi

    # Convergence pass (#608): `add` is additive-only by design (init.mjs
    # refuses --prune on add), so manifest-tracked entries whose names left
    # installer/registry.json linger forever without this pass. `update
    # --prune` removes exactly those (files + manifest rows) across recorded
    # targets. Non-fatal on purpose, mirroring update_manifest's rc-capture
    # idiom: exit 2 = pre-#379 manifest-less install (adoption hint); any
    # other failure warns with its exit code and the deploy continues —
    # reachability note: a successful `add` above writes the manifest, so
    # exit 2 in a real run effectively means the dry-run arm or an add that
    # half-failed; both deserve a warn, neither deserves a deploy abort.
    node "${INSTALLER_DIR}/init.mjs" update --prune $provider_arg $dry_arg
    local prune_rc=$?
    if [ "$prune_rc" -eq 2 ]; then
        log_warn "prune pass skipped - pre-#379 installs: one full re-run adopts the manifest"
    elif [ "$prune_rc" -ne 0 ]; then
        log_warn "prune pass failed (exit ${prune_rc}) - registry-removed entries may linger until the next successful pass"
    fi
    log_success "Content deployed ($(count_agents "${REPO_DIR}/agents") agents / $(count_skills "${REPO_DIR}/skills") skills, manifest-tracked)"
    return 0
}

deploy_agents() {
    echo ""
    log_info "Setting up agents (v2.0 model resolution)..."

    # Node is required for the resolver (@opencode/cli needs it anyway)
    if ! command_exists node; then
        log_error "Node.js is required to resolve agent models."
        log_error "Install Node.js first, then re-run this setup."
        log_warn "Skipping agent deployment."
        return 1
    fi

    if [ ! -d "$AGENTS_SRC_DIR" ]; then
        log_warn "agents/ source folder not found: ${AGENTS_SRC_DIR}"
        return 1
    fi

    run_cmd "mkdir -p ${AGENTS_DEST_DIR}"

    # Migration (detect pre-v2, backup, lift customizations) before resolve
    run_migration

    # Single install path (#379): content (agents + skills) installs through the
    # installer CLI — manifest-tracked, hashed, update-able. Runs AFTER migration
    # (lift must see pre-overwrite agents) and BEFORE the resolver (which now
    # resolves config only; the CLI injects models with the same precedence).
    deploy_content
    rc=$?
    if [ "$rc" -ne 0 ]; then
        log_error "Content deployment failed (exit ${rc})"
        return 1
    fi

    # Resolve + inject concrete models into the CONFIG (explore/general, primary).
    # Config-only call since #379 — agent files are written by deploy_content.
    log_info "Resolving agent models..."
    RESOLVER_CONFIG_ONLY=true run_resolver
    local rc=$?
    if [ "$rc" -ne 0 ]; then
        log_error "Model resolution failed (exit ${rc})"
        return 1
    fi

    # Apply provider packs (--enable-pack <csv>) if requested. Runs AFTER the
    # resolver so it merges into the resolved config. Mirrors run_resolver's
    # dry-run path (B1). No-op if $ENABLE_PACK is empty.
    run_pack_merger
    rc=$?
    if [ "$rc" -ne 0 ]; then
        log_error "Provider-pack application failed (exit ${rc})"
        return 1
    fi

    # Apply skill profile (--skill-profile lean|full, default lean). Runs LAST
    # so the rewrite lands on the final resolved+packed config. Subagents are
    # unaffected (frontmatter allows, GIT-333 Phase 1).
    run_skill_profile
    rc=$?
    if [ "$rc" -ne 0 ]; then
        log_error "Skill-profile application failed (exit ${rc})"
        return 1
    fi

    # Count deployed agents by mode
    local agent_count=0 primary_count=0 subagent_count=0
    for agent_file in "${AGENTS_DEST_DIR}"/*.md; do
        [ -f "$agent_file" ] || continue
        agent_count=$((agent_count + 1))
        if grep -q "^mode: primary" "$agent_file" 2>/dev/null; then
            primary_count=$((primary_count + 1))
        elif grep -q "^mode: subagent" "$agent_file" 2>/dev/null; then
            subagent_count=$((subagent_count + 1))
        fi
    done

    log_success "Deployed ${agent_count} agents (${subagent_count} subagents) to ${AGENTS_DEST_DIR}"
    echo "  Models resolved via tier registry."
    echo "  Change provider: ./setup.sh --provider <zai|anthropic|openai|openrouter>"
    echo "  Pin per-agent:   ~/.config/opencode/agent-overrides.json"
    return 0
}

# ─────────────────────────────────────────────────────────────────────────────
# DEPLOY PLAN MODEL (#470): one mode→steps mapping + one executor. Steps are
# "critical|id|label|function"; critical failures stop the plan and make the
# final exit code 1, non-critical failures warn and continue. Replaces the
# six+ early-exit branches whose callers swallowed failures with `|| true`
# and skipped backup/cleanup/summary entirely.
# ─────────────────────────────────────────────────────────────────────────────
PLAN_STEPS=()
PLAN_MODE=""
PLAN_FAILED_CRITICAL=""
PLAN_FAILED_COUNT=0

# Preconditions as steps (arch review): each mode carries the gates its
# branch used to run — skills-only re-checks opencode + deps, models-only /
# migrate-only require node. Manifest update is deliberately NON-critical:
# init.mjs update exits 2 on pre-#379 installs and #379 decided that is a
# warning (one full re-run adopts the manifest), not a failure.
build_plan() {
    validate_mode_conflicts
    PLAN_STEPS=()
    if [ "$ROLLBACK_MODE" = true ]; then
        PLAN_MODE="rollback"
        PLAN_STEPS+=("true|rollback|Restore from backup|rollback")
    elif [ "$UPDATE_ONLY" = true ]; then
        PLAN_MODE="update"
        PLAN_STEPS+=("true|update-cli|Update opencode CLI|update_opencode_cli")
    elif [ "$CHECK_UPDATE_ONLY" = true ]; then
        PLAN_MODE="check-update"
        PLAN_STEPS+=("true|deps|Dependency check|check_dependencies_strict")
        PLAN_STEPS+=("true|check-update|Check for updates|check_for_updates_only")
    elif [ "$CHECK_CATALOG_ONLY" = true ]; then
        PLAN_MODE="check-catalog"
        PLAN_STEPS+=("true|catalog-check|Check provider-models against models.dev|check_provider_catalog")
    elif [ "$LIST_ITEMS" = true ]; then
        PLAN_MODE="list-items"
        PLAN_STEPS+=("true|dump-catalog|Dump the deploy item catalog|dump_catalog")
    elif [ -n "$SAVE_PRESET_NAME" ]; then
        PLAN_MODE="save-preset"
        PLAN_STEPS+=("true|save-preset|Save user preset|save_user_preset")
    elif [ "$MODELS_ONLY" = true ]; then
        PLAN_MODE="models-only"
        PLAN_STEPS+=("true|node-check|Node.js required|node_required")
        PLAN_STEPS+=("false|provider|Select model provider|setup_model_provider")
        PLAN_STEPS+=("false|credentials|Capture provider credentials|setup_provider_credentials")
        PLAN_STEPS+=("true|resolver-config|Resolve models into config|resolve_models_config_only")
        PLAN_STEPS+=("false|manifest-update|Update agent manifest|update_manifest")
    elif [ "$MIGRATE_ONLY" = true ]; then
        PLAN_MODE="migrate-only"
        PLAN_STEPS+=("true|node-check|Node.js required|node_required")
        PLAN_STEPS+=("true|migrate|Run v2.0 migration|run_migration_only")
        PLAN_STEPS+=("true|resolver|Resolve models|run_resolver")
    elif [ "$PEONPING_ONLY" = true ]; then
        PLAN_MODE="peonping"
        PLAN_STEPS+=("true|deps|Dependency check|check_dependencies_strict")
        PLAN_STEPS+=("false|peonping|Install PeonPing sound notifications|setup_peonping")
    elif [ "$SKILLS_ONLY" = true ]; then
        PLAN_MODE="skills-only"
        PLAN_STEPS+=("true|opencode-check|Validate opencode install|validate_opencode_install")
        PLAN_STEPS+=("true|deps|Dependency check|check_dependencies_strict")
        if [ -n "$LOAD_PRESET_NAME" ]; then
            PLAN_STEPS+=("true|load-preset|Load preset ${LOAD_PRESET_NAME}|load_user_preset")
        fi
        PLAN_STEPS+=("true|config|Deploy config|setup_config")
        PLAN_STEPS+=("true|agents|Deploy agents|deploy_agents")
        PLAN_STEPS+=("true|plugins|Deploy plugins|deploy_plugins")
        PLAN_STEPS+=("false|init-symlink|Install opencode-init shim|setup_opencode_init_symlink")
        PLAN_STEPS+=("false|setup-symlink|Install opencode-setup shim|setup_opencode_setup_symlink")
        PLAN_STEPS+=("false|learnings|Set up learnings directory|setup_learnings_dir")
    else
        PLAN_MODE="full"
        PLAN_STEPS+=("true|deps|Dependency check|check_dependencies_strict")
        PLAN_STEPS+=("false|detect-agents|Detect installed coding agents|detect_installed_agents")
        if [ -n "$LOAD_PRESET_NAME" ]; then
            PLAN_STEPS+=("true|load-preset|Load preset ${LOAD_PRESET_NAME}|load_user_preset")
        fi
        if [ "$QUICK_SETUP" = false ]; then
            PLAN_STEPS+=("false|gh-cli|Set up GitHub CLI|setup_github_cli")
            PLAN_STEPS+=("false|zai-key|Configure Z.AI API key|setup_zai_api_key")
            PLAN_STEPS+=("false|nvm|Set up nvm|setup_nvm")
            PLAN_STEPS+=("false|nodejs|Set up Node.js|setup_nodejs")
            PLAN_STEPS+=("false|opencode-install|Install opencode CLI|setup_opencode")
        fi
        PLAN_STEPS+=("true|config|Deploy config|setup_config")
        PLAN_STEPS+=("false|provider|Select model provider|setup_model_provider")
        PLAN_STEPS+=("false|credentials|Capture provider credentials|setup_provider_credentials")
        PLAN_STEPS+=("false|seed-agent-keys|Seed Z.AI key into detected agents|seed_agent_keys")
        if [ "$SELECT_ITEMS" = true ]; then
            # Per-item picker (#473): selection replaces the blanket content
            # deploy. Steps APPEND here (never interleave — deploy_delegate
            # line-order pin); consumption gates on THIS RUN's flag + the plan
            # file (a stale plan from a prior run must never alter this one).
            PLAN_STEPS+=("false|provision-tui|Provision picker dependencies|provision_picker_deps")
            PLAN_STEPS+=("true|select-items|Select items to deploy|run_item_picker")
            PLAN_STEPS+=("true|deploy-selected-skills|Deploy selected skills|deploy_selected_skills")
            PLAN_STEPS+=("true|deploy-selected-agents|Deploy selected agents|deploy_selected_agents")
            PLAN_STEPS+=("true|prune-registry-removed|Prune registry-removed entries|deploy_selected_prune")
            PLAN_STEPS+=("false|apply-selected-extras|Apply selected packs|apply_selected_packs_extras")
        else
            PLAN_STEPS+=("true|agents|Deploy agents|deploy_agents")
            PLAN_STEPS+=("true|plugins|Deploy plugins|deploy_plugins")
        fi
        PLAN_STEPS+=("false|init-symlink|Install opencode-init shim|setup_opencode_init_symlink")
        PLAN_STEPS+=("false|setup-symlink|Install opencode-setup shim|setup_opencode_setup_symlink")
        PLAN_STEPS+=("false|learnings|Set up learnings directory|setup_learnings_dir")
        PLAN_STEPS+=("false|shell-vars|Set up shell variables|setup_shell_vars")
    fi
}

# The single executor (#470): failures are owned HERE, not by callers.
run_plan() {
    PLAN_FAILED_CRITICAL=""
    PLAN_FAILED_COUNT=0
    local entry critical id label func
    for entry in "${PLAN_STEPS[@]}"; do
        IFS='|' read -r critical id label func <<< "$entry"
        log_info "Plan step: $label"
        if ! "$func"; then
            if [ "$critical" = "true" ]; then
                log_error "Critical step failed: $label"
                PLAN_FAILED_CRITICAL="$id"
                return 1
            fi
            log_warn "Non-critical step failed (continuing): $label"
            PLAN_FAILED_COUNT=$((PLAN_FAILED_COUNT + 1))
        fi
    done
    return 0
}

# ── Extracted step functions (behavior-preserving; placed below deploy_agents
# to preserve deploy_delegate.bats' first-occurrence line-order pin) ──

node_required() {
    if ! command_exists node; then
        log_error "Node.js is required for model resolution."
        return 1
    fi
    return 0
}

check_dependencies_strict() {
    if ! check_dependencies; then
        log_error "Dependency check failed. Please install missing dependencies."
        return 1
    fi
    return 0
}

validate_opencode_install() {
    log_info "Validating OpenCode installation..."
    if command_exists opencode; then
        log_success "OpenCode is installed ($(opencode --version 2>/dev/null))"
        return 0
    fi
    log_error "OpenCode CLI is not installed globally"
    log_info "Please install OpenCode first: npm install -g @opencode/cli"
    return 1
}

resolve_models_config_only() {
    RESOLVER_CONFIG_ONLY=true run_resolver
}

update_manifest() {
    # Dry-run safe (#467): cmdUpdate gates writes and prune on !dry.
    # NOTE: a conditional-expansion gate (${VAR:+word} form) would expand on
    # the non-empty string "false" and permanently dry real runs — the
    # explicit comparison form below is deliberate (see test_dry_run_leaks).
    local dry_arg=""
    [ "$DRY_RUN" = true ] && dry_arg="--dry-run"
    node "${INSTALLER_DIR}/init.mjs" update ${PROVIDER:+--provider ${PROVIDER}} ${dry_arg}
    local rc=$?
    if [ "$rc" -ne 0 ]; then
        # #379 contract: pre-#379 installs warn-and-continue (non-critical).
        log_warn "manifest update skipped (exit ${rc}) — pre-#379 installs: one full ./deploy/setup.sh run adopts the manifest"
    fi
    return 0
}

# Seed the Z.AI provider into the pi coding agent's config (#573). Gated on
# detection + a captured key; delegates the merge to deploy/seed-pi-provider.mjs
# (merge-never-clobber, dry-run aware, 0600 output). Non-fatal on every path.
seed_pi_provider() {
    if [ "${PI_INSTALLED:-false}" != true ]; then
        log_info "pi not detected - skipping Z.AI provider seed"
        return 0
    fi
    if [ -z "${ZAI_API_KEY:-}" ]; then
        log_warn "pi detected but no ZAI_API_KEY captured - skipping provider seed"
        return 0
    fi
    local pi_config="${HOME}/.pi/agent/models.json"
    if [ "$DRY_RUN" = true ]; then
        echo "[DRY-RUN] Would run: node ${DEPLOY_DIR}/seed-pi-provider.mjs --config ${pi_config}"
        return 0
    fi
    log_info "Seeding Z.AI provider into pi (${pi_config})"
    if ! node "${DEPLOY_DIR}/seed-pi-provider.mjs" --config "$pi_config"; then
        log_warn "pi provider seed failed - pi remains unconfigured (non-fatal)"
        return 0
    fi
    log_success "pi: zai provider seeded (apiKey resolves from \$ZAI_API_KEY at runtime)"
    # Best-effort verification: pi reloads models.json on every /model open;
    # the probe confirms the file parses from pi's perspective.
    if command_exists pi && command_exists timeout; then
        if timeout 15 pi --list-models >/dev/null 2>&1; then
            log_success "pi --list-models OK (provider visible)"
        else
            log_warn "pi --list-models probe failed (non-fatal - check ~/.pi/agent/models.json)"
        fi
    fi
    return 0
}

# Seed the Z.AI provider into the codex CLI's config (#573). Guarded TOML
# append — never rewrites user content, never sets the global default model
# (activation is opt-in via `codex --profile zai`). Guards on BOTH section
# headers: appending a table that already exists is a TOML parse error, so a
# user-defined zai provider or profile skips with a note instead of
# corrupting the file. Non-fatal on every path.
seed_codex_provider() {
    if [ "${CODEX_INSTALLED:-false}" != true ]; then
        log_info "codex not detected - skipping Z.AI provider seed"
        return 0
    fi
    if [ -z "${ZAI_API_KEY:-}" ]; then
        log_warn "codex detected but no ZAI_API_KEY captured - skipping provider seed"
        return 0
    fi
    local codex_config="${HOME}/.codex/config.toml"
    if [ "$DRY_RUN" = true ]; then
        echo "[DRY-RUN] Would append Z.AI provider block to ${codex_config}"
        return 0
    fi
    if grep -q '^\[model_providers\.zai\]' "$codex_config" 2>/dev/null \
        || grep -q '^model_providers\.zai\.' "$codex_config" 2>/dev/null; then
        log_info "codex config already defines [model_providers.zai] - leaving ${codex_config} untouched"
        return 0
    fi
    if grep -q '^\[profiles\.zai\]' "$codex_config" 2>/dev/null \
        || grep -q '^profiles\.zai\.' "$codex_config" 2>/dev/null; then
        log_info "codex config already defines [profiles.zai] - leaving ${codex_config} untouched"
        return 0
    fi
    mkdir -p "${HOME}/.codex"
    if cat >> "$codex_config" <<'EOF'

# --- Z.AI provider (added by opencode setup, #573) ---
# codex supports wire_api = "responses" only, so base_url points at Z.AI's
# OpenAI Responses endpoint. Source of truth for the endpoint (verified
# 2026-09-26): Z.AI devpack docs "Coding Endpoint" table lists
#   Protocol "OpenAI Responses" -> base https://api.z.ai/api/v1
# (https://docs.z.ai/devpack/tool/others). NOT the PAAS chat-completions
# base pi uses (api/paas/v4 speaks openai-completions, not Responses).
# If Z.AI revises this, update here + tests + README together.
# env_key names the env var codex reads per invocation - the key itself is
# never stored in this file.
[model_providers.zai]
name = "Z.AI"
base_url = "https://api.z.ai/api/v1"
env_key = "ZAI_API_KEY"

# Opt-in activation: `codex --profile zai` (global default model untouched).
[profiles.zai]
model_provider = "zai"
model = "glm-5.3"
EOF
    then
        log_success "codex: zai provider appended to ${codex_config} (activate: codex --profile zai)"
    else
        log_warn "codex: failed to append Z.AI provider block to ${codex_config} (non-fatal)"
    fi
    return 0
}

# Plan-step entry: seed the captured provider key into every detected agent
# (#573). Future agents (claude, kimi, kilo) join as additional calls here.
seed_agent_keys() {
    seed_pi_provider
    seed_codex_provider
    return 0
}

# ── Provider credentials (#471): the identity step, coupled to provider
# selection. Resolves the chosen preset (flag → models map → defaults), reads
# its credential block, captures the key (env var headless, masked prompt
# interactive), seeds auth.json for EACH auth_id (merge-never-clobber), and
# verifies via `opencode auth list` when opencode is installed. OAuth presets
# print the manual login hint instead of prompting.
setup_provider_credentials() {
    local chosen=""
    if [ -n "$PROVIDER" ]; then
        chosen="$PROVIDER"
    else
        # Derive the provider prefix from the deployed models map, falling back
        # to the shipped defaults (local deploys omit primary → zai-coding-plan).
        chosen="$(node -e '
            const fs = require("fs");
            const read = (f) => { try { return JSON.parse(fs.readFileSync(f, "utf8")); } catch { return null; } };
            const map = read(process.argv[1]) || read(process.argv[2]);
            const primary = map && (map.primary || (map.tiers && map.tiers.primary));
            if (primary) console.log(String(primary).split("/")[0]);
        ' "$USER_MODELS_MAP" "$MODELS_DEFAULT_MAP" 2>/dev/null)"
    fi
    [ -z "$chosen" ] && { log_info "No model provider selected - skipping credential capture"; return 0; }

    # Credential block lookup: match preset name OR any of its auth_ids.
    local block
    block="$(node -e '
        const fs = require("fs");
        const pp = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
        const presets = pp.presets || pp;
        const chosen = process.argv[2];
        for (const p of Object.values(presets)) {
            const c = p.credential;
            if (c && (p.primary || c.auth_ids) &&
                (Object.keys(presets).find(n => presets[n] === p) === chosen || c.auth_ids.includes(chosen))) {
                console.log(JSON.stringify(c));
                break;
            }
        }
    ' "$PROVIDER_PRESETS" "$chosen" 2>/dev/null)"
    [ -z "$block" ] && { log_info "Provider '${chosen}' needs no credential - skipping"; return 0; }

    local auth_ids env_var oauth
    auth_ids="$(node -e 'console.log(JSON.stringify(JSON.parse(process.argv[1]).auth_ids))' "$block")"
    env_var="$(node -e 'console.log(JSON.parse(process.argv[1]).env_var)' "$block")"
    oauth="$(node -e 'console.log(JSON.parse(process.argv[1]).oauth ? "true" : "false")' "$block")"

    # Dry-run preview stops before any capture (the prompt would collect a
    # secret that the gate then discards — cleaner to not ask).
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Would capture credentials for provider '${chosen}'"
        return 0
    fi

    if [ "$oauth" = "true" ]; then
        # OAuth-capable providers authenticate via opencode's own interactive
        # login — a headless key prompt would be wrong UX (AC: hint, no prompt).
        local oid
        for oid in $(node -e 'console.log(JSON.parse(process.argv[1]).auth_ids.join(" "))' "$block"); do
            log_info "OAuth provider: run 'opencode auth login ${oid}' to authenticate (interactive)"
        done
        return 0
    fi

    # Idempotent: all auth_ids already seeded and no fresh env key ⇒ skip
    # (re-runs must not re-prompt for a key that is already in auth.json).
    if [ -z "${!env_var:-}" ] && [ -f "${XDG_DATA_HOME:-$HOME/.local/share}/opencode/auth.json" ]; then
        if node -e '
            const fs = require("fs");
            const auth = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
            const ids = JSON.parse(process.argv[2]);
            process.exit(ids.every(id => auth[id] && auth[id].key) ? 0 : 1);
        ' "${XDG_DATA_HOME:-$HOME/.local/share}/opencode/auth.json" "$auth_ids" 2>/dev/null; then
            log_info "Provider '${chosen}' credentials already seeded - skipping capture"
            return 0
        fi
    fi

    # Capture: env var first (headless), then a masked prompt (interactive).
    local key="${!env_var:-}"
    if [ -z "$key" ] && [ -t 0 ] && [ "$AUTO_ACCEPT" = false ]; then
        echo ""
        echo "  Credential for provider '${chosen}' (env \${${env_var}})"
        read -rs -p "  ${env_var} (input hidden, Enter to skip): " key
        echo ""
    fi
    if [ -z "$key" ]; then
        log_warn "No ${env_var} provided - provider '${chosen}' stays unauthenticated (set ${env_var} and re-run)"
        return 0
    fi

    # #588: identical-key idempotency. The pre-prompt gate above only fires
    # when the env var is UNSET, so an exported key (persisted by
    # setup_shell_vars) re-seeded AND restarted the background service on
    # every run — killing live opencode sessions although nothing changed.
    # auth.json already holding this exact key for every auth_id means this
    # run changes nothing: skip the re-seed and the #573 service restart.
    local auth_file="${XDG_DATA_HOME:-$HOME/.local/share}/opencode/auth.json"
    if [ -f "$auth_file" ]; then
        if AUTH_KEY="$key" node -e '
            const fs = require("fs");
            const auth = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
            const ids = JSON.parse(process.argv[2]);
            const key = process.env.AUTH_KEY.trim();
            process.exit(ids.every(id => auth[id] && auth[id].key === key) ? 0 : 1);
        ' "$auth_file" "$auth_ids" 2>/dev/null; then
            log_info "Provider '${chosen}' credentials unchanged (auth.json already holds this key) - skipping re-seed and service restart"
            return 0
        fi
    fi

    # Seed EVERY auth_id (merge-never-clobber inside register_provider_auth).
    local oid
    for oid in $(node -e 'console.log(JSON.parse(process.argv[1]).auth_ids.join(" "))' "$block"); do
        register_provider_auth "$oid" "$key"
    done

    # Verify via opencode's own view when it is installed. Exit status is the
    # check — opencode renders provider DISPLAY names ("Z.AI Coding Plan"),
    # not raw auth ids, so id-substring matching is unreliable.
    if command_exists opencode; then
        # Bounded: on a never-run opencode state dir the list command can stall
        # (first-run initialization) — the verify is advisory, cap it at 15s.
        local verify_cmd=(opencode auth list)
        command_exists timeout && verify_cmd=(timeout 15 "${verify_cmd[@]}")
        local listing
        if listing="$("${verify_cmd[@]}" 2>/dev/null)"; then
            log_success "Credentials registered (verified via 'opencode auth list'):"
            if [ -n "$listing" ]; then
                while IFS= read -r line; do log_info "  ${line}"; done <<< "$listing"
            fi
        else
            log_warn "Could not verify the seeded credential via 'opencode auth list'"
        fi
    else
        log_warn "opencode not found - skipping credential verification"
    fi

    # #573: the v2 background service captures its environment at start, so a
    # freshly seeded key does not reach {env:ZAI_API_KEY} MCP servers
    # (zai-web-reader/search) until the service restarts. Best-effort and
    # bounded — a failed restart never fails setup. Only reached on the path
    # where a key was seeded this run (earlier returns skip it by design).
    if command_exists opencode; then
        # The restarted service inherits the CLI's environment, so the key
        # must be EXPORTED here — a read-captured (prompted) ZAI_API_KEY is
        # shell-local and otherwise never reaches the spawned service, while
        # the success log below would still print (review #573 Major 2).
        [ -n "${ZAI_API_KEY:-}" ] && export ZAI_API_KEY
        local restart_cmd=(opencode service restart)
        command_exists timeout && restart_cmd=(timeout 15 "${restart_cmd[@]}")
        if [ "$DRY_RUN" = true ]; then
            log_info "[DRY-RUN] Would restart the opencode background service (env pickup for {env:} MCP vars)"
        else
            # Announce before acting (#588): the restart interrupts any live
            # opencode session — never do that silently.
            log_info "Restarting opencode background service (new key seeded) - live opencode sessions will be interrupted"
            if "${restart_cmd[@]}" >/dev/null 2>&1; then
                log_success "opencode service restarted - MCP {env:} substitution now sees the new key"
            else
                log_warn "opencode service restart failed - run 'opencode service restart' manually so MCP servers pick up ZAI_API_KEY"
            fi
        fi
    fi
    return 0
}

check_provider_catalog() {
    node "${DEPLOY_DIR}/regen-provider-models.mjs" --check
}

# ── Per-item picker steps (#473) ──
provision_picker_deps() {
    # The dashboard dep is only needed interactively; fresh clones have no
    # node_modules, so provision it here (network-gated, non-critical — the
    # picker falls back to linear prompts when this fails).
    if [ -d "${REPO_DIR}/node_modules/@opentui/core" ]; then
        return 0
    fi
    log_info "Provisioning picker dependencies (npm ci --omit=dev)..."
    if (cd "${REPO_DIR}" && npm ci --omit=dev >/dev/null 2>&1); then
        return 0
    fi
    log_warn "npm ci failed - the picker falls back to linear prompts"
    return 1
}

run_item_picker() {
    if [ "$DRY_RUN" = true ]; then
        # W6: dry-run reads a PRE-SEEDED plan only — it never runs the picker
        # (which would write one for real) and previews the consumption.
        if [ ! -f "$SELECT_PLAN_FILE" ]; then
            log_warn "Dry-run --select: no pre-seeded plan at ${SELECT_PLAN_FILE} - nothing to preview"
            return 1
        fi
        log_info "[DRY-RUN] Would deploy items from ${SELECT_PLAN_FILE}:"
        node -e 'const p=require(process.argv[1]); for (const g of ["skills","agents","mcps"]) console.log("  "+g+": "+((p[g]||[]).map(i=>i.name).join(", ")||"(none)"))' "$SELECT_PLAN_FILE" 2>/dev/null || true
        return 0
    fi
    node "$TUI_SCRIPT" select-items --out "$SELECT_PLAN_FILE"
}

deploy_selected_group() {
    # $1 = plan group (skills|agents). Direct picks only — locked-by items are
    # pulled in automatically by init.mjs add's requiresSkills closure (#439).
    # Dry-run (#473 review BLOCK): the child CLI gets its own --dry-run —
    # boolean-safe array form, never ${DRY_RUN:+} (that shape fires on "false").
    [ -f "$SELECT_PLAN_FILE" ] || { log_error "No selection plan at ${SELECT_PLAN_FILE}"; return 1; }
    local names
    names=$(node -e 'const p=require(process.argv[1]); console.log((p[process.argv[2]]||[]).filter(i=>i.source==="direct").map(i=>i.name).join(" "))' "$SELECT_PLAN_FILE" "$1")
    [ -z "$names" ] && { log_info "No $1 selected"; return 0; }
    # Length-guard before expansion: stock macOS bash 3.2 (no bash-4 features
    # used in this script) treats "${arr[@]}" on an EMPTY array as unset under
    # nounset — real (non-dry) --select runs would crash there.
    local dry_args=""
    if [ "$DRY_RUN" = true ]; then
        dry_args="--dry-run"
        node "${INSTALLER_DIR}/init.mjs" add $names $dry_args ${PROVIDER:+--provider ${PROVIDER}} || return 1
    else
        node "${INSTALLER_DIR}/init.mjs" add $names ${PROVIDER:+--provider ${PROVIDER}} || return 1
    fi
    return 0
    return 0
}

deploy_selected_skills() {
    deploy_selected_group skills
}

deploy_selected_agents() {
    deploy_selected_group agents
}

deploy_selected_prune() {
    # #610: converge the --select deploy with the registry — remove
    # manifest-tracked entries whose names left installer/registry.json.
    # Boolean-safe dry_args (see deploy_selected_group's nounset note).
    local dry_args=""
    if [ "$DRY_RUN" = true ]; then
        dry_args="--dry-run"
    fi
    node "${INSTALLER_DIR}/init.mjs" prune $dry_args
}

apply_selected_packs_extras() {
    local failed=0
    local packs
    packs=$(node -e 'const p=require(process.argv[1]); console.log((p.packs||[]).join(","))' "$SELECT_PLAN_FILE" 2>/dev/null)
    if [ -n "$packs" ]; then
        ENABLE_PACK="$packs" run_pack_merger || { log_warn "pack merge failed (non-critical)"; failed=1; }
    fi
    # Selected plugins: copy only the picked opencode-* plugins (#473 review —
    # plan.plugins was recorded but never consumed).
    local plugin_count
    plugin_count=$(node -e 'const p=require(process.argv[1]); console.log((p.plugins||[]).length)' "$SELECT_PLAN_FILE" 2>/dev/null)
    if [ "${plugin_count:-0}" -gt 0 ]; then
        run_cmd mkdir -p "${CONFIG_DIR}/plugins"
        for pname in $(node -e 'const p=require(process.argv[1]); console.log((p.plugins||[]).join(" "))' "$SELECT_PLAN_FILE" 2>/dev/null); do
            run_cmd cp -r "${REPO_DIR}/plugins/${pname}" "${CONFIG_DIR}/plugins/${pname}" || { failed=1; continue; }
            # Companion artifacts come from dependency-map.json pluginCompanions
            # (#537): one declarative home shared with the manifest path —
            # never fork plugin companion knowledge into shell case arms.
            # Trailing-slash entries are whole directories (shipsPlugins
            # semantics); rm-first keeps re-runs idempotent (cp -r into an
            # existing dir would nest a duplicate tree).
            # Fail-closed lookup (#537 review): a broken dependency-map must
            # fail the run, never silently skip companions beside the
            # consume-once plan deletion. Assignment on its own line — `local`
            # would mask the exit status.
            local comps
            comps=$(node -e '
                const m = require(process.argv[1]).pluginCompanions || {};
                console.log((m[process.argv[2]] || []).join(" "));
            ' "${REPO_DIR}/installer/dependency-map.json" "$pname" 2>/dev/null) || { log_warn "companion lookup failed for ${pname} (dependency-map.json unreadable?) - plugin may deploy broken"; failed=1; continue; }
            for comp in $comps; do
                # Hardening (#537 review): repo-trusted JSON today — still
                # refuse to rm/cp entries with spaces or traversal.
                case "$comp" in
                    *\ *|*..*) log_warn "refusing suspicious companion entry: ${comp}"; failed=1; continue ;;
                esac
                case "$comp" in
                    */)
                        run_cmd rm -rf "${CONFIG_DIR}/plugins/${comp%/}" || { failed=1; continue; }
                        run_cmd cp -r "${REPO_DIR}/plugins/${comp%/}" "${CONFIG_DIR}/plugins/${comp%/}" || { failed=1; }
                        ;;
                    *)
                        run_cmd cp "${REPO_DIR}/plugins/${comp}" "${CONFIG_DIR}/plugins/${comp}" || { failed=1; }
                        ;;
                esac
            done
        done
    fi
    # Consume-once (B2): the plan is spent only after a SUCCESSFUL deployment —
    # a failed non-critical piece keeps the file so a re-run can retry; never
    # deleted under dry-run.
    if [ "$failed" -eq 0 ] && [ "$DRY_RUN" != true ]; then
        rm -f "$SELECT_PLAN_FILE"
    fi
    return 0
}

dump_catalog() {
    # Packs/plugins come from the shared scanners (deploy-plan-items.mjs,
    # #537) — never hardcode empty arrays here again. Module path is argv-
    # passed ABSOLUTE (pathToFileURL): node -e import() resolves relative
    # specifiers against the process cwd, and setup.sh runs from any cwd
    # via the opencode-setup PATH shim.
    node -e '
        const { pathToFileURL } = require("node:url");
        const registry = require(process.argv[1]);
        import(pathToFileURL(process.argv[2]).href).then(({ scanPackNames, scanPluginNames }) => {
            const out = { skills: {}, agents: {}, packs: [], plugins: [], extras: [] };
            for (const s of registry.skills) { (out.skills[s.category || "Uncategorized"] ||= []).push(s.name); }
            for (const a of registry.agents) { (out.agents[a.tier || "unassigned"] ||= []).push(a.stem); }
            out.packs = scanPackNames(process.argv[3]).sort();
            out.plugins = scanPluginNames(process.argv[4]).sort();
            console.log(JSON.stringify(out, null, 2));
        }).catch((e) => { console.error(e && e.message ? e.message : e); process.exit(1); });
    ' "${REPO_DIR}/installer/registry.json" "${REPO_DIR}/installer/deploy-plan-items.mjs" "${REPO_DIR}/deploy/packs" "${REPO_DIR}/plugins"
}

save_user_preset() {
    case "$SAVE_PRESET_NAME" in
        */*|""|.*) log_error "Invalid preset name: '${SAVE_PRESET_NAME}'"; return 1 ;;
    esac
    local preset_dir="${CONFIG_DIR}/presets/${SAVE_PRESET_NAME}"
    run_cmd mkdir -p "$preset_dir"
    if [ -f "$USER_MODELS_MAP" ]; then
        run_cmd cp "$USER_MODELS_MAP" "${preset_dir}/models.json"
    fi
    if [ -f "$SELECT_PLAN_FILE" ]; then
        run_cmd cp "$SELECT_PLAN_FILE" "${preset_dir}/deploy-plan.json"
    fi
    log_success "Preset '${SAVE_PRESET_NAME}' saved to ${preset_dir}"
}

load_user_preset() {
    local preset_dir="${CONFIG_DIR}/presets/${LOAD_PRESET_NAME}"
    if [ ! -d "$preset_dir" ]; then
        log_error "Preset not found: ${preset_dir}"
        return 1
    fi
    if [ -f "${preset_dir}/models.json" ]; then
        node -e 'JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"))' "${preset_dir}/models.json" || { log_error "Preset models.json is not valid JSON"; return 1; }
        run_cmd cp "${preset_dir}/models.json" "${USER_MODELS_MAP}"
    fi
    if [ -f "${preset_dir}/deploy-plan.json" ]; then
        run_cmd cp "${preset_dir}/deploy-plan.json" "${SELECT_PLAN_FILE}"
    fi
    return 0
}

run_migration_only() {
    # NOTE: run_migration currently has no failure path (all returns 0); if it
    # gains one, propagate it here — this critical step would otherwise mask it
    # with run_resolver's status.
    run_cmd "mkdir -p ${AGENTS_DEST_DIR}"
    run_migration
    run_resolver
}

setup_learnings_dir() {
    log_info "Setting up user-level learnings directory..."

    local LEARNINGS_DIR

    local LEARNINGS_DIR="${CONFIG_DIR}/learnings"
    local learnings_categories=("patterns" "decisions" "anti-patterns" "solutions" "conventions")

    if [ ! -d "${LEARNINGS_DIR}" ]; then
        run_cmd mkdir -p "$LEARNINGS_DIR"
        log_info "Created ${LEARNINGS_DIR}"
    fi

    for category in "${learnings_categories[@]}"; do
        local category_dir="${LEARNINGS_DIR}/${category}"
        if [ ! -d "${category_dir}" ]; then
            run_cmd mkdir -p "$category_dir"
            run_cmd touch "${category_dir}/.gitkeep"
        fi
    done

    if [ ! -f "${LEARNINGS_DIR}/_index.md" ]; then
        # Dry-run safe (#467): this heredoc bypasses run_cmd and would create
        # a real file during a preview.
        if [ "$DRY_RUN" = true ]; then
            log_info "[DRY-RUN] Would create _index.md template"
        else
            cat > "${LEARNINGS_DIR}/_index.md" << 'LEARNINGS_INDEX'
# LEARNINGS Index (User-Level)

<!-- AUTO-GENERATED — manual edits to the listing below will be overwritten on next learning write -->

## Folder Structure

| Folder | Purpose |
|--------|---------|
| `patterns/` | Reusable code/architecture patterns (cross-project) |
| `decisions/` | Personal architectural decisions |
| `anti-patterns/` | Things to avoid |
| `solutions/` | Non-obvious fixes worth remembering |
| `conventions/` | Personal coding standards |

## Entries

<!-- Entries are appended here automatically when new learnings are saved -->

<!-- No entries yet -->
LEARNINGS_INDEX
        fi
        log_info "Created _index.md template"
    fi

    log_success "User-level learnings directory ready at ${LEARNINGS_DIR}"
}

# Check if running on Windows (native or Git Bash)
is_windows() {
    case "$DETECTED_OS" in
        Windows*|Windows-GitBash) return 0 ;;
        *) return 1 ;;
    esac
}

# Set a user-level environment variable on Windows using setx
# Falls back gracefully if setx is not available
setx_env() {
    local key="$1"
    local value="$2"

    if ! command_exists setx; then
        log_warn "setx not found - skipping system env var for ${key}"
        return 1
    fi

    log_debug "Setting Windows env var: ${key} via setx"
    # Dry-run safe (#469 class sweep): setx persists a user env var — never
    # during a preview.
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Would set ${key} via setx (value suppressed)"
        return 0
    fi
    setx "$key" "$value" > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        log_success "${key} set via setx (available in new terminals)"
    else
        log_warn "setx failed for ${key}"
        return 1
    fi
}

# Register the PAYG `zai` provider credential in opencode's native auth store
# (~/.local/share/opencode/auth.json) so `opencode auth list` shows it and the
# built-in `zai` provider resolves (e.g. zai/glm-5.3-flash vision fallback).
# Mirrors the Docker entrypoint's auth["zai"] write. MERGES — never clobbers
# existing entries (zai-coding-plan, gemini, ...). Idempotent. MCP servers still
# read {env:ZAI_API_KEY} independently — this only authenticates the model provider.
register_provider_auth() {
    # Generalized auth.json seeder (#471): merge-never-clobber — writes only
    # auth[auth_id], preserving every other entry. Dry-run and python3-safe.
    local auth_id="$1"
    local key="$2"
    [ -z "$key" ] && return 0
    if [ "$DRY_RUN" = true ]; then
        echo "[DRY-RUN] Would register $auth_id credential in ~/.local/share/opencode/auth.json"
        return 0
    fi
    if ! command_exists python3; then
        log_warn "python3 not found — skipping auth.json registration for $auth_id (provider stays unauthenticated)"
        return 0
    fi
    local auth_dir="${XDG_DATA_HOME:-$HOME/.local/share}/opencode"
    local auth_file="${auth_dir}/auth.json"
    AUTH_ID="$auth_id" AUTH_KEY="$key" python3 - "$auth_file" "$auth_dir" <<'PYEOF'
import json, os, sys
auth_file, auth_dir = sys.argv[1], sys.argv[2]
auth_id = os.environ.get("AUTH_ID", "").strip()
key = os.environ.get("AUTH_KEY", "").strip()
if not auth_id or not key:
    sys.exit(0)
auth = {}
try:
    with open(auth_file) as f:
        loaded = json.load(f)
        if isinstance(loaded, dict):
            auth = loaded
        else:
            raise ValueError("auth.json is not an object")
except FileNotFoundError:
    pass
except ValueError:
    # Merge-never-clobber must hold even for corrupt files (#471 review): a
    # half-written auth.json must not be silently replaced (that would destroy
    # every stored credential) — park it and start fresh, loudly.
    backup = auth_file + ".corrupt.bak"
    try:
        os.replace(auth_file, backup)
        print(f"  warning: auth.json was unparseable — moved to {backup}", file=sys.stderr)
    except OSError:
        pass
auth[auth_id] = {"type": "api", "key": key}
os.makedirs(auth_dir, exist_ok=True)
with open(auth_file, "w") as f:
    json.dump(auth, f, indent=2)
os.chmod(auth_file, 0o600)  # API keys at rest — not group/world-readable
print("  auth.json providers: " + ", ".join(sorted(auth.keys())))
PYEOF
}

# Setup environment variables in shell config (bashrc, zshrc, etc.)
setup_shell_vars() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "              🔐 Environment Variables Setup"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Detected shell: ${DETECTED_SHELL}"
    echo "Config file: ${SHELL_CONFIG_FILE}"
    if is_windows; then
        echo "Platform: Windows (using setx for system-wide env vars)"
    fi
    echo ""

    # On Windows, use setx for system-wide access (all shells + opencode)
    # On non-Windows, use shell config file (bashrc/zshrc)
    if is_windows; then
        log_info "Windows detected: setting env vars via setx (available in all terminals)"
    fi

    # Add ZAI_API_KEY
    if [ -n "$ZAI_API_KEY" ]; then
        if is_windows; then
            setx_env "ZAI_API_KEY" "${ZAI_API_KEY}"
            export ZAI_API_KEY="${ZAI_API_KEY}"
        else
            if grep -q "ZAI_API_KEY" "$SHELL_CONFIG_FILE" 2>/dev/null; then
                log_info "ZAI_API_KEY already exists in ${SHELL_CONFIG_FILE}"
            else
                if prompt_yes_no "Add ZAI_API_KEY to $(basename "${SHELL_CONFIG_FILE}") for persistent access?" "y"; then
                    create_backup "$SHELL_CONFIG_FILE"
                    run_cmd "printf '%s\\n' 'export ZAI_API_KEY=\"${ZAI_API_KEY}\"' >> \"${SHELL_CONFIG_FILE}\""
                    log_success "ZAI_API_KEY added to ${SHELL_CONFIG_FILE}"
                else
                    log_info "Skipping shell config update for ZAI_API_KEY"
                fi
            fi
        fi
    fi

    # Register a provider credential (see the generalized contract below) in opencode's native auth store so it
    # resolves identically to the Docker path (single credential mechanism).
    # auth.json seeding moved to setup_provider_credentials (#471) — the
    # identity layer, coupled to provider selection, not shell-vars.

    # Offer to install autoresearch protocol helpers (ar-enable / ar-disable)
    # into existing bashrc / zshrc. Prompted — never silent.
    if ! is_windows; then
        local rc_files=()
        [ -f "$HOME/.bashrc" ] && rc_files+=("$HOME/.bashrc")
        [ -f "$HOME/.zshrc" ] && rc_files+=("$HOME/.zshrc")
        if [ ${#rc_files[@]} -gt 0 ]; then
            local already_present=true
            for rc in "${rc_files[@]}"; do
                grep -q 'ar-enable()' "$rc" 2>/dev/null || already_present=false
            done
            if [ "$already_present" = false ]; then
                if prompt_yes_no "Install 'ar-enable' / 'ar-disable' helpers in your shell rc?" "n"; then
                    for rc in "${rc_files[@]}"; do
                        if ! grep -q 'ar-enable()' "$rc" 2>/dev/null; then
                            create_backup "$rc"
                            {
                                echo ''
                                echo '# autoresearch protocol helpers (added by opencode setup)'
                                echo 'ar-enable()  { export AUTORESEARCH_PROTOCOL=1; echo "autoresearch protocol: ON"; }'
                                echo 'ar-disable() { unset AUTORESEARCH_PROTOCOL;   echo "autoresearch protocol: OFF"; }'
                            } >> "$rc"
                            log_info "Added ar-enable/ar-disable to ${rc}"
                        fi
                    done
                    log_success "autoresearch protocol helpers installed"
                else
                    log_info "Skipping autoresearch protocol helpers"
                fi
            fi
        fi
    fi

    return 0
}

################################################################################
# AUTO-UPDATE FUNCTIONS
################################################################################

# Update last check time
update_last_check_time() {
    local timestamp=$(date +%s)
    echo "$timestamp" > "$LAST_UPDATE_CHECK"
    # date -d @<ts> is GNU-only (Linux). BSD date (macOS) uses -r <ts>.
    if [ "$DETECTED_OS" = "macOS" ]; then
        log_debug "Updated last check time: $(date -r "$timestamp" 2>/dev/null || echo "$timestamp")"
    else
        log_debug "Updated last check time: $(date -d "@$timestamp" 2>/dev/null || echo "$timestamp")"
    fi
}

# Check if enough time has passed since last check
should_check_for_updates() {
    if [ ! -f "$LAST_UPDATE_CHECK" ]; then
        log_debug "No last check file found, should check for updates"
        return 0
    fi

    local last_check=$(cat "$LAST_UPDATE_CHECK" 2>/dev/null || echo "0")
    local current_time=$(date +%s)
    local time_diff=$((current_time - last_check))

    # Time intervals in seconds
    local daily=86400        # 24 * 60 * 60
    local weekly=604800      # 7 * 24 * 60 * 60
    local monthly=2592000    # 30 * 24 * 60 * 60

    case "$UPDATE_SCHEDULE" in
        daily)
            return $((time_diff >= daily))
            ;;
        weekly)
            return $((time_diff >= weekly))
            ;;
        monthly)
            return $((time_diff >= monthly))
            ;;
        manual)
            return 0
            ;;
        *)
            # Default to weekly
            return $((time_diff >= weekly))
            ;;
    esac
}

# Create backup before update
create_backup_before_update() {
    log_info "Creating backup before update..."

    local backup_dir="${HOME}/.opencode-update-backup-$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir" 2>/dev/null

    # Backup config
    if [ -f "$CONFIG_FILE" ]; then
        cp "$CONFIG_FILE" "${backup_dir}/opencode.json"
        log_info "Backed up: ${CONFIG_FILE}"
    fi

    # Backup AGENTS.md if it exists
    if [ -f "${CONFIG_DIR}/AGENTS.md" ]; then
        cp "${CONFIG_DIR}/AGENTS.md" "${backup_dir}/AGENTS.md"
        log_info "Backed up: ${CONFIG_DIR}/AGENTS.md"
    fi

    # Backup vibeguard.config.json if it exists (PLAN-GIT-315)
    if [ -f "${CONFIG_DIR}/vibeguard.config.json" ]; then
        cp "${CONFIG_DIR}/vibeguard.config.json" "${backup_dir}/vibeguard.config.json"
        log_info "Backed up: ${CONFIG_DIR}/vibeguard.config.json"
    fi

    # Backup skills directory if it exists
    if [ -d "$SKILLS_DIR" ]; then
        cp -r "$SKILLS_DIR" "${backup_dir}/skills"
        log_info "Backed up: ${SKILLS_DIR}"
    fi

    log_success "Backup created at: ${backup_dir}"
    echo "" >> "$UPDATE_LOG"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Backup created: ${backup_dir}" >> "$UPDATE_LOG"

    cleanup_old_backups
}

# Check for updates only (don't install) — targets the v2 package @opencode/cli (#499)
check_for_updates_only() {
    log_info "Checking for @opencode/cli updates..."

    # Check if enough time has passed
    if ! should_check_for_updates; then
        log_info "Skipping update check (scheduled time not reached)"
        return 0
    fi

    # Get current version (normalized to a bare semver — the binary prints
    # "opencode v2.0.11")
    local current_version
    if ! command_exists opencode; then
        log_warn "@opencode/cli is not installed"
        return 1
    fi
    current_version=$(normalize_version "$(opencode --version 2>/dev/null)")

    # Get latest version
    local latest_version
    latest_version=$(npm view @opencode/cli version 2>/dev/null || echo "unknown")

    if [ "$latest_version" = "unknown" ]; then
        log_error "Could not fetch latest version from npm registry"
        return 1
    fi

    log_info "Current version: v${current_version}"
    log_info "Latest version: v${latest_version}"

    # Compare versions
    if [ "$current_version" = "$latest_version" ]; then
        log_success "@opencode/cli is already up to date!"
    else
        log_info "Update available: v${current_version} → v${latest_version}"
        log_info "Run: ./setup.sh -C to check again, or ./setup.sh --update to install"
    fi

    update_last_check_time
    # Trailing appends must not become the function's return status (#470
    # review): a failed log write would flip the critical check-update step.
    mkdir -p "$(dirname "$UPDATE_LOG")" 2>/dev/null || true
    echo "" >> "$UPDATE_LOG" 2>/dev/null || true
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Update check: v${current_version} (latest: v${latest_version})" >> "$UPDATE_LOG" 2>/dev/null || true
    return 0
}

# Perform auto-update

################################################################################
# SUMMARY AND REPORTING
################################################################################

# Print setup summary
print_summary() {
    local nvm_version
    local opencode_version
    local node_version
    local skill_count

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "                      📊 Setup Summary"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Platform detection status
    echo "Platform Detection:"
    echo "✓ Detected OS: ${DETECTED_OS} ${OS_VERSION:+(${OS_VERSION})}"
    echo "✓ Detected Shell: ${DETECTED_SHELL}"
    echo "✓ Shell Config: ${SHELL_CONFIG_FILE}"
    echo ""

    # Coding-agent detection (#573) — read-only, idempotent; works in every
    # epilogue even when the detect-agents plan step never ran.
    detect_installed_agents
    echo ""

    # nvm status (Unix-like systems only)
    if command_exists nvm; then
        nvm_version=$(nvm --version 2>/dev/null)
        echo "✓ nvm: Installed v${nvm_version}"
    else
        case "$DETECTED_OS" in
            Windows*|Windows-GitBash)
                # On Windows, nvm is not used
                ;;
            *)
                echo "✗ nvm: Not installed"
                ;;
        esac
    fi

    # Package manager status
    if [ "$PACKAGE_MANAGER" != "none" ]; then
        echo "✓ Package Manager: ${PACKAGE_MANAGER}"
        # Show distribution for Linux
        case "$DETECTED_OS" in
            Linux*)
                if [ -n "$DISTRIBUTION_NAME" ] && [ "$DISTRIBUTION_NAME" != "unknown" ]; then
                    echo "  Distribution: ${DISTRIBUTION_NAME}"
                fi
                ;;
        esac
    else
        case "$DETECTED_OS" in
            Windows*|Windows-GitBash)
                echo "○ Package Manager: Not detected (use winget or chocolatey)"
                ;;
            *)
                echo "✗ Package Manager: Not detected"
                ;;
        esac
    fi

    # Node.js status
    if command_exists node; then
        node_version=$(node --version)
        echo "✓ Node.js: ${node_version}"
    else
        echo "✗ Node.js: Not installed"
    fi

    # @opencode/cli status — v1 installs are labeled honestly: a v1 binary
    # silently ignores the deployed config's v2 plugins key (#499)
    if command_exists opencode; then
        opencode_version=$(normalize_version "$(opencode --version 2>/dev/null || echo "unknown")")
        case "$opencode_version" in
            1.*)
                echo "⚠ opencode-ai (v1): Installed v${opencode_version} — v1 ignores the v2 plugins config; run ./deploy/setup.sh to migrate to @opencode/cli"
                ;;
            *)
                echo "✓ @opencode/cli: Installed v${opencode_version}"
                ;;
        esac
    else
        echo "✗ @opencode/cli: Not installed"
    fi

    # opencode.json status
    if [ -f "$CONFIG_FILE" ]; then
        echo "✓ opencode.json: Copied to ${CONFIG_DIR}/"
        primary_model=$(node -pe "JSON.parse(require('fs').readFileSync('${REPO_DIR}/installer/models.default.json','utf8')).primary" 2>/dev/null || echo "zai-coding-plan/glm-5.3")
        echo "    - Model: ${primary_model}"
        echo "    - Default agent: build"
    else
        echo "✗ opencode.json: Not copied"
    fi

    # Agents configured
    if [ -f "$CONFIG_FILE" ]; then
        echo "✓ Configured $(count_agents "${REPO_DIR}/agents") agents:"
        echo "    - build (default) - Full-featured coding agent"
        echo "    - plan - Planning agent (read-only)"
        echo "    - explore - Codebase exploration and analysis"
        echo "    - image-analyzer-subagent - Image/screenshot analysis"
        echo "    - zai-media-subagent - Media production: image/video gen, ASR, OCR (delegated)"
        echo "    - ... and $(($(count_agents "${REPO_DIR}/agents") - 5)) more agents"
    fi

    # MCP servers configured
    if [ -f "$CONFIG_FILE" ]; then
         echo "✓ Configured MCP servers:"
         echo "    - codegraph - Code knowledge graph (auto-start)"
         echo "    - web-reader - Web page reading (auto-start, needs ZAI_API_KEY)"
         echo "    - web-search - Web search with cited results (auto-start, needs ZAI_API_KEY)"
         echo "    - atlassian - JIRA and Confluence (opt-in per-project)"
         echo "    - next-devtools - Next.js DevTools (opt-in)"
         echo "    - markitdown - Document-to-Markdown (upstream markitdown-mcp), opt-in"
         echo "    - docling - Layout-aware document extraction, opt-in (~3-4 GB)"
         echo "    - chrome-devtools - Live Chrome automation, opt-in"
         echo "    - playwright - Logged-in web automation, opt-in"
         echo "    - alpha-vantage - Market/macro data (needs ALPHA_VANTAGE_API_KEY), opt-in"
         echo "    - nanobanana - Nano Banana image generation (needs GEMINI_API_KEY), opt-in"

    # Secret masking
    if [ -f "${CONFIG_DIR}/vibeguard.config.json" ]; then
         echo "✓ Secret masking: active (vibeguard)"
    fi
    fi

    # skills directory status
    if [ -d "$SKILLS_DIR" ] && [ "$(ls -A "${SKILLS_DIR}" 2>/dev/null)" ]; then
        local skill_count=$(count_skills "${SKILLS_DIR}")
        echo "✓ skills: ${skill_count} skills deployed to ${SKILLS_DIR}/"
        echo "✓ skill profile: ${SKILL_PROFILE} (primary-visible skills in skill permissions)"
        print_skill_categories "${SKILLS_DIR}"

    else
        echo "✗ skills: Not deployed"
    fi

    # ZAI_API_KEY status
    if is_windows && command_exists setx; then
        if [ -n "$ZAI_API_KEY" ]; then
            echo "✓ ZAI_API_KEY: Set via setx (system-wide)"
        else
            echo "✗ ZAI_API_KEY: Not configured"
        fi
    elif grep -q "ZAI_API_KEY" "$SHELL_CONFIG_FILE" 2>/dev/null; then
        echo "✓ ZAI_API_KEY: Added to ${SHELL_CONFIG_FILE}"
    elif [ -n "$ZAI_API_KEY" ]; then
        echo "○ ZAI_API_KEY: Set in current session only"
    else
        echo "✗ ZAI_API_KEY: Not configured"
    fi

    # GitHub CLI status
    if command_exists gh; then
        if gh auth status >/dev/null 2>&1; then
            echo "✓ GitHub CLI: Installed and authenticated"
        else
            echo "○ GitHub CLI: Installed but not authenticated (run: gh auth login)"
        fi
    else
        echo "○ GitHub CLI: Not installed (https://cli.github.com/)"
    fi

    echo ""
}

# Print next steps
print_next_steps() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "                        🎉 Setup Complete!"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "📋 Next Steps:"
    echo "  1. Restart terminal or run: source ${SHELL_CONFIG_FILE}"
    if is_windows; then
        echo "     (Environment variables were set via setx - open a NEW terminal to use them)"
    fi
    echo "  2. Verify installation: opencode --version"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "                        🚀 Quick Start"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "🤖 Agents ($(count_agents "${REPO_DIR}/agents")):"
    echo "  - build (default) - Full-featured coding agent"
    echo "  - plan - Planning agent (read-only)"
    echo "  - explore - Fast codebase exploration and analysis"
    echo "  - image-analyzer-subagent - Images/screenshots to code, OCR, error diagnosis"
    echo "  - zai-media-subagent - Media production: image/video gen, ASR, OCR (delegated)"
    echo "  - discovery-specialist-subagent - Customer-facing discovery: Vision docs + wireframes"
    echo "  - ... and $(($(count_agents "${REPO_DIR}/agents") - 6)) more agents"
    echo ""
    echo "  Usage: opencode --agent <name> \"prompt\""
    echo "         opencode \"prompt\" (uses build)"
     echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo "                     📦 $(count_skills "${REPO_DIR}/skills") Skills Available"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
     echo ""
     print_skill_categories "${REPO_DIR}/skills"
     echo ""
    echo "  Run 'opencode --list-skills' for detailed descriptions"
    echo "  Run 'opencode --skill <name> \"prompt\"' to use a skill"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
     echo "                     🔌 MCP Servers (4)"
     echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
     echo ""
     echo "  Auto-start: codegraph, web-reader, web-search"
      echo "  Opt-in per-project: atlassian"
     echo "  Opt-in global packs: next-devtools, markitdown, docling, chrome-devtools, playwright, alpha-vantage, nanobanana"
    echo ""
    echo "  Auth: opencode mcp auth atlassian / opencode mcp auth github"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "                     📚 Documentation"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "  - Update CLI: ./setup.sh --update"
    echo "  - Config file: ${CONFIG_FILE}"
    echo "  - Log file: ${LOG_FILE}"
    echo "  - Backup dir: ${BACKUP_DIR}"
    echo "  - Full docs: https://opencode.ai"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

################################################################################
# MAIN EXECUTION
################################################################################

# Setup the opencode-init symlink (project-scoped selective installer CLI).
# Symlinks <repo>/installer/init.mjs -> ~/.local/bin/opencode-init so the CLI is on
# PATH and invocable from any project (the LLM uses it via the routing rule in
# AGENTS.md). Idempotent: refreshes a stale link, skips a correct one. Additive —
# does not touch any other setup.sh behavior.
setup_opencode_init_symlink() {
    local init_src="${REPO_DIR}/installer/init.mjs"
    if [ ! -f "$init_src" ]; then
        log_warn "opencode-init source not found at ${init_src}; skipping symlink"
        return 0
    fi
    local user_bin="${HOME}/.local/bin"
    # Dry-run safe (#469, same class as #467): bare mkdir/ln here would really
    # create the PATH shim during a preview.
    run_cmd mkdir -p "$user_bin"
    local link="${user_bin}/opencode-init"
    # Refresh if missing or pointing elsewhere; leave alone if already correct.
    if [ -L "$link" ] && [ "$(readlink -f "$link" 2>/dev/null)" = "$(readlink -f "$init_src" 2>/dev/null)" ]; then
        log_info "opencode-init symlink already correct at ${link}"
    else
        run_cmd ln -sf "$init_src" "$link"
        log_success "opencode-init installed to ${link}"
    fi
    # PATH check (mirrors the markitdown pattern ~line 2587)
    case ":${PATH}:" in
        *":${user_bin}:"*) ;;
        *) log_warn "${user_bin} is not on your PATH. Add it to your shell rc to use opencode-init:" \
           && echo "    export PATH=\"${user_bin}:\$PATH\"" >&2 ;;
    esac
    log_info "Tip: individual skills/agents can also be installed via: npx github:darellchua2/civiltekk-opencode-claude-skills add <name>"
}

# Setup the opencode-setup symlink (full-deploy entrypoint shim).
# Symlinks <repo>/deploy/setup.sh -> ~/.local/bin/opencode-setup so the full
# configurator deploy is on PATH and runnable from any directory (safe only
# because the SCRIPT_DIR resolution above follows symlinks). Idempotent:
# refreshes a stale link, skips a correct one. Additive — does not touch any
# other setup.sh behavior.
setup_opencode_setup_symlink() {
    local setup_src="${REPO_DIR}/deploy/setup.sh"
    if [ ! -f "$setup_src" ]; then
        log_warn "setup.sh source not found at ${setup_src}; skipping symlink"
        return 0
    fi
    local user_bin="${HOME}/.local/bin"
    # Dry-run safe (#469, same class as #467): run_cmd only logs in preview.
    run_cmd mkdir -p "$user_bin"
    local link="${user_bin}/opencode-setup"
    # Refresh if missing or pointing elsewhere; leave alone if already correct.
    if [ -L "$link" ] && [ "$(readlink -f "$link" 2>/dev/null)" = "$(readlink -f "$setup_src" 2>/dev/null)" ]; then
        log_info "opencode-setup symlink already correct at ${link}"
    else
        run_cmd ln -sf "$setup_src" "$link"
        log_success "opencode-setup installed to ${link}"
    fi
    # PATH check (mirrors the opencode-init pattern ~line 4788)
    case ":${PATH}:" in
        *":${user_bin}:"*) ;;
        *) log_warn "${user_bin} is not on your PATH. Add it to your shell rc to use opencode-setup:" \
           && echo "    export PATH=\"${user_bin}:\$PATH\"" >&2 ;;
    esac
    log_info "Tip: full redeploys from any directory: opencode-setup"
}

main() {
    parse_arguments "$@"

    # Fail-fast pack validation, then plan validation (#470): mode conflicts
    # die BEFORE the network check / menu render.
    if [ -n "$ENABLE_PACK" ]; then
        validate_enable_pack
    fi
    build_plan   # validation pass — PLAN_MODE computed, conflicts die here

    # Display header, keyed off the plan mode (single-step modes print their
    # own banners inside their steps).
    case "$PLAN_MODE" in
        skills-only)
            echo "=== OpenCode Skills Deployment v${SCRIPT_VERSION} ==="
            echo ""
            ;;
        update)
            echo "=== OpenCode CLI Updater v${SCRIPT_VERSION} ==="
            echo ""
            ;;
        full)
            echo "=== OpenCode Configuration Setup v${SCRIPT_VERSION} ==="
            echo ""
            ;;
    esac

    # Initialize logging
    init_logging

    # Auxiliary gates preserve their historical reachability: network check and
    # auto-update ran only on the full-path branch (single-step modes exited
    # before them). PLAN_MODE=full is exactly that branch under the plan model.
    if [ "$PLAN_MODE" = "full" ] && [ "$QUICK_SETUP" = false ]; then
        if ! check_network; then
            log_warn "Network connectivity issues detected. Some features may not work."
            if ! prompt_yes_no "Continue anyway?" "n"; then
                # Headless fork (#466 review): EOF resolves this prompt to the
                # default "n", so a bare no-TTY run exits 1 here — fail-closed
                # on purpose (don't deploy on known-bad network). Say so.
                [ -t 0 ] || log_warn "No TTY: headless default is abort (exit 1). Re-run with --skills-only for a local-only deploy."
                exit 1
            fi
        fi
    fi

    # Interactive menu — only the full path ever showed it (historically gated
    # on QUICK/SKILLS/AUTO_ACCEPT; single-step modes had exited earlier, which
    # PLAN_MODE=full now encodes). Menu options only SET flags; the plan owns
    # the steps (#470).
    if [ "$PLAN_MODE" = "full" ] && [ "$AUTO_ACCEPT" = false ]; then
        if [ ! -t 0 ]; then
            # TTY gate (#466): headless runs used to fall into the menu and let
            # `read` hit EOF, silently taking the menu default. Now the default
            # is announced and taken deterministically — no prompt is reached.
            # (A FAILING network check still aborts headless runs before this
            # point — fail-closed on purpose: don't deploy on known-bad network.)
            log_warn "No TTY detected - non-interactive run: defaulting to skills-only setup (the menu default). Use explicit flags (--quick, --skills-only, --update, --models-only, --migrate, --peonping) - see --help."
            SKILLS_ONLY=true
        else
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "                      Setup Mode Selection"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo ""
            echo "  1) Quick setup (config + skills only)"
            echo "  2) Skills-only setup"
            echo "  3) Full setup (API keys, Node.js, OpenCode)"
            echo "  4) Update OpenCode CLI only"
            echo "  5) Install PeonPing (sound notifications)"
            echo "  6) Select items to deploy (skills / agents / packs / plugins)"
            echo ""

            local setup_option
            setup_option=$(prompt_user "Select option [default: 2]" "2")

            case "$setup_option" in
                1)
                    echo ""
                    log_info "Quick Setup: Copy opencode.json and skills only"
                    QUICK_SETUP=true
                    ;;
                2)
                    echo ""
                    log_info "Skills-Only Setup: Copy skills folder only"
                    SKILLS_ONLY=true
                    ;;
                3)
                    log_info "Running full setup..."
                    ;;
                4)
                    echo ""
                    log_info "Update OpenCode CLI only"
                    UPDATE_ONLY=true
                    ;;
                5)
                    echo ""
                    log_info "PeonPing Sound Notifications"
                    PEONPING_ONLY=true
                    ;;
                6)
                    echo ""
                    log_info "Select items to deploy (skills / agents / packs / plugins)"
                    SELECT_ITEMS=true
                    ;;
                *)
                    log_warn "Invalid option. Running full setup..."
                    ;;
            esac
            echo ""
        fi
        build_plan   # rebuild: the menu may have changed the mode (#470)
    fi

    # ── Execute the plan (#470) — failure state lands in PLAN_FAILED_CRITICAL ──
    run_plan || true
    # Mode completion lines (truthful: only when no critical step failed)
    if [ -z "$PLAN_FAILED_CRITICAL" ]; then
        case "$PLAN_MODE" in
            skills-only)  echo ""; echo "Skills deployment complete!";;
            models-only)  echo ""; echo "Model resolution complete!";;
            migrate-only) echo ""; echo "Migration + model resolution complete!";;
            update)       echo ""; echo "Update complete!";;
            check-catalog) echo ""; echo "Catalog check complete!";;
            list-items) echo ""; echo "Catalog dump complete!";;
            save-preset) echo ""; echo "Preset saved!";;
            peonping)     echo ""; echo "PeonPing setup complete!";;
        esac
    fi

    # ── Uniform epilogue (#470): content modes get backup + cleanup + summary
    # on EVERY path — success or failure. Single-step modes complete above.
    case "$PLAN_MODE" in
        full|quick|skills-only)
            create_zip_backup || true
            cleanup_old_backups
            print_summary
            print_next_steps
            ;;
    esac

    log "INFO" "=== OpenCode Setup Completed at $(date) ==="

    # Truthful exit (#470): non-zero iff a critical step failed.
    if [ -n "$PLAN_FAILED_CRITICAL" ]; then
        log_error "Setup finished WITH FAILURES (critical step: ${PLAN_FAILED_CRITICAL}). Log: ${LOG_FILE:-unknown}"
        if [ "$AUTO_ACCEPT" = false ] && [ -t 0 ]; then
            read -p "Press Enter to exit..."
        fi
        exit 1
    fi

    if [ "$AUTO_ACCEPT" = false ]; then
        read -p "Press Enter to exit..."
    fi
    exit 0
}
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

