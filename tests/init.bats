#!/usr/bin/env bats

# Tests for installer/init.mjs (opencode-init) — the project-scoped selective installer.
# Covers the flag path (primary contract); the interactive TUI is not tested here
# (needs a real TTY). See PLANS/PLAN-GIT-286 Phase 5.4.

REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
INIT="node ${REPO}/installer/init.mjs"
REG="${REPO}/installer/registry.json"
OC="${REPO}/deploy/opencode.json"

# JSON helper: extract a value/length via python3 (already a setup.sh dependency).
jq_len() { python3 -c "import sys,json; print(len(json.load(sys.stdin)))"; }
jq_get() { python3 -c "import sys,json; d=json.load(sys.stdin); print($1)"; }

setup() {
  export TMP_PROJ="$(mktemp -d)"
  git -C "$TMP_PROJ" init -q
}
teardown() { rm -rf "$TMP_PROJ"; }

@test "registry.json exists with correct agent/skill counts" {
  [ -f "$REG" ]
  agents=$(jq_get "len(d['agents'])" < "$REG")
  skills=$(jq_get "len(d['skills'])" < "$REG")
  echo "agents=$agents skills=$skills" >&3
  # Count-agnostic: registry must match disk. BT-157. Enumeration is -maxdepth 1
  # to match build-registry.mjs (non-recursive): agents/overlays/*.md are body
  # fragments, not agents (#576 step 3.2 — semantics-preserving alignment).
  disk_agents=$(find "${REPO}/agents" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
  disk_skills=$(find "${REPO}/skills" -name 'SKILL.md' 2>/dev/null | wc -l | tr -d ' ')
  [ "$agents" = "$disk_agents" ]
  [ "$skills" = "$disk_skills" ]
}

@test "--list agents is valid JSON matching registry count" {
  count=$($INIT --list agents 2>/dev/null | jq_len)
  [ "$count" = "$(jq_get "len(d['agents'])" < "$REG")" ]
}

@test "--list agents --category review filters to reviewers" {
  count=$($INIT --list agents --category review 2>/dev/null | jq_len)
  [ "$count" = "3" ]
}

@test "--list skills is valid JSON matching registry count" {
  count=$($INIT --list skills 2>/dev/null | jq_len)
  [ "$count" = "$(jq_get "len(d['skills'])" < "$REG")" ]
}

@test "--list categories is valid non-empty JSON" {
  count=$($INIT --list categories 2>/dev/null | jq_len)
  [ "$count" -gt 10 ]
}

@test "--list presets shows all 10 presets" {
  count=$($INIT --list presets 2>/dev/null | jq_len)
  [ "$count" = "10" ]
}

@test "--describe code-review-subagent returns skills+delegates+modelAvailable" {
  out=$($INIT --describe code-review-subagent 2>/dev/null)
  skills=$(echo "$out" | jq_get "len(d['requiresSkills'])")
  delegates=$(echo "$out" | jq_get "len(d['delegatesTo'])")
  avail=$(echo "$out" | jq_get "d['modelAvailable']")
  echo "skills=$skills delegates=$delegates avail=$avail" >&3
  [ "$skills" = "15" ]
  [ "$delegates" -ge 4 ]
  [ "$avail" = "True" ]
}

@test "--expand review resolves transitive closure (4 agents incl. image-analyzer)" {
  agents=$($INIT --expand review 2>/dev/null | jq_get "len(d['agents'])")
  has_img=$($INIT --expand review 2>/dev/null | jq_get "'image-analyzer-subagent' in d['agents']")
  echo "agents=$agents has_image-analyzer=$has_img" >&3
  [ "$agents" = "4" ]
  [ "$has_img" = "True" ]
}

@test "install review --yes lands exactly 4 agents + 27 skills + codegraph (resolver deps)" {
  run $INIT --project "$TMP_PROJ" --preset review --yes
  [ "$status" -eq 0 ]
  agent_files=$(ls "$TMP_PROJ/.opencode/agents/" | wc -l)
  skill_dirs=$(ls "$TMP_PROJ/.agents/skills/" | wc -l)
  [ "$agent_files" -eq 4 ]
  [ "$skill_dirs" -eq 27 ]
}

@test "each installed agent has a model: frontmatter line" {
  $INIT --project "$TMP_PROJ" --preset review --yes >/dev/null 2>&1
  grep -q "^model:" "$TMP_PROJ/.opencode/agents/code-review-subagent.md"
}

@test "generated opencode.json is v2-shaped: skill deny-all first + scoped subagent permissions + builtins" {
  $INIT --project "$TMP_PROJ" --preset review --yes >/dev/null 2>&1
  python3 -c "
import json
d=json.load(open('$TMP_PROJ/.opencode/opencode.json'))
# top-level permissions: skill deny-all must be the FIRST rule (v2 last-match-wins)
p=d['permissions']
assert p[0]=={'action':'skill','resource':'*','effect':'deny'}, 'skill *:deny must be first, got '+json.dumps(p[0])
assert any(r.get('resource')=='reviewer-baseline-skill' and r.get('effect')=='allow' for r in p), 'review preset must allow reviewer-baseline-skill'
# scoped subagent permissions: deny-all FIRST, then per-agent allows
sub=[r for r in d['agents']['build']['permissions'] if r['action']=='subagent']
assert sub[0]=={'action':'subagent','resource':'*','effect':'deny'}, 'subagent *:deny must be first'
assert any(r['resource']=='code-review-subagent' and r['effect']=='allow' for r in sub), 'missing code-review-subagent subagent allow'
assert set(['build','plan','explore','general']).issubset(d['agents']), 'missing builtin agent blocks'
print('ok')"
}

@test "--dry-run writes nothing into the project" {
  $INIT --project "$TMP_PROJ" --preset core --yes --dry-run >/dev/null 2>&1
  [ ! -d "$TMP_PROJ/.opencode" ]
}

@test "non-TTY without --yes exits non-zero" {
  run $INIT --project "$TMP_PROJ" --preset core
  [ "$status" -ne 0 ]
}

@test "re-run install is idempotent (no error, same counts)" {
  $INIT --project "$TMP_PROJ" --preset review --yes >/dev/null 2>&1
  run $INIT --project "$TMP_PROJ" --preset review --yes
  [ "$status" -eq 0 ]
  agent_files=$(ls "$TMP_PROJ/.opencode/agents/" | wc -l)
  [ "$agent_files" -eq 4 ]
}

@test "--prune removes previously-installed entries absent from the new set" {
  $INIT --project "$TMP_PROJ" --preset review --yes >/dev/null 2>&1
  before=$(ls "$TMP_PROJ/.opencode/agents/" | wc -l)
  [ "$before" -eq 4 ]
  # switch to docs (disjoint agents) with --prune
  $INIT --project "$TMP_PROJ" --preset docs --yes --prune >/dev/null 2>&1
  # code-review-subagent should be gone (not in docs closure)
  [ ! -f "$TMP_PROJ/.opencode/agents/code-review-subagent.md" ]
}

@test "manifest is written and lists installed agents/skills" {
  $INIT --project "$TMP_PROJ" --preset core --yes >/dev/null 2>&1
  [ -f "$TMP_PROJ/.opencode/.opencode-init.manifest.json" ]
  m_agents=$(jq_get "len(d['agents'])" < "$TMP_PROJ/.opencode/.opencode-init.manifest.json")
  [ "$m_agents" -ge 1 ]
}

@test "clean-slate warning fires when ~/.config/opencode/agents is non-empty" {
  # This machine has a global deploy (51 agents). The summary (stderr) must mention it.
  run bash -c "$INIT --project '$TMP_PROJ' --preset core --dry-run 2>&1 >/dev/null"
  echo "$output" | grep -qi "GLOBAL DEPLOY DETECTED"
}

@test "--permit seeds deny-all-first build subagent rules incl. explore/general (v2)" {
  export HOME="$TMP_PROJ/home"
  mkdir -p "$HOME"
  $INIT add code-review-subagent --permit --yes >/dev/null 2>&1
  local cfg="$HOME/.config/opencode/opencode.json"
  [ -f "$cfg" ]
  jq_get "json.dumps(d['agents']['build']['permissions'][0])" < "$cfg" > "$TMP_PROJ/first.json"
  grep -q '"action": "subagent"' "$TMP_PROJ/first.json"
  grep -q '"resource": "\*"' "$TMP_PROJ/first.json"
  grep -q '"effect": "deny"' "$TMP_PROJ/first.json"
  jq_get "any(r['resource'] == 'explore' and r['effect'] == 'allow' for r in d['agents']['build']['permissions'])" < "$cfg" | grep -q True
  jq_get "any(r['resource'] == 'general' and r['effect'] == 'allow' for r in d['agents']['build']['permissions'])" < "$cfg" | grep -q True
  jq_get "any(r['resource'] == 'code-review-subagent' and r['effect'] == 'allow' for r in d['agents']['build']['permissions'])" < "$cfg" | grep -q True
}

@test "--permit does not inject explore/general into existing v2 permissions arrays" {
  export HOME="$TMP_PROJ/home"
  mkdir -p "$HOME/.config/opencode"
  cat > "$HOME/.config/opencode/opencode.json" <<'EOC'
{
  "permissions": [],
  "agents": {
    "build": {
      "permissions": [
        { "action": "subagent", "resource": "*", "effect": "allow" }
      ]
    }
  }
}
EOC
  $INIT add code-review-subagent --permit --yes >/dev/null 2>&1
  local cfg="$HOME/.config/opencode/opencode.json"
  jq_get "len([r for r in d['agents']['build']['permissions'] if r['resource'] == 'explore'])" < "$cfg" | grep -q '^0$'
  jq_get "len([r for r in d['agents']['build']['permissions'] if r['resource'] == 'code-review-subagent'])" < "$cfg" | grep -q '^1$'
}

@test "--target claude writes only ~/.claude/skills/<skill> (#377)" {
  export HOME="$TMP_PROJ/home"
  mkdir -p "$HOME"
  $INIT add tdd-workflow-skill --target claude --yes >/dev/null 2>&1
  [ -f "$HOME/.claude/skills/tdd-workflow-skill/SKILL.md" ]
  [ ! -d "$HOME/.config/opencode/skills/tdd-workflow-skill" ]
}

@test "--target claude with an agent: installs translated agent to ~/.claude/agents (#457 flips #377)" {
  export HOME="$TMP_PROJ/home"
  mkdir -p "$HOME"
  run bash -c "$INIT add tdd-subagent --target claude --yes 2>&1 >/dev/null"
  [ "$status" -eq 0 ]
  local F="$HOME/.claude/agents/tdd-subagent.md"
  [ -f "$F" ]
  grep -q '^name: tdd-subagent' "$F"
  ! grep -q "agent(s) skipped" <<< "$output"
}

@test "--format claude alias still works with deprecation warning (#377)" {
  export HOME="$TMP_PROJ/home"
  mkdir -p "$HOME"
  run bash -c "$INIT add tdd-workflow-skill --format claude --yes 2>&1 >/dev/null"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "deprecated"
  [ -f "$HOME/.claude/skills/tdd-workflow-skill/SKILL.md" ]
}

# ---- #401: project-scope installs honor agent-overrides.json (project > global > tier) ----

@test "project install honors a global agent-overrides.json pin (#401a)" {
  export HOME="$TMP_PROJ/home"
  mkdir -p "$HOME/.config/opencode"
  echo '{"explorer-subagent": {"model": "test/global-pin"}}' > "$HOME/.config/opencode/agent-overrides.json"
  $INIT add explorer-subagent --project "$TMP_PROJ" --yes >/dev/null 2>&1
  grep -q "^model: test/global-pin$" "$TMP_PROJ/.opencode/agents/explorer-subagent.md"
}

@test "project-level pin outranks the global pin (#401b)" {
  export HOME="$TMP_PROJ/home"
  mkdir -p "$HOME/.config/opencode"
  echo '{"explorer-subagent": {"model": "test/global-pin"}}' > "$HOME/.config/opencode/agent-overrides.json"
  mkdir -p "$TMP_PROJ/.opencode"
  echo '{"explorer-subagent": {"model": "test/project-pin"}, "code-review-subagent": {"model": "test/other-pin"}}' > "$TMP_PROJ/.opencode/agent-overrides.json"
  $INIT add explorer-subagent --project "$TMP_PROJ" --yes >/dev/null 2>&1
  grep -q "^model: test/project-pin$" "$TMP_PROJ/.opencode/agents/explorer-subagent.md"
  ! grep -q "test/global-pin" "$TMP_PROJ/.opencode/agents/explorer-subagent.md"
  ! grep -q "test/other-pin" "$TMP_PROJ/.opencode/agents/explorer-subagent.md"
}

@test "project install with no pins injects the tier default by value (#401c)" {
  export HOME="$TMP_PROJ/home"
  mkdir -p "$HOME"
  $INIT add explorer-subagent --project "$TMP_PROJ" --yes >/dev/null 2>&1
  grep -q "^model: zai-coding-plan/glm-5.3-flash$" "$TMP_PROJ/.opencode/agents/explorer-subagent.md"
}

# ---- #412: project models.json is conflict-gated like opencode.json (no clobber) ----

@test "hand-authored models.json survives project install with a --force hint (#412a)" {
  export HOME="$TMP_PROJ/home"
  mkdir -p "$HOME" "$TMP_PROJ/.opencode"
  echo '{"tiers": {"fast": "hand/authored"}}' > "$TMP_PROJ/.opencode/models.json"
  run $INIT add explorer-subagent --project "$TMP_PROJ" --yes
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "conflict (skipped, use --force).*models.json"
  grep -q "hand/authored" "$TMP_PROJ/.opencode/models.json"
  ! grep -q "glm-5.3-flash" "$TMP_PROJ/.opencode/models.json"
}

@test "--force overwrites models.json and the manifest claims it (#412b)" {
  export HOME="$TMP_PROJ/home"
  mkdir -p "$HOME" "$TMP_PROJ/.opencode"
  echo '{"tiers": {"fast": "hand/authored"}}' > "$TMP_PROJ/.opencode/models.json"
  $INIT add explorer-subagent --project "$TMP_PROJ" --yes --force >/dev/null 2>&1
  grep -q '"\$comment"' "$TMP_PROJ/.opencode/models.json"
  [ "$(jq_get "d['modelsPath']" < "$TMP_PROJ/.opencode/.opencode-init.manifest.json")" = "$TMP_PROJ/.opencode/models.json" ]
}

@test "previously-generated models.json re-installs silently (#412c)" {
  export HOME="$TMP_PROJ/home"
  mkdir -p "$HOME"
  $INIT add explorer-subagent --project "$TMP_PROJ" --yes >/dev/null 2>&1
  run $INIT add explorer-subagent --project "$TMP_PROJ" --yes
  [ "$status" -eq 0 ]
  [[ "$output" != *"conflict (skipped"* ]]
  grep -q "glm-5.3-flash" "$TMP_PROJ/.opencode/models.json"
}

@test "hand-authored models.json keeps protection across re-installs (#412d)" {
  export HOME="$TMP_PROJ/home"
  mkdir -p "$HOME" "$TMP_PROJ/.opencode"
  echo '{"tiers": {"fast": "hand/authored"}}' > "$TMP_PROJ/.opencode/models.json"
  # run 1: warn + skip; manifest must NOT claim the file (claim only what we wrote)
  $INIT add explorer-subagent --project "$TMP_PROJ" --yes >/dev/null 2>&1
  [ "$(jq_get "d.get('modelsPath')" < "$TMP_PROJ/.opencode/.opencode-init.manifest.json")" = "None" ]
  # run 2: warning repeats, file still intact — no silent clobber
  run $INIT add code-review-subagent --project "$TMP_PROJ" --yes
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "conflict (skipped, use --force).*models.json"
  grep -q "hand/authored" "$TMP_PROJ/.opencode/models.json"
}

@test "hand-authored opencode.json survives re-installs too (configPath twin, #412)" {
  export HOME="$TMP_PROJ/home"
  mkdir -p "$HOME" "$TMP_PROJ/.opencode"
  echo '{"mcp": {"myserver": {"type": "local", "command": ["echo"]}}}' > "$TMP_PROJ/.opencode/opencode.json"
  $INIT add explorer-subagent --project "$TMP_PROJ" --yes >/dev/null 2>&1
  run $INIT add code-review-subagent --project "$TMP_PROJ" --yes
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "conflict (skipped, use --force).*opencode.json"
  grep -q "myserver" "$TMP_PROJ/.opencode/opencode.json"
  [ "$(jq_get "d.get('configPath')" < "$TMP_PROJ/.opencode/.opencode-init.manifest.json")" = "None" ]
}

@test "project update migrates pre-flip .opencode/skills copies (#561)" {
  run $INIT add tdd-workflow-skill --project "$TMP_PROJ" --yes
  [ "$status" -eq 0 ]
  [ -d "$TMP_PROJ/.agents/skills/tdd-workflow-skill" ]
  # simulated pre-flip leftover (installed before the #561 destination flip)
  mkdir -p "$TMP_PROJ/.opencode/skills/tdd-workflow-skill"
  run $INIT add tdd-workflow-skill --project "$TMP_PROJ" --yes
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "migrated from .opencode/skills"
  [ ! -e "$TMP_PROJ/.opencode/skills/tdd-workflow-skill" ]
  [ -d "$TMP_PROJ/.agents/skills/tdd-workflow-skill" ]
}

@test "prune removes legacy-dir copies of pruned skills (#561)" {
  run $INIT add tdd-workflow-skill --project "$TMP_PROJ" --yes
  [ "$status" -eq 0 ]
  [ -d "$TMP_PROJ/.agents/skills/tdd-workflow-skill" ]
  # simulated pre-flip leftover
  mkdir -p "$TMP_PROJ/.opencode/skills/tdd-workflow-skill"
  # prune-only mode: empty selection removes everything manifest-owned
  run $INIT --project "$TMP_PROJ" --prune
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "legacy .opencode/skills"
  [ ! -e "$TMP_PROJ/.agents/skills/tdd-workflow-skill" ]
  [ ! -e "$TMP_PROJ/.opencode/skills/tdd-workflow-skill" ]
}

@test "add -g/--global installs user scope (npx-skills alias, #563)" {
  export HOME="$TMP_PROJ/home"
  mkdir -p "$HOME"
  run $INIT add tdd-workflow-skill -g --yes
  [ "$status" -eq 0 ]
  [ -d "${HOME}/.config/opencode/skills/tdd-workflow-skill" ]
  run $INIT add code-principles-skill --global --yes
  [ "$status" -eq 0 ]
  [ -d "${HOME}/.config/opencode/skills/code-principles-skill" ]
}

@test "add -g --project conflicts and exits non-zero (#563)" {
  run $INIT add tdd-workflow-skill -g --project "$TMP_PROJ" --yes
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "cannot combine --global with --project"
  [ ! -d "$TMP_PROJ/.agents/skills/tdd-workflow-skill" ]
  run $INIT add tdd-workflow-skill --project "$TMP_PROJ" -g --yes
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "cannot combine --global with --project"
}

@test "--target auto with no harnesses detected exits non-zero (#564)" {
  export HOME="$TMP_PROJ/empty-home"
  mkdir -p "$HOME"
  run $INIT add tdd-workflow-skill --target auto --yes
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "no harness config directories detected"
}

@test "--target auto installs to detected harnesses only (#564)" {
  export HOME="$TMP_PROJ/home"
  mkdir -p "$HOME/.agents"
  run $INIT add tdd-workflow-skill --target auto --yes
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "detected agents"
  [ -d "${HOME}/.agents/skills/tdd-workflow-skill" ]
  [ ! -e "${HOME}/.config/opencode/skills/tdd-workflow-skill" ]
}

@test "--target auto --project dedupes downgraded targets (#564)" {
  export HOME="$TMP_PROJ/home"
  mkdir -p "$HOME/.agents" "$HOME/.claude"
  run $INIT add tdd-workflow-skill --project "$TMP_PROJ" --target auto --yes
  [ "$status" -eq 0 ]
  [ -d "$TMP_PROJ/.agents/skills/tdd-workflow-skill" ]
  # agents+claude both downgrade to the opencode project target — one install
  [ ! -e "${HOME}/.agents/skills/tdd-workflow-skill" ]
  [ ! -e "${HOME}/.claude/skills/tdd-workflow-skill" ]
}

@test "-y and -p aliases work; --project -y value-eat is safe (#564)" {
  run $INIT add tdd-workflow-skill --project "$TMP_PROJ" -y
  [ "$status" -eq 0 ]
  [ -d "$TMP_PROJ/.agents/skills/tdd-workflow-skill" ]
  cd "$TMP_PROJ"
  export HOME="$TMP_PROJ/home2"
  mkdir -p "$HOME"
  run $INIT add code-principles-skill -p -y
  [ "$status" -eq 0 ]
  [ -d "$TMP_PROJ/.agents/skills/code-principles-skill" ]
  [ ! -e "$TMP_PROJ/-y" ]
}

@test "rm alias removes a user-scope install (#564)" {
  export HOME="$TMP_PROJ/home"
  mkdir -p "$HOME"
  run $INIT add tdd-workflow-skill -g --yes
  [ "$status" -eq 0 ]
  run $INIT rm tdd-workflow-skill
  [ "$status" -eq 0 ]
  [ ! -e "${HOME}/.config/opencode/skills/tdd-workflow-skill" ]
}

@test "list/ls command spellings mirror --list (#564)" {
  run $INIT list skills
  [ "$status" -eq 0 ]
  list_out="$output"
  run $INIT --list skills
  [ "$status" -eq 0 ]
  [ "$output" = "$list_out" ]
  run $INIT ls categories
  [ "$status" -eq 0 ]
  run $INIT ls
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "specify a category"
}

@test "--target auto does not self-inflate from the installer's own manifest dir (#564 review)" {
  export HOME="$TMP_PROJ/home"
  mkdir -p "$HOME/.claude"
  # a claude-target install creates ~/.config/opencode/ for its manifest —
  # the auto probe must not read that synthetic signal as "opencode installed"
  run $INIT add tdd-workflow-skill --target claude --yes
  [ "$status" -eq 0 ]
  [ -d "${HOME}/.config/opencode" ]
  run $INIT add code-principles-skill --target auto --yes
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "detected claude"
  [ ! -e "${HOME}/.config/opencode/skills/code-principles-skill" ]
  [ -d "${HOME}/.claude/skills/code-principles-skill" ]
}

@test "add --prune is rejected explicitly on all add paths (#567)" {
  run $INIT add tdd-workflow-skill --prune --yes
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "'--prune' is not an add flag"
  run $INIT add tdd-workflow-skill --project "$TMP_PROJ" --prune --yes
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "'--prune' is not an add flag"
  [ ! -d "$TMP_PROJ/.agents/skills/tdd-workflow-skill" ]
  run $INIT add --all --prune --yes
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "'--prune' is not an add flag"
  # auto-target loop forwards opts through the spread — the guard must still fire
  export HOME="$TMP_PROJ/home"
  mkdir -p "$HOME/.claude"
  run $INIT add tdd-workflow-skill --target auto --prune --yes
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "'--prune' is not an add flag"
}

@test "--target auto --dry-run emits one aggregated doc, multi-detected (#568)" {
  export HOME="$TMP_PROJ/home"
  mkdir -p "$HOME/.agents" "$HOME/.claude"
  run $INIT add tdd-workflow-skill --target auto --dry-run
  [ "$status" -eq 0 ]
  # bats merges stderr into $output — strip notices so python parses pure JSON
  echo "$output" | sed -n '/^{/,$p' | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['dryRun'] is True and d['auto'] is True and d['scope'] == 'user', d
assert len(d['targets']) == 2, d
assert [t['target'] for t in d['targets']] == ['agents', 'claude'], d
assert all(t['skills'] == ['tdd-workflow-skill'] for t in d['targets']), d
"
  [ ! -e "${HOME}/.agents/skills/tdd-workflow-skill" ]
  [ ! -e "${HOME}/.claude/skills/tdd-workflow-skill" ]
}

@test "--target auto --dry-run wraps single-detected too (#568)" {
  export HOME="$TMP_PROJ/home2"
  mkdir -p "$HOME/.claude"
  run $INIT add tdd-workflow-skill --target auto --dry-run
  [ "$status" -eq 0 ]
  echo "$output" | sed -n '/^{/,$p' | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['auto'] is True and len(d['targets']) == 1 and d['targets'][0]['target'] == 'claude', d
"
}

@test "--target auto --project --dry-run aggregates deduped targets (#568)" {
  export HOME="$TMP_PROJ/home3"
  mkdir -p "$HOME/.agents" "$HOME/.claude"
  run $INIT add tdd-workflow-skill --project "$TMP_PROJ" --target auto --dry-run
  [ "$status" -eq 0 ]
  echo "$output" | sed -n '/^{/,$p' | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['auto'] is True and d['scope'] == 'project', d
assert len(d['targets']) == 1, d
assert d['targets'][0]['dryRun'] is True, d
"
  [ ! -d "$TMP_PROJ/.agents/skills/tdd-workflow-skill" ]
  [ ! -e "${HOME}/.agents/skills/tdd-workflow-skill" ]
}

@test "explicit --target --dry-run keeps its plain unwrapped doc (#568)" {
  export HOME="$TMP_PROJ/home4"
  mkdir -p "$HOME/.claude"
  run $INIT add tdd-workflow-skill --target claude --dry-run
  [ "$status" -eq 0 ]
  echo "$output" | sed -n '/^{/,$p' | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['dryRun'] is True and d['target'] == 'claude', d
assert 'auto' not in d and 'targets' not in d, d
"
}
