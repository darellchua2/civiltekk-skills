#!/usr/bin/env bats

# Built-in browser plugin pin (issue #705). deploy/opencode.json names
# opencode.browser in its plugins array so the browser stays on if a later
# OpenCode release makes the built-in opt-in (it is on by default today). The
# pin is plain data that the deploy-time config writers pass through, so
# nothing else fails if a rewrite drops it or an edit reverts it. Offline by
# design: every writer runs against a mktemp copy; nothing here reads or
# writes the real $HOME.

CONFIG="deploy/opencode.json"
RESOLVER="installer/resolve-models.mjs"
TIERS="installer/agent-tiers.json"
DEFAULT_MAP="installer/models.default.json"

# Shared checker: exits non-zero naming every violated point.
# argv: <opencode.json>
# Strict JSON.parse on purpose: CI parses this file with jq and Python's
# json.load, so a comment that slips in must fail here too.
PIN_CHECK='
const fs = require("fs");
// node -e has NO script-name argv slot: argv = [execPath, ...args] => slice(1).
const cfg = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const bad = [];
const plugins = Array.isArray(cfg.plugins) ? cfg.plugins : [];
if (!plugins.some((entry) => entry === "opencode.browser")) bad.push("plugins does not contain \"opencode.browser\"");
if (plugins.some((entry) => typeof entry === "string" && entry.trim() === "-opencode.browser")) bad.push("plugins disables opencode.browser");
if (bad.length) throw new Error("browser plugin pin check failed:\n  " + bad.join("\n  "));
'

setup() {
    SCRATCH="$(mktemp -d)"
}

teardown() {
    rm -rf "$SCRATCH"
}

# The config as setup's copy step leaves it: the shipped file, in the scratch dir.
stage_config() {
    cp "$CONFIG" "$SCRATCH/opencode.json"
}

# The model resolver as setup runs it for the deployed config, with no agent
# files. Extra arguments are passed through.
resolve_deployed_config() {
    node "$RESOLVER" \
        --tiers "$TIERS" \
        --default-map "$DEFAULT_MAP" \
        --config-dest "$SCRATCH/opencode.json" \
        "$@"
}

# Run one deploy-time config writer against the scratch config, then check the
# pin is still intact. Called bare (not through `run`) so a failure fails the
# test; every check returns non-zero explicitly, because a helper reports only
# its last command status.
survives() {
    local label="$1"
    shift
    run "$@"
    if [ "$status" -ne 0 ]; then
        echo "$label: writer exited $status" >&2
        echo "$output" >&2
        return 1
    fi
    run node -e "$PIN_CHECK" "$SCRATCH/opencode.json"
    if [ "$status" -ne 0 ]; then
        echo "$label: pin not intact after the writer ran" >&2
        echo "$output" >&2
        return 1
    fi
}

@test "shipped_config_pins_the_builtin_browser_plugin" {
    run node -e "$PIN_CHECK" "$CONFIG"
    [ "$status" -eq 0 ]
}

@test "pin_survives_every_deploy_time_writer" {
    # The normal setup path, in order: the resolver writes the deployed file
    # from the shipped source, then the lean skill profile and a pack merge
    # edit that same file. The scratch dir starts empty, so a missing output
    # fails the checker instead of passing on a pre-existing copy.
    survives "resolver (fresh copy)" resolve_deployed_config --config-src "$CONFIG"
    survives "apply-skill-profile (lean)" \
        node deploy/apply-skill-profile.mjs \
        --config "$SCRATCH/opencode.json" \
        --profiles deploy/skill-profiles.json
    survives "merge-packs (markitdown)" \
        node deploy/merge-packs.mjs \
        --config "$SCRATCH/opencode.json" \
        --packs-dir deploy/packs \
        --packs markitdown
}

@test "survives_helper_fails_on_a_failing_writer_or_a_dropped_pin" {
    # Negative fixture for the helper itself: a failing writer, and a passing
    # writer over a config that lost the pin, must both fail the test, or the
    # survival test above could pass on a no-op.
    stage_config
    if survives "failing writer" false; then
        echo "survives() accepted a failing writer" >&2
        return 1
    fi
    node -e '
      const fs = require("fs");
      const cfg = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
      cfg.plugins = cfg.plugins.filter((entry) => entry !== "opencode.browser");
      fs.writeFileSync(process.argv[1], JSON.stringify(cfg, null, 2) + "\n");
    ' "$SCRATCH/opencode.json"
    if survives "dropped pin" true; then
        echo "survives() accepted a config without the pin" >&2
        return 1
    fi
}
