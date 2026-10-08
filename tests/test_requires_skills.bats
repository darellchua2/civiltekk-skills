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

MODIFIER="pptx-template-modifier-skill"
SLIDE="pptx-generate-slide-skill"

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

@test "requires_skills_autoresearch_loop_pulls_core" {
  # #602: the three loop skills declare the core protocol host — one
  # representative edge proves the wiring end-to-end (the map pin above
  # covers all three entries).
  LOOP="autoresearch-ml-skill"
  CORE="autoresearch-core-skill"
  run bash -c "$INIT add $LOOP --yes 2>&1"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "also installing required skill: $CORE"
  [ -d "$HOME/.config/opencode/skills/$LOOP" ]
  [ -d "$HOME/.config/opencode/skills/$CORE" ]
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
  # AGENTS.md: HANDOFF{1,2}_OWNER/HANDOFF{1,2}_TARGETS plus the HANDOFF3
  # multi-owner pair and the HANDOFF4/HANDOFF5/HANDOFF6 pairs in the guard are the
  # source of truth — the installer edges must be exactly those handoffs
  # (owner -> multi-target), never drift.
  HANDOFF1_OWNER="$(grep -oE '^HANDOFF1_OWNER="[^"]+"' "$GUARD" | cut -d'"' -f2)"
  HANDOFF1_TARGETS="$(grep -oE '^HANDOFF1_TARGETS="[^"]+"' "$GUARD" | cut -d'"' -f2)"
  HANDOFF2_OWNER="$(grep -oE '^HANDOFF2_OWNER="[^"]+"' "$GUARD" | cut -d'"' -f2)"
  HANDOFF2_TARGETS="$(grep -oE '^HANDOFF2_TARGETS="[^"]+"' "$GUARD" | cut -d'"' -f2)"
  HANDOFF3_OWNERS="$(grep -oE '^HANDOFF3_OWNERS="[^"]+"' "$GUARD" | cut -d'"' -f2)"
  HANDOFF3_TARGETS="$(grep -oE '^HANDOFF3_TARGETS="[^"]+"' "$GUARD" | cut -d'"' -f2)"
  HANDOFF4_OWNER="$(grep -oE '^HANDOFF4_OWNER="[^"]+"' "$GUARD" | cut -d'"' -f2)"
  HANDOFF4_TARGETS="$(grep -oE '^HANDOFF4_TARGETS="[^"]+"' "$GUARD" | cut -d'"' -f2)"
  HANDOFF5_OWNER="$(grep -oE '^HANDOFF5_OWNER="[^"]+"' "$GUARD" | cut -d'"' -f2)"
  HANDOFF5_TARGETS="$(grep -oE '^HANDOFF5_TARGETS="[^"]+"' "$GUARD" | cut -d'"' -f2)"
  HANDOFF6_OWNER="$(grep -oE '^HANDOFF6_OWNER="[^"]+"' "$GUARD" | cut -d'"' -f2)"
  HANDOFF6_TARGETS="$(grep -oE '^HANDOFF6_TARGETS="[^"]+"' "$GUARD" | cut -d'"' -f2)"
  [ -n "$HANDOFF1_OWNER" ] && [ -n "$HANDOFF1_TARGETS" ]
  [ -n "$HANDOFF2_OWNER" ] && [ -n "$HANDOFF2_TARGETS" ]
  [ -n "$HANDOFF3_OWNERS" ] && [ -n "$HANDOFF3_TARGETS" ]
  [ -n "$HANDOFF4_OWNER" ] && [ -n "$HANDOFF4_TARGETS" ]
  [ -n "$HANDOFF5_OWNER" ] && [ -n "$HANDOFF5_TARGETS" ]
  [ -n "$HANDOFF6_OWNER" ] && [ -n "$HANDOFF6_TARGETS" ]
  python3 - "$DEPMAP" "$HANDOFF1_OWNER" "$HANDOFF1_TARGETS" "$HANDOFF2_OWNER" "$HANDOFF2_TARGETS" "$HANDOFF3_OWNERS" "$HANDOFF3_TARGETS" "$HANDOFF4_OWNER" "$HANDOFF4_TARGETS" "$HANDOFF5_OWNER" "$HANDOFF5_TARGETS" "$HANDOFF6_OWNER" "$HANDOFF6_TARGETS" "${REPO}/deploy/opencode.json" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1]))
owner1, targets1, owner2, targets2, owners3, targets3, owner4, targets4, owner5, targets5, owner6, targets6 = sys.argv[2:14]
expected = {owner1: targets1.split(), owner2: targets2.split()}
for o in owners3.split():
    expected[o] = targets3.split()
expected[owner4] = targets4.split()
expected[owner5] = targets5.split()
expected[owner6] = targets6.split()
got = d.get("requiresSkills", {})
assert got == expected, f"requiresSkills {got} != guard handoffs {expected}"
# impliesMcp values must be real MCP server keys (dependency-map $comment claim)
oc = json.load(open(sys.argv[14]))
servers = set((oc.get("mcp") or {}).get("servers") or {})
for skill, mcps in d.get("impliesMcp", {}).items():
    for m in mcps:
        assert m in servers, f"{skill} implies unknown MCP server {m}"
print("ok")
PYEOF
}
