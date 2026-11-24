#!/usr/bin/env bats

# Preset pin resolution guard (issue #468). Every remote preset pin must
# resolve against installer/provider-models.json — the same data the #281
# deploy-time guard consumes via --provider-models. Offline by design:
# drift FROM the live models.dev catalog is #472's --check-catalog; this
# pins internal consistency of the shipped data files.
# Regression: anthropic's fast/docs pins referenced claude-haiku-4-6, which
# does not exist in the catalog — invisible because provider-models.json
# covered zai* prefixes only.

PRESETS="installer/provider-presets.json"
MODELS="installer/provider-models.json"
DEFAULTS="installer/models.default.json"

# Presets with no catalog-backed provider (template pin or local runtime).
# A NEW remote preset missing from provider-models.json FAILS the coverage
# test below instead of silently escaping.
LOCAL_PRESETS="openrouter vllm ollama"

# Shared checker: exits non-zero listing every unresolvable pin.
# argv: <provider-models.json> <presets.json> [tier-map.json]
PIN_CHECK='
const fs = require("fs");
// node -e has NO script-name argv slot: argv = [execPath, ...args] => slice(1).
const [modelsFile, presetsFile, tierMapFile] = process.argv.slice(1);
const m = JSON.parse(fs.readFileSync(modelsFile, "utf8"));
const pp = JSON.parse(fs.readFileSync(presetsFile, "utf8"));
const presets = pp.presets || pp;
const LOCAL = new Set((process.env.LOCAL_PRESETS || "").split(/\s+/).filter(Boolean));
const broken = [], uncovered = [];
for (const [name, p] of Object.entries(presets)) {
  if (name.startsWith("$")) continue;
  if (!p || typeof p !== "object" || Array.isArray(p)) {
    broken.push(`${name}: preset entry is not an object — cannot check pins`);
    continue;
  }
  if (!p.primary) {
    // A preset object without .primary escapes every check below — fail loudly
    // instead (the claude-haiku-4-6 class of silent green).
    broken.push(`${name}: preset object has no "primary" pin`);
    continue;
  }
  const pins = [p.primary, ...Object.values(p.tiers || {})];
  const prefixes = new Set(pins.map(pin => pin.slice(0, pin.indexOf("/"))));
  const covered = [...prefixes].every(pfx => Array.isArray(m[pfx]));
  if (!covered && !LOCAL.has(name)) {
    uncovered.push(`${name}: prefixes [${[...prefixes]}] absent from provider-models.json — add its array or extend LOCAL_PRESETS deliberately`);
    continue;
  }
  for (const pin of pins) {
    const slash = pin.indexOf("/");
    if (slash < 1) { broken.push(`${name}: not provider/model form: ${pin}`); continue; }
    const prov = pin.slice(0, slash), model = pin.slice(slash + 1);
    if (Array.isArray(m[prov]) && !m[prov].includes(model)) {
      broken.push(`${name}: ${pin} — ${prov} does not serve this model`);
    }
  }
}
if (tierMapFile) {
  const tm = JSON.parse(fs.readFileSync(tierMapFile, "utf8"));
  const pins = [tm.primary, ...Object.values(tm.tiers || {})];
  for (const pin of pins) {
    const prov = pin.slice(0, pin.indexOf("/")), model = pin.slice(pin.indexOf("/") + 1);
    if (!(Array.isArray(m[prov]) && m[prov].includes(model))) {
      broken.push(`models.default.json: ${pin} — unresolvable`);
    }
  }
}
const all = [...uncovered, ...broken];
if (all.length) throw new Error("unresolvable pins:\n  " + all.join("\n  "));
'

@test "provider_models_covers_all_remote_presets_with_nonempty_arrays" {
  # Derived, not enumerated (derived-consistency-pins): every real provider
  # key in provider-models.json must be a non-empty array — a future provider
  # added to the data file is covered automatically.
  node -e '
    const m = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    const bad = Object.keys(m).filter(k => !k.startsWith("$") && !(Array.isArray(m[k]) && m[k].length > 0));
    if (bad.length) throw new Error("missing/empty provider arrays: " + bad.join(", "));
  ' "$MODELS"
}

@test "every_preset_pin_resolves_against_provider_models" {
  LOCAL_PRESETS="$LOCAL_PRESETS" node -e "$PIN_CHECK" "$MODELS" "$PRESETS"
}

@test "models_default_json_pins_resolve" {
  LOCAL_PRESETS="$LOCAL_PRESETS" node -e "$PIN_CHECK" "$MODELS" "$PRESETS" "$DEFAULTS"
}

@test "induced_broken_pin_fails_the_check" {
  # Negative fixture: reintroduce the historical #468 breakage on a copy —
  # the checker must catch it (claude-haiku-4-6 is not in the catalog).
  local dir
  dir="$(mktemp -d)"
  trap 'rm -rf "$dir"' EXIT
  cp "$MODELS" "$dir/models.json"
  sed 's/claude-haiku-4-5/claude-haiku-4-6/g' "$PRESETS" > "$dir/presets.json"
  run env LOCAL_PRESETS="$LOCAL_PRESETS" node -e "$PIN_CHECK" "$dir/models.json" "$dir/presets.json"
  [ "$status" -ne 0 ]
  [[ "$output" == *"claude-haiku-4-6"* ]]
}

@test "malformed_preset_shapes_fail_the_check" {
  # Committed fixture for the fail-loudly branches (round-2 review): a
  # primary-less preset object must be reported, never silently skipped —
  # that silent-skip is exactly what let the historical breakage through.
  local dir
  dir="$(mktemp -d)"
  trap 'rm -rf "$dir"' EXIT
  cp "$MODELS" "$dir/models.json"
  cat > "$dir/presets.json" <<'JSON'
{
  "zai": { "primary": "zai-coding-plan/glm-5.3", "tiers": {} },
  "broken-shape": { "label": "no primary key here" },
  "not-an-object": "whoops"
}
JSON
  run env LOCAL_PRESETS="$LOCAL_PRESETS" node -e "$PIN_CHECK" "$dir/models.json" "$dir/presets.json"
  [ "$status" -ne 0 ]
  [[ "$output" == *'broken-shape: preset object has no "primary" pin'* ]]
  [[ "$output" == *"not-an-object: preset entry is not an object"* ]]
}
