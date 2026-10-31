# Repository-Specific Agent Instructions

Repo conventions only. Usage docs (install, deploy commands, file tree, chaining syntax) live in `README.md` and user-level `deploy/.AGENTS.md` (deploys to `~/.config/opencode/AGENTS.md`). Do not duplicate here.

## Repository Purpose

Multi-mode OpenCode configurator: user-space deploy (`./deploy/setup.sh` → `~/.config/opencode/`) and shadcn-style individual installs (`npx github:darellchua2/civiltekk-opencode-claude-skills add <name>`) with per-skill prerequisites (`installer/dependency-map.json` `requiresSkills`; `--no-deps` opts out).

Install targets (`--project`, `--target claude|agents|kimi|kilo|zcode|copilot`), their destination dirs, and translation caveats live in `README.md` — the usage-docs home (target support: [issue #304](https://github.com/darellchua2/civiltekk-opencode-claude-skills/issues/304)).

## Source of Truth

The root `skills/` and `agents/` dirs are the **single source** for skills and agents. Never edit deployed `~/.config/opencode/` copies — edit source, then redeploy.

## Skill Isolation Contract (#437)

Every skill directory under `skills/` (name suffix or not) must be **fully self-contained** — all scripts, schemas, and fixtures it needs live inside its own tree — because `npx github:darellchua2/civiltekk-opencode-claude-skills add <name>` copies one directory per requested skill (plus its **declared** `requiresSkills` prerequisites, which are themselves whole self-contained skills; `--no-deps` opts out). `tests/test_skill_isolation.bats` is the mechanical enforcement: it bans `skills/_common` references, parent-chain path escapes, sibling-skill paths outside the declared handoff, new `_`-prefixed shared dirs, and vendored-copy drift.

- **Cross-skill code duplication is intentional.** Shared helpers are vendored per skill (per-skill copy model), not factored into shared packages. Do not "DRY up" duplicated code across skills by extracting a common module — that is the exact regression this contract bans.
- **No new shared `_`-prefixed dirs** (e.g. a `skills/_common/`). The former `skills/_common/scripts` engine was vendored into each pptx skill as `scripts/_common/` and the shared dir deleted.
- **Vendored copies stay in sync**: the three pptx skills' `scripts/_common` trees must remain byte-identical (guard-enforced). Fix a vendored bug once, copy to all three trees, run the guard.
- **Cross-skill runtime deps are banned by default.** The declared exceptions, all in the guard's allowlist: `plan-execution-inline-skill → {testing,linting,responsive-audit}-inline-skill + civiltekk-documentation-inline-skill` (#597 — the inline executor routes its delegate matrix to the inline worker family), and `{autoresearch-code, autoresearch-ml, autoresearch-research}-skill → autoresearch-core-skill` (#602 — the loop skills cite the core protocol host's references at runtime). The guard's `HANDOFF1_OWNER`/`HANDOFF1_TARGETS` vars (uniform owner → space-separated-targets shape) plus the `HANDOFF3_OWNERS`/`HANDOFF3_TARGETS` multi-owner pair (every owner maps to every target) — mirrored by the `installer/dependency-map.json` `requiresSkills` entries — are the source of truth for the allowlist: a new handoff updates those first, then the SKILL.md prose — or duplicate the code instead.

## Secret Masking

Vibeguard masks `.env` secrets in provider-bound traffic via regex patterns (`plugins/vibeguard.config.json`). **OpenCode v2: shipped as a local v2 port (`plugins/opencode-vibeguard-v2.ts`, npm pin removed) — masking is active; the `permissions` deny rules for `*.env` are the second layer.** Verification + per-project overlay: `security-audit-skill` (also documents residual risks: `/share` plaintext, no fail-closed, plaintext session DB).

## Dependency Management

`package-lock.json` is committed. Dependency changes MUST run `npm install` and commit the regenerated lockfile — `npm ci` hard-fails on drift.

## Subagent Locations

| Location | Scope | Deployed? |
|----------|-------|-----------|
| `agents/*.md` | Global (all projects) | Yes — copied by `deploy/setup.sh` |
| `.opencode/agents/*.md` | Project-only | No — stays in repo |

Project-level agents must NOT be counted in setup scripts or README.

## Subagent Model Tiering (v2.0)

Tiers live in `installer/agent-tiers.json`; models are resolved at deploy time from `installer/models.default.json` (Z.AI defaults) and are provider-agnostic — swap via `installer/provider-presets.json` without editing agent files. See `MIGRATION.md`.

| Tier | Default (Z.AI) | Use for |
|------|----------------|---------|
| `primary` | `glm-5.3` (1M ctx) | Primary session only — never for subagents. |
| `reasoning` | `glm-5.3` (200k) | Correctness-critical: reviewers (code/architecture/language), repo-ops-specialist, tdd, opentofu-explorer, loop-operator, opencode-tooling, opencode-v2-migration, pptx-specialist, responsive-audit, technical-design-specialist, discovery-specialist, requirements-specialist |
| `fast` | `glm-5.3-flash` (1M) | Exploratory/low-impact: explorer, testing, nextjs/cad/office-docs specialists, document creators (docx/xlsx), pr-workflow, startup agents (ceo/founder) |
| `docs` | `glm-5.3-flash` (1M) | documentation, linting, coverage |
| `long-context` | `glm-5.3` (1M ctx) | Large-context research/code loops: autoresearch-ml, autoresearch-code, autoresearch-research — designated subagent tier; subagents never use `primary` directly |
| `vision` | `glm-5.3-flash` (1M) | Native multimodal (image/video/pdf): `image-analyzer-subagent` + `error-resolver-subagent` + `uiux-reviewer-subagent` + `zai-media-subagent` (see fallback below) |

Pick by purpose: correctness-critical → `reasoning`; exploratory → `fast`; docs/lint → `docs`; research/code loops → `long-context`; image perception → `vision`.

**Vision fallback:** when native perception is unavailable ("model does not support image input", text-only session), image-analyzer, error-resolver, and uiux-reviewer fall back to the inline bash recipe embedded in `image-analyzer-subagent`, calling the Z.AI vision API directly at `glm-5.3-flash` — the same multimodal model, invoked over raw HTTP instead of the provider binding (coding-plan endpoint preferred, PAAS fallback; requires `ZAI_API_KEY`).

**Resolution precedence (highest wins):** project `.opencode/agent-overrides.json` > global `~/.config/opencode/agent-overrides.json` > project `.opencode/models.json` > global `~/.config/opencode/models.json` > `installer/models.default.json`. Swap provider: `setup.sh --provider <p>`; mix per tier: `setup.sh --mix` (stored in `models.json`, re-resolve with `--models-only`); per-agent pin: global `agent-overrides.json`. Built-ins `explore`→`fast` and `general`→`reasoning` are patched by `deploy/setup.sh` (models written into the deployed `opencode.json` at `deploy/setup.sh:728-743`), not the tier registry.

## Adding Skills or Subagents — Sync Rules

| Trigger | What to update |
|---------|---------------|
| New/removed MCP server | MCP count, auto-start listing, help text |
| New/removed skill | Skill count, category listing, banner |
| New/removed agent | Agent count, help text listing |
| `opencode.json` config change | MCP server entries if added/removed |

Files: `deploy/setup.sh`, `deploy/setup.ps1` (Windows mirror), `README.md` (Skill Categories + Subagents tables). Then invoke `civiltekk-documentation-sync-skill` or delegate to `opencode-tooling-subagent`.

## Skill / Agent Frontmatter Contract

Verified against opencode.ai v2 docs 2026-09-14. All new/edited SKILL.md and agent files MUST conform.

**Skills — runtime-read keys** (all else ignored):
| Key | Rule |
|-----|------|
| `name` | Required. MUST equal directory name (`^[a-z0-9]+(-[a-z0-9]+)*$`, ≤64 chars) |
| `description` | Required, 1–1024 chars. House style: ≤50 words, preserve trigger phrases |
| `license` | `Apache-2.0` (house default; existing MIT exceptions grandfathered) |
| `compatibility` | `opencode` |
| `metadata` | Opaque string map, zero runtime behavior. House sub-keys: `protocol`, `pattern`, `os`, `harness` (portability — see §Portability contract) |
| `category` | Installer-registry-only (build-registry.mjs, init.mjs, setup.sh counts) — invisible to OpenCode, never delete |

Skill gating does NOT belong in SKILL.md — it lives in the `permissions` array (`action:"skill"` rules) of `opencode.json` or agent frontmatter only.

**Agents — runtime-read keys:** `description` (required), `steps`, `disabled`, `system` (JSON prompt key; legacy `prompt` auto-translated), `model` (string or `model#variant`), `permissions` (NOT deprecated `tools`; array of `{action,resource,effect}` rules), `mode`, `hidden`, `color`, `request.body.temperature`, `request.body.top_p`. Source files ship no `model:` — tiers inject it at deploy time. `category` is installer-registry-only. Source agent `.md` files ship native v2 frontmatter: `permissions:` rules arrays (order matters — last matching rule wins), no `model:` (tier-injected at deploy); the markdown body is the system prompt.

After ANY frontmatter change: run `node installer/build-registry.mjs` and commit `installer/registry.json`.

### Portability contract

Skills deploy to multiple harness targets (`--target claude|agents|kimi|kilo|zcode|copilot`) and OSes. Three rules; the portability guard test (#515) enforces rules 1–2, review enforces rule 3:

1. **Capability-binding block** — a skill body that invokes a harness-specific runtime mechanism presents it as a capability with per-harness bindings plus a portable fallback (the agent self-selects its row; unknown harnesses fall through to the fallback):

   ```markdown
   <capability sentence>.
   - OpenCode: <mechanism>
   - Claude Code: <mechanism>
   - Other/none: <portable fallback — nohup+log-poll / plain-reply question / inline>
   ```

2. **Metadata vocabulary** — `metadata` gains two house sub-keys (still opaque, zero runtime effect). Values are **double-quoted, comma-separated lowercase strings** — the runtime schema is a string-to-string map and the registry parser has no flow-sequence support, so never brackets or block sequences:
   - `os: "linux, macos"` — declare when the skill does NOT run everywhere (e.g. xvfb/pkill → `os: "linux"`); omit when unrestricted.
   - `harness: "opencode"` — declare on skills about OpenCode itself (creation/migration/config-audit). `installer/build-registry.mjs` extracts both into `registry.json`; #514 adds the `installer/init.mjs` warning for cross-target/platform installs (init.mjs reads `registry.json` only).
3. **Bash rule** — every bash snippet states `Requires bash (git-bash/WSL on Windows)` or is written as a `node -e` one-liner (Node is guaranteed wherever the installer ran; jq/xvfb/pkill are not).

## Return Contract

All subagents return (additive signal fields allowed beyond, never replacing):
**Status:** success | partial | failed
**Output:** file path(s) / key result, one line
**Summary:** 2–3 sentences max
**Issues:** blockers, warnings, or "None"

**Reviewer additions** (architecture, code, language, uiux) — required on every review: `Patterns applied/violated: [{id: <LEARNINGS-slug>, status: applied|violated, evidence: <file:line>}]`; emit `[]` if none, never omit.

## Project Learnings

`LEARNINGS/` is a template in this repo; in target projects, check it before reviewing/planning. Storage, the recall/capture procedure, and the auto-inject manifest live in user-level `deploy/.AGENTS.md` §Memory Hygiene.

## Office Document Extraction Routing

**Single source of truth: `office-document-router-skill`** (routes `markitdown`, `docling`, `pdf` — #680 consolidated the office family). This section summarizes the ladder; the router's SKILL.md owns it. Binary office docs (`.docx`, `.pptx`, `.xlsx`, born-digital `.pdf`) need an extraction engine — `Read` cannot parse them. Escalate only when the cheaper tier is insufficient:

| Tier | Engine | Best for | Enable |
|------|--------|----------|--------|
| 1 | markitdown (MCP) — router route `markitdown` | Fast text dumps of born-digital docs (~1s/50 pages; local conversion, plugins off — note: audio inputs upload to Google Speech and YouTube URLs contact YouTube, #487) | `--enable-pack markitdown` (consent-gated) |
| 2 | docling (CLI or MCP) — router route `docling` | Layout-aware: complex tables, multi-column, scanned PDFs | CLI `pip install --user docling` (ask consent, ~3-4 GB); MCP `--enable-pack docling` |
| 3 | image-analyzer-subagent | Visual understanding: charts, diagrams, screenshots | always available (native multimodal) |
| 4 | pdf route — router route `pdf` | Structured PDF data: forms, fillable fields, OCR-as-purpose | load route |

markitdown and docling are both opt-in (disabled by default). When markitdown is disabled, tell the user to `--enable-pack markitdown`. When its output is insufficient, escalate to docling — if absent, ask consent via `question` (never auto-install 3-4 GB). Headless/CI: soft-fail to markitdown best-effort.
