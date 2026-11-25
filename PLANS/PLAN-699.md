# PLAN: Disable unused MCP servers by default

**Branch**: feat/699
**Issue**: https://github.com/darellchua2/civiltekk-skills/issues/699
**Base**: dev

## Acceptance Criteria
- [x] Root `opencode.json` disables Atlassian by default.
- [x] `deploy/opencode.json` keeps Atlassian and Alpha Vantage disabled by default.
- [x] Regression tests cover these defaults; optional Atlassian setup and the Alpha Vantage pack remain available.
- [x] JSON validation and the targeted Bats test pass.

## Dependency & Consumer Map

| Node (file/module) | Depends on (must precede) | Consumers (who depends on this) | Change risk |
|---------------------|---------------------------|---------------------------------|-------------|
| `opencode.json` | — | OpenCode sessions opened in this repository; MCP default regression test | low |
| `deploy/opencode.json` | — | Fresh user-space deployments; MCP default regression test | low (asserted, not edited) |
| `tests/test_mcp_count_consistency.bats` | `opencode.json`, `deploy/opencode.json` | Bats test suite / CI | low |
| `deploy/packs/pack-alpha-vantage.json` | `deploy/opencode.json` | Users explicitly enabling the Alpha Vantage pack | none (retained, not edited) |

## Implementation Phases

### Phase 1: Disable the unused default and guard it
- [x] **1.1** Set the Atlassian server to disabled in the repository-root `opencode.json`.
    — **Why:** Repository sessions currently start an MCP integration the project no longer uses.
    — **Done when:** Parsing `opencode.json` shows `mcp.servers.atlassian.disabled` is `true`.
    — **Consumers affected:** OpenCode sessions using this repository's config.
    — **Done:** Disabled Atlassian in the repository-root config; JSON validation passed; files: `opencode.json`; fixes: none
- [x] **1.2** Extend `tests/test_mcp_count_consistency.bats` to assert the root Atlassian default and the deployed Atlassian and Alpha Vantage defaults remain disabled.
    — **Why:** A regression check protects both the repo-local config and the shipped deployment defaults without removing opt-in support.
    — **Done when:** The targeted Bats test passes and `deploy/packs/pack-alpha-vantage.json` remains available.
    — **Consumers affected:** MCP config test suite and users who explicitly enable optional integrations.
    — **Done:** Added root Atlassian and deployed Alpha Vantage default assertions; full Bats suite passed (727/727); files: `tests/test_mcp_count_consistency.bats`; fixes: none

## Technical Notes
- The pipeline accepts `dev` as the base branch and resolves it to `origin/dev`.
- Alpha Vantage is already disabled in `deploy/opencode.json`; leave its pack and opt-in behavior unchanged.
- Atlassian remains available through the existing per-project setup path.

## Dependencies
- None.

## Risks & Mitigation
- The repo-local config change only affects new OpenCode sessions that load this configuration; user-specific overrides may still enable Atlassian. Keep optional setup intact for projects that need it.

## Trace
LOG Full gate selected because Phase 1 changes a configuration anchor with cross-module consumers; 727 Bats tests, JSON parsing, and `git diff --check` passed on the implementation tree, committed as a61f6293. No typed build target exists; E2E is not applicable because no frontend changed.
GATE a61f6293 tier=full lint=t typecheck=n.a build=- unit=t e2e=n.a
