#!/usr/bin/env bash
# laya-guard sidecar provisioning (#671, moved from deploy/setup.sh in #677).
#
# Invoked by setup.sh's deploy_plugins hook (any plugin dir may ship a
# provision.sh — this is the convention's first consumer). Also runnable
# standalone: bash plugins/laya-guard/provision.sh
#
# Copies the sidecar scripts + pinned package.json into ~/.cache/laya-guard
# and npm-installs there, so the opencode plugin file itself stays
# dependency-free. The ~1.7 GB model pre-pull is opt-in (interactive prompt,
# or LAYA_GUARD_WARM=1 headless); without it the model downloads lazily on
# the first classify. Idempotent: the marker records the provisioned
# package.json hash. Linux-only (Ubuntu target — non-Linux gets a skip
# notice, which is also what Windows reaches through the setup.ps1 thin
# launcher, #474). LAYA_GUARD_SKIP=1 escapes entirely.
#
# Environment (all optional): DRY_RUN, AUTO_ACCEPT, REPO_DIR, LAYA_GUARD_DIR,
# LAYA_GUARD_SKIP, LAYA_GUARD_WARM.
set -o pipefail
set -o nounset

# Resolve repo root (script lives at <repo>/plugins/laya-guard/).
PROVISION_SELF="${BASH_SOURCE[0]}"
REPO_DIR="${REPO_DIR:-$(cd "$(dirname "$PROVISION_SELF")/../.." && pwd)}"

# Dry-run contract (#467): explicit comparison — never ${DRY_RUN:+word}
# (expands on the string "false"; test_dry_run_leaks pins this class).
DRY_RUN="${DRY_RUN:-false}"
AUTO_ACCEPT="${AUTO_ACCEPT:-false}"

command_exists() { command -v "$1" >/dev/null 2>&1; }
# Dry-run-aware exec (mirrors setup.sh's run_cmd multi-arg contract).
run_cmd() {
    if [ "$DRY_RUN" = true ]; then
        echo "[DRY-RUN] Would execute: $*"
        return 0
    fi
    "$@"
}
log_info()    { echo "[INFO] $*"; }
log_warn()    { echo "[WARNING] $*" >&2; }
log_success() { echo "[SUCCESS] $*"; }

prompt_yes_no() {
    local msg="$1" def="${2:-n}" reply
    if [ "$AUTO_ACCEPT" = true ]; then
        [ "$def" = "y" ]
        return
    fi
    read -r -p "${msg} [${def}]: " reply || { [ "$def" = "y" ]; return; }
    reply="${reply:-$def}"
    [[ "$reply" =~ ^[Yy]$ ]]
}

provision_main() {
if [ "${LAYA_GUARD_SKIP:-0}" = "1" ]; then
    log_info "LAYA_GUARD_SKIP=1 — skipping laya-guard provisioning"
    return 0
fi
if [ "$(uname -s)" != "Linux" ]; then
    log_info "laya-guard provisioning is Linux-only (Ubuntu target) — skipped on $(uname -s); the plugin deploys but stays inert"
    return 0
fi
if ! command_exists node; then
    log_warn "node not found — cannot provision the laya-guard sidecar. Install Node >= 24 and re-run."
    return 0
fi
local node_major
node_major="$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)"
if [ "${node_major:-0}" -lt 24 ]; then
    log_warn "Node >= 24 required for the laya-guard sidecar (found $(node --version 2>/dev/null || echo none)) — skipping; the plugin stays inert."
    return 0
fi
if ! command_exists npm; then
    log_warn "npm not found — cannot provision the laya-guard sidecar. Install npm and re-run."
    return 0
fi

local src_dir="${REPO_DIR}/plugins/laya-guard"
local dest_dir="${LAYA_GUARD_DIR:-$HOME/.cache/laya-guard}"
local pkg_hash marker
pkg_hash="$(sha256sum "$src_dir/package.json" | cut -d' ' -f1)"
marker="$dest_dir/.provisioned"

if [ -f "$marker" ] && [ -f "$dest_dir/sidecar.mjs" ] && [ "$(cat "$marker" 2>/dev/null)" = "$pkg_hash" ]; then
    log_info "laya-guard sidecar already provisioned ($dest_dir)"
else
    echo ""
    log_info "Provisioning the laya-guard sidecar (local decision-model runtime)..."
    run_cmd mkdir -p "$dest_dir"
    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY-RUN] Would copy sidecar + warm + package.json to $dest_dir and npm install there"
    else
        if cp "$src_dir/sidecar.mjs" "$dest_dir/sidecar.mjs" \
            && cp "$src_dir/warm.mjs" "$dest_dir/warm.mjs" \
            && cp "$src_dir/package.json" "$dest_dir/package.json"; then
            if (cd "$dest_dir" && npm install --omit=dev --no-audit --no-fund >/dev/null 2>&1); then
                printf '%s
' "$pkg_hash" > "$marker"
                log_success "laya-guard sidecar provisioned ($dest_dir)"
            else
                log_warn "npm install failed for the laya-guard sidecar (offline?). OpenCode works without it; re-run setup when online."
                return 0
            fi
        else
            log_warn "laya-guard sidecar copy failed — the plugin stays inert"
            return 0
        fi
    fi
fi

# Model pre-pull: interactive prompt, or LAYA_GUARD_WARM=1 headless.
# Deliberately NOT --enable-pack: validate_enable_pack fail-fasts on
# non-MCP pack names, and run_pack_merger would choke on the missing
# pack partial — laya toggles no MCP servers (#672 post-merge fix).
local warm_model=false
if [ "${LAYA_GUARD_WARM:-0}" = "1" ]; then
    warm_model=true
elif [ -t 0 ] && [ "$AUTO_ACCEPT" = false ]; then
    if prompt_yes_no "Pre-pull the ~1.7 GB Laya model bundle now? (skip is fine — the first classify downloads it)" "n"; then
        warm_model=true
    fi
fi
if [ "$warm_model" = true ]; then
    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY-RUN] Would pre-pull the ~1.7 GB Laya model bundle (node warm.mjs)"
    elif [ -f "$dest_dir/node_modules/@receptron/laya/package.json" ]; then
        log_info "Pre-pulling the ~1.7 GB Laya model bundle (one-time; laya-managed cache)..."
        if (cd "$dest_dir" && node warm.mjs >/dev/null 2>&1); then
            log_success "Laya model bundle ready — classification is fully offline from here"
        else
            log_warn "Model pre-pull failed (network?). The first classify downloads it instead."
        fi
    else
        log_warn "Model pre-pull skipped — sidecar deps are missing (npm install failed earlier?)"
    fi
fi
}

provision_main
