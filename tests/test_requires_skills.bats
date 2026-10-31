#!/usr/bin/env bats

# Tests for the requiresSkills installer edge (#439, PLANS/PLAN-439.md).
# dependency-map.json skill->skill auto-install: `add <skill>` installs the
# declared prerequisite with a visible notice; --no-deps opts out; dry-run and
# the user-scope manifest list the auto-added skill; the map entries are pinned
# to tests/test_skill_isolation.bats HANDOFF{1,2}_OWNER/HANDOFF{1,2}_TARGETS
# plus the #602 HANDOFF3 multi-owner pair (source of truth per AGENTS.md
# §Skill Isolation Contract).

REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
INIT="node ${REPO}/installer/init.mjs"
DEPMAP="${REPO}/installer/dependency-map.json"
GUARD="${REPO}/tests/test_skill_isolation.bats"

MODIFIER="plan-execution-inline-skill"
SLIDE="testing-inline-skill"

setup() {
  export TMP_HOME="$(mktemp -d)"
  export HOME="$TMP_HOME"
}
teardown() { rm -rf "$TMP_HOME"; }

@test "requires_skills_add_auto_installs_prerequisite_with_notice" {
  run bash -c "$INIT add $MODIFIER --yes 2>&1"
  [ "$status" -eq 0 ]
  # Notice pinned to the emitted prefix (init.mjs console.error) — exact
  # enough to catch silent auto-install, loose enough not to pin prose.
  echo "$output" | grep -q "also installing required skill: $SLIDE"
  [ -d "$HOME/.config/opencode/skills/$MODIFIER" ]
  [ -d "$HOME/.config/opencode/skills/$SLIDE" ]
}

@test "requires_skills_manifest_tracks_auto_added_skill" {
  $INIT add "$MODIFIER" --yes >/dev/null 2>&1
  python3 - "$HOME/.config/opencode/.skill-manifest.json" "$MODIFIER" "$SLIDE" <<'PYEOF'
import json, sys
m = json.load(open(sys.argv[1]))
for name in sys.argv[2:4]:
    assert name in m["skills"], f"{name} missing from manifest skills"
    assert m["entries"][name]["type"] == "skill", f"{name} entry type wrong"
print("ok")
PYEOF
}

@test "requires_skills_no_deps_installs_only_named_skill" {
  run bash -c "$INIT add $MODIFIER --no-deps --yes 2>&1"
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q "also installing"
  [ -d "$HOME/.config/opencode/skills/$MODIFIER" ]
  [ ! -d "$HOME/.config/opencode/skills/$SLIDE" ]
}

@test "requires_skills_dry_run_lists_auto_added_skill" {
  run bash -c "$INIT add $MODIFIER --dry-run 2>/dev/null"
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import sys, json
d = json.load(sys.stdin)
for name in sys.argv[1:3]:
    assert name in d['skills'], f'{name} missing from dry-run skills'
" "$MODIFIER" "$SLIDE"
}

@test "requires_skills_map_entry_matches_isolation_guard_handoff_pair" {
  # AGENTS.md: the HANDOFF1..HANDOFF4 uniform owner->targets pairs in the guard are the
  # source of truth — the installer edges must be exactly those handoffs
  # (owner -> multi-target), never drift.
  HANDOFF1_OWNER="$(grep -oE '^HANDOFF1_OWNER="[^"]+"' "$GUARD" | cut -d'"' -f2)"
  HANDOFF1_TARGETS="$(grep -oE '^HANDOFF1_TARGETS="[^"]+"' "$GUARD" | cut -d'"' -f2)"
  HANDOFF2_OWNER="$(grep -oE '^HANDOFF2_OWNER="[^"]+"' "$GUARD" | cut -d'"' -f2)"
  HANDOFF2_TARGETS="$(grep -oE '^HANDOFF2_TARGETS="[^"]+"' "$GUARD" | cut -d'"' -f2)"
  HANDOFF3_OWNER="$(grep -oE '^HANDOFF3_OWNER="[^"]+"' "$GUARD" | cut -d'"' -f2)"
  HANDOFF3_TARGETS="$(grep -oE '^HANDOFF3_TARGETS="[^"]+"' "$GUARD" | cut -d'"' -f2)"
  HANDOFF4_OWNER="$(grep -oE '^HANDOFF4_OWNER="[^"]+"' "$GUARD" | cut -d'"' -f2)"
  HANDOFF4_TARGETS="$(grep -oE '^HANDOFF4_TARGETS="[^"]+"' "$GUARD" | cut -d'"' -f2)"
  [ -n "$HANDOFF1_OWNER" ] && [ -n "$HANDOFF1_TARGETS" ]
  [ -n "$HANDOFF2_OWNER" ] && [ -n "$HANDOFF2_TARGETS" ]
  [ -n "$HANDOFF3_OWNER" ] && [ -n "$HANDOFF3_TARGETS" ]
  [ -n "$HANDOFF4_OWNER" ] && [ -n "$HANDOFF4_TARGETS" ]
  python3 - "$DEPMAP" "$HANDOFF1_OWNER" "$HANDOFF1_TARGETS" "$HANDOFF2_OWNER" "$HANDOFF2_TARGETS" "$HANDOFF3_OWNER" "$HANDOFF3_TARGETS" "$HANDOFF4_OWNER" "$HANDOFF4_TARGETS" "${REPO}/deploy/opencode.json" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1]))
owner1, targets1, owner2, targets2, owner3, targets3, owner4, targets4 = sys.argv[2:10]
expected = {
    owner1: targets1.split(),
    owner2: targets2.split(),
    owner3: targets3.split(),
    owner4: targets4.split(),
}
got = d.get("requiresSkills", {})
assert got == expected, "requiresSkills %s != guard handoffs %s" % (got, expected)
# impliesMcp values must be real MCP server keys (dependency-map $comment claim)
oc = json.load(open(sys.argv[10]))
servers = set((oc.get("mcp") or {}).get("servers") or {})
for skill, mcps in d.get("impliesMcp", {}).items():
    for m in mcps:
        assert m in servers, "%s implies unknown MCP server %s" % (skill, m)
print("ok")
PYEOF
}
