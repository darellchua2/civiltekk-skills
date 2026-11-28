#!/usr/bin/env bats

# Tests for MCP server count consistency across documentation surfaces.
# Catches the latent off-by-one bug fixed in PLAN-GIT-262 Phase 6.
#
# Source of truth: deploy/opencode.json `mcp` block length.
# Documentation surfaces that must match:
#   - README.md "ships N MCP server entries"
#   - deploy/setup.sh "MCP SERVERS (N):"
#
# Note: deploy/setup.ps1 and setup.sh banner refs
# refer to the AUTO-START count, not the total — those are
# intentionally different and not asserted here.
# UPDATE (PLAN-GIT-333 Phase 6): atlassian is opt-in per-project
# (opencode-repo-setup-skill). zai-vision-mcp-server / zai-zread,
# mermaid were removed entirely (native vision tier, inline mermaid
# blocks, gh/webfetch cover them).
# UPDATE (GIT-336): zai-web-search re-added and enabled — deliberate
# reversal of 161c21d removal ("no consumers" falsified by #336).
# Auto-start is now 3 (codegraph, zai-web-reader, zai-web-search).
# UPDATE (GIT-364): zai-vision-mcp removed entirely (native multimodal
# vision tier is the default and only path; agents embed an inline
# direct-API fallback recipe). setup.sh banner "(N)" counts non-pack
# servers (auto-start + atlassian) = 4.

CONFIG="deploy/opencode.json"

# Compute the actual count from the source of truth.
# Uses python3 (already a setup.sh dependency for codegraph init).
actual_mcp_count() {
  python3 -c "import json; print(len(json.load(open('${CONFIG}'))['mcp']['servers']))"
}

@test "mcp_count_opencode_json_is_consistent_across_docs" {
  actual="$(actual_mcp_count)"
  echo "Actual MCP count in ${CONFIG}: ${actual}" >&3

  # README.md must match
  readme_count=$(grep -oE 'ships [0-9]+ MCP server entries' README.md | grep -oE '[0-9]+' | head -1)
  echo "README.md count: ${readme_count}" >&3
  [ "$readme_count" = "$actual" ]

  # setup.sh help text (#474 de-bloat): carries NO hand-maintained count at
  # all — the exact drift class this ticket removed cannot recur in help.
  run grep -qE 'MCP SERVERS \([0-9]+\)' deploy/setup.sh
  [ "$status" -ne 0 ]
  grep -q 'MCP SERVERS:' deploy/setup.sh
}

@test "mcp_count_markitdown_present" {
  # Phase 2 of PLAN-GIT-262 — markitdown must be registered (v2: disabled flag)
  python3 -c "import json; d=json.load(open('${CONFIG}')); assert 'markitdown' in d['mcp']['servers'], 'markitdown missing'; assert d['mcp']['servers']['markitdown']['disabled'] is True, 'markitdown must be opt-in'"
}

@test "mcp_count_atlassian_is_opt_in" {
  # PLAN-GIT-333 Phase 6 — atlassian must be per-project opt-in
  python3 -c "import json; d=json.load(open('${CONFIG}')); assert d['mcp']['servers']['atlassian']['disabled'] is True, 'atlassian must be opt-in'"
}

@test "mcp_count_root_atlassian_is_disabled_by_default" {
  python3 -c "import json; d=json.load(open('opencode.json')); assert d['mcp']['servers']['atlassian']['disabled'] is True, 'repo-local atlassian must be disabled by default'"
}

@test "mcp_count_alpha_vantage_removed" {
  # alpha-vantage pack + server entry removed entirely (2026-11-28). The pack
  # list is derived from deploy/packs/, so a leftover base-config entry would
  # resurface in the picker without its pack.
  python3 -c "import json; d=json.load(open('${CONFIG}')); assert 'alpha-vantage' not in d['mcp']['servers'], 'alpha-vantage must stay removed'"
}

@test "mcp_count_zai_zread_and_vision_removed" {
  # zai-zread removed (GIT-332); zai-vision-mcp removed (GIT-364 — native
  # multimodal vision tier + inline agent fallback recipes are the only paths)
  python3 -c "import json; d=json.load(open('${CONFIG}')); assert 'zai-zread' not in d['mcp']['servers'], 'zai-zread must be removed'; assert 'zai-vision-mcp' not in d['mcp']['servers'], 'zai-vision-mcp must be removed (GIT-364)'"
}

@test "mcp_count_mermaid_removed_web_search_present" {
  # GIT-336 — zai-web-search re-added (enabled) as deliberate reversal of 161c21d
  # ("no consumers" falsified by issue #336 demand; no websearch plugin supports Z.AI).
  python3 -c "import json; d=json.load(open('${CONFIG}')); assert 'mermaid' not in d['mcp']['servers'], 'mermaid MCP must be removed (inline blocks + mmdc)'; assert d['mcp']['servers']['zai-web-search']['disabled'] is False, 'zai-web-search must be present and enabled (GIT-336)'"
}

@test "mcp_count_auto_start_is_three" {
  # Three auto-start servers: codegraph, zai-web-reader, zai-web-search (GIT-336).
  # atlassian is opt-in (Phase 6); zai-vision-mcp removed (GIT-364);
  # zai-zread / mermaid remain removed.
  auto_count=$(python3 -c "import json; d=json.load(open('${CONFIG}')); print(sum(1 for v in d['mcp']['servers'].values() if v.get('disabled') is False))")
  echo "Auto-start (disabled: false) MCP count: ${auto_count}" >&3
  [ "$auto_count" = "3" ]
}
