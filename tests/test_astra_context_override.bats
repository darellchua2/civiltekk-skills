#!/usr/bin/env bats

# GPT-6.2 Astra context override (issue #703). deploy/opencode.json seeds a
# per-model limit for openai/gpt-6.2-astra so ChatGPT sign-ins stop being
# capped at 272k input for that model. The block is plain data that the
# deploy-time config writers pass through, so nothing else fails if a
# rewrite drops it or an edit removes `input` (the cap plugin writes
# `input`, and OpenCode merges a model limit per key). Offline by design:
# every writer runs against a mktemp copy; nothing here reads or writes the
# real $HOME.

CONFIG="deploy/opencode.json"
RESOLVER="installer/resolve-models.mjs"
TIERS="installer/agent-tiers.json"
DEFAULT_MAP="installer/models.default.json"

# Shared checker: exits non-zero naming every violated point.
# argv: <opencode.json>
# Strict JSON.parse on purpose: CI parses this file with jq and Python's
# json.load, so a comment that slips in must fail here too.
ASTRA_CHECK='
const fs = require("fs");
// node -e has NO script-name argv slot: argv = [execPath, ...args] => slice(1).
const file = process.argv[1];
const cfg = JSON.parse(fs.readFileSync(file, "utf8"));
const want = { context: 1050000, input: 922000, output: 128000 };
const bad = [];
const openai = cfg.providers && cfg.providers.openai;
const model = openai && openai.models && openai.models["gpt-6.2-astra"];
const limit = model && model.limit;
for (const key of Object.keys(want)) {
  if (!limit || limit[key] === undefined) bad.push(`limit.${key} is missing, expected ${want[key]}`);
  else if (limit[key] !== want[key]) bad.push(`limit.${key} is ${limit[key]}, expected ${want[key]}`);
}
if (limit) {
  for (const key of Object.keys(limit)) if (!(key in want)) bad.push(`unexpected limit key "${key}"`);
}
const others = Object.keys((openai && openai.models) || {}).filter((id) => id !== "gpt-6.2-astra");
if (others.length) bad.push(`providers.openai.models also defines ${others.join(", ")}`);
const plugins = Array.isArray(cfg.plugins) ? cfg.plugins : [];
if (plugins.some((entry) => typeof entry === "string" && entry.trim() === "-opencode.provider.openai-context-caps")) {
  bad.push("plugins disable opencode.provider.openai-context-caps");
}
if (bad.length) throw new Error("Astra override check failed:\n  " + bad.join("\n  "));
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

# Run one deploy-time config writer against the scratch config, then check
# the override is still intact. Called bare (not through `run`) so a failure
# fails the test; every check returns non-zero explicitly, because a helper
# reports only its last command status.
survives() {
    local label="$1"
    shift
    run "$@"
    if [ "$status" -ne 0 ]; then
        echo "$label: writer exited $status" >&2
        echo "$output" >&2
        return 1
    fi
    run node -e "$ASTRA_CHECK" "$SCRATCH/opencode.json"
    if [ "$status" -ne 0 ]; then
        echo "$label: override not intact after the writer ran" >&2
        echo "$output" >&2
        return 1
    fi
}

@test "shipped_config_carries_the_exact_astra_limit" {
    run node -e "$ASTRA_CHECK" "$CONFIG"
    [ "$status" -eq 0 ]
}

@test "override_survives_the_resolver_fresh_copy_path" {
    # The normal setup path: the resolver writes the deployed file from the
    # shipped source. The scratch dir starts empty, so a missing output
    # fails the checker instead of passing on a pre-existing copy.
    survives "resolver (fresh copy)" resolve_deployed_config --config-src "$CONFIG"
}

@test "override_survives_the_resolver_declined_copy_path" {
    # The user keeps an existing config: no --config-src, the resolver
    # patches the deployed file in place.
    stage_config
    survives "resolver (declined copy)" resolve_deployed_config
}

@test "resolver_never_adds_the_override_to_a_kept_config" {
    # Decline contract (#470): a config the user chose to keep only gets its
    # model pins patched. One that predates the override stays free of it.
    # Drop a pin as well, so the pin coming back proves the resolver did
    # process this file.
    node -e '
      const fs = require("fs");
      const [from, to] = process.argv.slice(1);
      const cfg = JSON.parse(fs.readFileSync(from, "utf8"));
      delete cfg.providers.openai;
      delete cfg.agents.general;
      fs.writeFileSync(to, JSON.stringify(cfg, null, 2) + "\n");
    ' "$CONFIG" "$SCRATCH/opencode.json"
    run resolve_deployed_config
    [ "$status" -eq 0 ]
    run node -e '
      const fs = require("fs");
      const cfg = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
      const expected = JSON.parse(fs.readFileSync(process.argv[2], "utf8")).tiers.reasoning;
      const patched = cfg.agents && cfg.agents.general && cfg.agents.general.model;
      if (patched !== expected) throw new Error(`resolver did not patch the kept config (general.model is ${patched}); this test proves nothing`);
      const added = Object.keys(cfg.providers || {}).filter((id) => cfg.providers[id].models && cfg.providers[id].models["gpt-6.2-astra"]);
      if (Object.prototype.hasOwnProperty.call(cfg.providers || {}, "openai")) added.push("providers.openai");
      if (added.length) throw new Error("resolver added the Astra override to a kept config: " + added.join(", "));
    ' "$SCRATCH/opencode.json" "$DEFAULT_MAP"
    [ "$status" -eq 0 ]
}

@test "override_survives_the_lean_skill_profile" {
    stage_config
    survives "apply-skill-profile (lean)" \
        node deploy/apply-skill-profile.mjs \
        --config "$SCRATCH/opencode.json" \
        --profiles deploy/skill-profiles.json
}

@test "override_survives_a_pack_merge" {
    stage_config
    survives "merge-packs (markitdown)" \
        node deploy/merge-packs.mjs \
        --config "$SCRATCH/opencode.json" \
        --packs-dir deploy/packs \
        --packs markitdown
}

@test "survives_helper_fails_on_a_failing_writer_or_a_dropped_override" {
    # Negative fixture for the helper itself: a failing writer, and a passing
    # writer over a config that lost the override, must both fail the test,
    # or every override_survives_* test above could pass on a no-op.
    stage_config
    if survives "failing writer" false; then
        echo "survives() accepted a failing writer" >&2
        return 1
    fi
    node -e '
      const fs = require("fs");
      const cfg = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
      delete cfg.providers.openai;
      fs.writeFileSync(process.argv[1], JSON.stringify(cfg, null, 2) + "\n");
    ' "$SCRATCH/opencode.json"
    if survives "dropped override" true; then
        echo "survives() accepted a config without the override" >&2
        return 1
    fi
}

@test "induced_corruption_is_reported_by_name" {
    # Negative fixture for the checker, one corruption per branch: delete
    # `input` (the key the cap plugin writes), add a second OpenAI model,
    # and disable the cap plugin. The checker must fail and name all three.
    node -e '
      const fs = require("fs");
      const cfg = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
      delete cfg.providers.openai.models["gpt-6.2-astra"].limit.input;
      cfg.providers.openai.models["gpt-5.5"] = {};
      cfg.plugins.push("-opencode.provider.openai-context-caps");
      fs.writeFileSync(process.argv[2], JSON.stringify(cfg, null, 2) + "\n");
    ' "$CONFIG" "$SCRATCH/corrupt.json"
    run node -e "$ASTRA_CHECK" "$SCRATCH/corrupt.json"
    [ "$status" -ne 0 ]
    [[ "$output" == *"limit.input is missing, expected 922000"* ]]
    [[ "$output" == *"providers.openai.models also defines gpt-5.5"* ]]
    [[ "$output" == *"plugins disable opencode.provider.openai-context-caps"* ]]
}
