# CivilTekk OpenCode & Claude Skills

A personal software-development skills collection — the agents, skills, and pipeline tooling I use daily — shared so you can take **a single skill** or adopt **the whole stack**.

- **125 ready-to-load skills + 34 specialist subagents**, natively targeting **OpenCode v2**
- **Same skills install to other harnesses**: Claude Code, Kimi Code, Kilo Code, and the cross-tool `~/.agents/` standard (Agent Skills open format)
- A **robust application-development pipeline**: ticket → PLAN → gated execution → review → merged PR, driven by a handful of slash commands

> **v2.0.0 upgrade?** See [`MIGRATION.md`](./MIGRATION.md) for breaking changes (stale agent cleanup, zip backup format, new `--rollback` / `--no-zip-backup` flags) and rollback instructions.

## Daily-driver commands

These four commands carry most of my day-to-day flow. **Slash commands ship with a full deploy** — a single-skill `npx add` install gives you the skills (invoked by natural language), not the command bindings.

| Command | What it does |
|---------|--------------|
| `/create-ticket` | Structured GitHub issue or JIRA ticket — platform detection, intake validation, labels. Ticket only: no branch, no PLAN, no execution. |
| `/run-worktree-pipeline` | Tracker-ticket-to-merged-PR pipeline via git worktrees — sync, PLAN authoring, adaptive review, gated execution, code review, PR merge; fully inline by default (subagents only on explicit request). Usage: `/run-worktree-pipeline [--dry-run] [base-branch] <ticket-refs...>` |
| `/run-plan` | Fully-automated per-phase PLAN execution with a tiered verification gate (scoped lint + typecheck + affected tests per phase; full gate on anchors and at exit), per-step traceability → commit → push; inline by default (subagent workers on explicit request). |
| `/goal` | Session goal tracking with budgets and auto-continue (server-side, from the goal plugin). |

The first two compose: `/create-ticket` makes the ticket, `/run-worktree-pipeline #NNN` takes it to a merged PR.

**One execution flavor — inline by default**: `/run-plan` and `/run-worktree-pipeline` execute fully in-session — zero subagents end to end (plan review — architecture via the `architecture-review-skill` decision tree —, execution via `plan-execution-inline-skill`, code review via `code-review-inline-skill`, and the PR route via the `civiltekk-pr-workflow-skill` create route all run in-session; the only deployed agent definitions still loaded as checklists are the Step 7 uiux reviewer and the requirements relay). Subagent orchestration (`plan-execution-skill` --gate workers) is an explicit opt-in on OpenCode — request it and, if its deps are missing, the run proceeds inline with a note. Plan-mode sessions get read-only `/worktree-pipeline-preview` — the same pipeline walked in preview mode (no worktree, no commits, no pushes, no PRs, no file writes); real execution stays pinned to Build via the command above.

## Installation

Three ways in, pick by appetite. All commands below work from any clone of this repo.

### 1. Take one skill (or agent) — the shadcn model

No clone needed; `npx` copies the skill directory into your config. See [issue #304](https://github.com/darellchua2/civiltekk-opencode-claude-skills/issues/304).

```bash
npx github:darellchua2/civiltekk-opencode-claude-skills add solid-principles-skill   # one skill
npx github:darellchua2/civiltekk-opencode-claude-skills add tdd-subagent             # agent + its required skills
npx github:darellchua2/civiltekk-opencode-claude-skills                              # bare = interactive TUI catalog
npx github:darellchua2/civiltekk-opencode-claude-skills remove solid-principles-skill
```

**Other harnesses** — skills follow the [Agent Skills](https://agentskills.io) open standard; `--target` controls the destination:

| Target | Destination | Notes |
|--------|-------------|-------|
| `opencode` (default) | `~/.config/opencode/{skills,agents}/` | Full opencode compat (model injection, strict-allowlist detection) |
| `auto` | all detected harness config roots | Probes `~/.config/opencode`, `~/.agents`, `~/.claude`, `~/.kimi-code`, `~/.config/kilo`, `~/.zcode`, `~/.copilot` — installs to every hit (`add` only; none found → error); `--dry-run` emits one aggregated JSON doc |
| `claude` | `~/.claude/skills/` · agents `~/.claude/agents/` | Skills verbatim (`model:` stripped); agents get additive `tools:`/`disallowedTools:` translation |
| `agents` | `~/.agents/{skills,agents}/` | Cross-tool shared dir — skills read by Kimi Code and pi, agents Kimi-only (pi has no agents concept); verbatim copies |
| `kimi` | `~/.kimi-code/{skills,agents}/` (user) · `.kimi-code/` (project) | Kimi Code native dirs; additive frontmatter translation |
| `kilo` | `~/.config/kilo/agent/` + `~/.kilo/skills/` (user) · `.kilo/` (project) | Kilo Code native dirs; additive `permission:`-map translation |
| `zcode` | `~/.zcode/{skills,agents}/` (user only) | ZCode dirs; additive `tools:`/`disallowedTools:` translation with ZCode deviations (subagent rules dropped — nesting ban; `tools:` omitted for skill-allow agents — exhaustive allowlists; `steps:`→`maxTurns:`). Project installs use the opencode target (Beta is user-level) |
| `copilot` | agents `~/.copilot/agents/` (user) · `.claude/agents/` (project) · skills `.github/skills/` (project) | Claude-format translation (same as `claude`); project dirs are the per-content-type documented VS Code workspace locations |
| `both` | opencode + Claude Code paths | Agents install to opencode only |

`--project` installs into `./.opencode/` (agents, `opencode.json`, manifests — full-service config generation) with skills going to `./.agents/skills/` (Agent Skills standard dir natively discovered by OpenCode and pi) instead of user scope. `--no-deps` skips declared skill prerequisites.

The catalog is also consumable via the ecosystem CLI: `npx skills add darellchua2/civiltekk-opencode-claude-skills` (skills only — project default, `-g` for global; no dependency resolution or agent installs). This installer mirrors its ergonomics: `-g`, `-y`, `-p`, `rm`, `list`, and `--target auto` all work; two divergences are deliberate — user scope is the default (not project), and installs are per-target copies (not symlinks) because targets apply model/permission translations.

### 2. Full deploy — the whole stack

Copies config + agents + skills to `~/.config/opencode/` and installs two PATH commands (`opencode-setup` to re-run the deploy from anywhere, `opencode-init` for project-scoped installs).

```bash
./deploy/setup.sh                 # interactive
./deploy/setup.sh --quick --yes   # non-interactive: config + skills, skip dependency checks
# Windows: powershell -ExecutionPolicy Bypass -File .\deploy\setup.ps1 -Quick -Yes
# No clone? npx -p github:darellchua2/civiltekk-opencode-claude-skills opencode-setup --quick --yes
```

Provider swap (Z.AI default): `./deploy/setup.sh --provider anthropic|openai|openrouter|zai` — agent models are tier-based and provider-agnostic (details in the collapsed reference below). Full flag table: `./deploy/setup.sh --help`, or the [collapsed reference](#full-setup-reference) at the end.

**Multi-agent detection (#573):** the deploy also probes which coding agents are installed (opencode, pi, codex, claude, kimi, kilo) and prints a found/missing table. With pi or codex present and a Z.AI key captured, it seeds a `zai` provider into `~/.pi/agent/models.json` (`apiKey` via `$ZAI_API_KEY` interpolation — key never stored) and `~/.codex/config.toml` (`env_key`; opt-in via `codex --profile zai`), then restarts the opencode background service so `{env:}` MCP substitution picks up the key — the fix for "the bashrc export never reached the MCP servers".

### 3. Per-project subset — presets

Not every project needs 34 agents + 125 skills. `opencode-init` installs a curated preset into `./.opencode/` (clean-slate isolation; additive over a global deploy — it warns):

```bash
opencode-init --list categories                              # introspect (JSON)
opencode-init --expand review                                # preview the resolved set
opencode-init --project . --preset review --yes              # install
npx github:darellchua2/civiltekk-opencode-claude-skills --project . --preset review --yes   # no prior deploy needed
```

| Preset | Use for |
|--------|---------|
| `core` | Minimal baseline (explorer + civiltekk-git-commits, continuous-learning, codegraph) |
| `review` | Code quality gates (code/architecture/language reviewers + 26 skills) |
| `frontend` | Web frontend (Next.js/React/a11y + uiux-reviewer, responsive-audit) |
| `backend` | Server / devops-lite (Python/DB/API/security + language-reviewer) |
| `docs` | Document generation (documentation + coverage + office docs) |
| `devops` | Git / infra / release (repo-ops + opentofu-explorer) |
| `business` | BD / founder workflows (discovery → requirements → technical-design) |
| `research` | Autonomous loops (autoresearch ml/code/research; ml needs GPU) |
| `inline-workers` | Inline delegation family — `plan-execution-inline-skill` + the testing/linting/documentation/responsive-audit/code-review/requirements inline skills, the `architecture-review-skill` decision-tree reviewer, the `requirements-inline-skill` detection-gate delegate, and their knowledge-skill closure; companion to the inline-default `/run-plan` and `/run-worktree-pipeline` |
| `cad` | CAD / robotics / hardware (cad-specialist + 15 CAD skills) |

## Directory structure

```
civiltekk-opencode-claude-skills/
├── skills/                      # 125 skill directories (source of truth)
├── agents/                      # 34 subagent .md files (source of truth)
├── plugins/                     # Local OpenCode plugins (vibeguard, ponytail, learnings, auto-continue, question-repair)
│   └── vibeguard.config.json    # Secret-masking regex patterns
├── deploy/                      # User-space deployment (setup.sh = bin: opencode-setup; opencode.json = config source of truth)
├── installer/                   # npx installer (init.mjs = bin: opencode-skill; registry, tiers, presets)
├── tests/                       # bats test suite (guards counts, isolation, portability)
├── PLANS/                       # Execution plans per ticket (git-committed history)
├── LEARNINGS/                   # Knowledge-persistence skeleton (auto-provisioned in target projects)
├── CHANGELOG.md                 # Release history (semantic-release generated)
├── CONTRIBUTING.md              # Contribution guide (skill/agent authoring)
├── MIGRATION.md                 # v1.x → v2.0 migration guide
└── THIRD_PARTY_LICENSES.md      # Vendored-skill attributions (MIT/Apache-2.0)
```

`skills/` and `agents/` are the single source of truth — edit there, then redeploy. Never edit deployed `~/.config/opencode/` copies. Every skill directory is fully self-contained (the `npx add` copy model — enforced by `tests/test_skill_isolation.bats`).

## Support & reporting issues

Both issue forms enforce a search-first attestation and structured fields — a complete report gets fixed faster:

- **[🐞 Bug report](https://github.com/darellchua2/civiltekk-opencode-claude-skills/issues/new?template=bug_report.yml)** — unexpected behavior or a broken feature
- **[🚀 Feature request](https://github.com/darellchua2/civiltekk-opencode-claude-skills/issues/new?template=feature_request.yml)** — new capability or enhancement

Blank issues are disabled; pick a template. Include your environment (OS, Node, opencode version, install method) for bugs.

Want to contribute a skill or agent? See [`CONTRIBUTING.md`](./CONTRIBUTING.md).

## Prerequisites

- **Node.js v20+** and npm (setup scripts can install Node for you; nvm recommended)
- An API key for your provider (Z.AI default; Anthropic/OpenAI/OpenRouter via `--provider`)
- **GitHub CLI** (`gh`) — recommended for ticket/PR flows (`gh auth login`)
- **ripgrep** (`rg`) — recommended, faster search; falls back to `grep`

---

# Deep reference

Everything below is detail you rarely need at first install — expanded on demand.

<details>
<summary><strong>Model resolution (v2.0) — tier-based, provider-agnostic</strong></summary>

Agent models are **tier-based and provider-agnostic**. Source agent files contain no hardcoded model — each agent is categorized into a tier (`reasoning` / `fast` / `docs` / `vision` / `long-context`) in `installer/agent-tiers.json`, and the concrete model is resolved at deploy time:

```bash
./deploy/setup.sh --provider anthropic      # or: openai, openrouter, zai (default)
./deploy/setup.sh --mix                     # mix providers per tier
./deploy/setup.sh --models-only             # re-resolve models only
```

Override precedence (highest first):

| File | Scope |
|------|-------|
| `<project>/.opencode/agent-overrides.json` | per-agent pin, project-local |
| `~/.config/opencode/agent-overrides.json` | per-agent pin, global |
| `<project>/.opencode/models.json` | tier map, project-local |
| `~/.config/opencode/models.json` | tier map, global (written by `--provider`) |
| `installer/models.default.json` | Z.AI defaults |

> **Vision tier (Z.AI):** `image-analyzer-subagent` + `error-resolver-subagent` + `uiux-reviewer-subagent` + `zai-media-subagent` run on `zai-coding-plan/glm-5.3-flash` (native multimodal — image/video/pdf input, 1M ctx). When native perception is unavailable, they fall back to the inline recipe embedded in `image-analyzer-subagent`, calling the same model via direct API. Requires `opencode auth login` (Z.AI) or `ZAI_API_KEY`.

| Tier | Use for |
|------|---------|
| `reasoning` | Correctness-critical: reviewers, repo-ops, tdd, migration, pptx, technical-design, discovery, requirements |
| `fast` | Exploratory/low-impact: explorer, testing, nextjs/cad/office specialists, document creators, pr-workflow, startup agents |
| `docs` | documentation, linting, coverage |
| `long-context` | Large-context research/code loops: autoresearch-ml/code/research |
| `vision` | Native multimodal: image-analyzer, error-resolver, uiux-reviewer, zai-media |

See `AGENTS.md` § Subagent Model Tiering for the full table.
</details>

<details>
<summary><strong>MCP servers, provider packs, and skill profiles</strong></summary>

The configuration ships 11 MCP server entries. **3 are enabled by default:**

| Server | Type | Purpose |
|--------|------|---------|
| `codegraph` | local (npx) | Pre-indexed code knowledge graph |
| `zai-web-reader` | remote | Web page content extraction |
| `zai-web-search` | remote | Web search with cited results |

The remaining 8 ship `disabled: true` and are opt-in: `atlassian` (JIRA/Confluence OAuth), `next-devtools` (Next.js DevTools), `markitdown` (document-to-Markdown, plugins off), `docling` (layout-aware extraction, ~3-4 GB), `chrome-devtools` (live Chrome automation, telemetry pre-disabled), `playwright` (logged-in web automation via accessibility snapshots), `alpha-vantage` (market/macro/commodities data; `ALPHA_VANTAGE_API_KEY`), `nanobanana` (Google Nano Banana image generation; `GEMINI_API_KEY`). The last three are also available as provider packs (below).

To enable one for a single project, add it to the project's `opencode.json` as a **full entry** (v2 replaces `mcp.servers.<name>` atomically — a bare `{"disabled": false}` stub is inert):

```json
{ "mcp": { "servers": { "atlassian": { "type": "local", "command": ["npx", "-y", "mcp-remote", "https://mcp.atlassian.com/v1/mcp"], "disabled": false } } } }
```

Globally: set `"disabled": false` in `~/.config/opencode/opencode.json`, or use a provider pack. The `opencode-repo-setup-skill` automates per-project enablement interactively. The `mcp-install-assistant-skill` is the guided front door: it inventories your servers, prechecks keys/browsers, and walks global `--enable-pack` or per-project enablement.

**Provider packs** — one flag flips a logical group ON at deploy time (packs are JSON partials in `deploy/packs/`):

| Pack | Servers enabled | Requires |
|------|----------------|----------|
| `markitdown` | markitdown | Python server (auto-installed by setup.sh) |
| `docling` | docling | Python + `docling-mcp[local]` (~3-4 GB) |
| `nextjs` | next-devtools | A running Next.js dev server |
| `chrome-devtools` | chrome-devtools | Chrome stable (telemetry + CrUX pre-disabled) |
| `playwright` | playwright | npx (self-installs on first spawn) — logged-in web work via accessibility snapshots |
| `alpha-vantage` | alpha-vantage | Remote; `ALPHA_VANTAGE_API_KEY` env var (free tier: 25 req/day) — market/macro/commodities data |
| `nanobanana` | nanobanana | `GEMINI_API_KEY` env var — Google Nano Banana image generation (4K, multi-reference editing) |

> **Troubleshooting:** `--enable-pack` fails with "no full definition" when the deployed config predates the pack — re-run `setup.sh` and answer **y** to the overwrite prompt (or re-copy `deploy/opencode.json`), then re-run the enable. Applies to `--dry-run` previews too.

> **Autodesk MCP policy (official-only):** no Autodesk MCP pack ships. The former pack pointed at `mcp.autodesk.com` endpoints that do not resolve. Autodesk MCP may only be re-admitted once an **official** Autodesk MCP server's connection details are verifiable from Autodesk's own documentation — the archived `autodesk-platform-services/aps-mcp-server-nodejs` sample (clone-based, archived 2026-05) does not qualify. Until then, use the Autodesk Platform Services REST APIs via `autodesk-aps-skill`.

```bash
./deploy/setup.sh --enable-pack markitdown,docling   # multiple packs, comma-separated
```

Default state of every pack is **OFF**. Design history: [issue #268](https://github.com/darellchua2/civiltekk-opencode-claude-skills/issues/268).

**Skill profiles** — deploy-time primary visibility (#333). Every allowed skill's `description` loads into the primary session at startup (~90 tokens each). Default deploy is **lean** (70 primary-visible skills + deny-all); subagents are profile-immune and all 125 skills stay on disk:

```bash
./deploy/setup.sh                     # default: lean
./deploy/setup.sh --skill-profile full  # shipped allowlist verbatim
./deploy/setup.ps1 -SkillProfile full   # Windows parity
```

> **Interim workaround (#481):** the 4 reviewer agents' 26-skill union is temporarily primary-visible in lean because opencode v2.0.11 ignores agent-frontmatter `skill` allows in child sessions ([upstream anomalyco/opencode#50149](https://github.com/anomalyco/opencode/issues/50149)). This note is the deferral record.

#### Installed a skill the primary session can't see?

Lean deploys carry a **skill deny-all-first allowlist**: every installed skill stays on disk, but the primary session can only invoke a skill that has an explicit allow rule. A freshly `npx … add`-ed skill is therefore on disk yet invisible to the primary session — subagents are profile-immune and keep full access.

Per-skill fix (the shipped file stays the source of truth):

```json
{ "action": "skill", "resource": "<skill-name>", "effect": "allow" }
```

Add that rule to `deploy/opencode.json`'s `permissions` array, then re-run `./deploy/setup.sh` and **accept the config copy** when prompted — stale allow rules are reconciled only on an accepted copy (declining keeps your existing config untouched). The wholesale alternative: `./deploy/setup.sh --skill-profile full` ships the allowlist verbatim.

Adding a skill **to this repo** touches five surfaces, not one — the deeper checklist lives in [`LEARNINGS/patterns/command-referenced-skills-need-deploy-allowlist-entries.md`](LEARNINGS/patterns/command-referenced-skills-need-deploy-allowlist-entries.md) and [`LEARNINGS/conventions/add-skill-deploy-checklist.md`](LEARNINGS/conventions/add-skill-deploy-checklist.md).

**Notes:**
- `filesystem` MCP is **permanently removed** — built-in `read`/`write`/`edit`/`glob`/`grep`/`bash` cover it; a filesystem MCP caused tool-selection ambiguity.
- Opt-in servers ship **telemetry pre-disabled**: chrome-devtools (`--no-usage-statistics`, `--no-performance-crux`, `--redact-network-headers`, update-check off) and next-devtools (`NEXT_TELEMETRY_DISABLED=1`). The enabled `zai-*` servers send data by design (that is their function); `codegraph` is purely local.
- `markitdown` runs the official PyPI server pinned `==0.0.1a7` with `MARKITDOWN_ENABLE_PLUGINS=false` — cloud extras present-but-dormant; residual: audio input uploads to Google Speech, YouTube URLs contact YouTube. Local file conversions make no network calls.
- `docling` is pinned to local conversion (`DOCLING_CONVERSION_MODE=local`).
- Every `npx -y <pkg>` first run hits the npm registry to download — not telemetry, but it is a phone-home; pre-install globally to avoid.
</details>

<details>
<summary><strong>Plugins — vibeguard, ponytail, learnings auto-inject, auto-continue, question repair, location keepalive</strong></summary>

Six local plugins ship in `plugins/` — zero runtime npm dependencies, air-gap safe, active on OpenCode v2.

**Vibeguard (secret masking).** Masks `.env` secrets in provider-bound traffic via regex patterns (`vibeguard.config.json`); the LLM provider never sees plaintext values, tools receive real values at execution time. Verify with `OPENCODE_VIBEGUARD_DEBUG=1 opencode` (replace-counts > 0). Per-project keywords: uncommitted `./vibeguard.config.json` at project root (first config wins — re-include the global patterns). Residual risks (documented honestly): `/share` exports plaintext (never share sessions that processed secrets); no fail-closed if config is missing; session DB stores plaintext locally; MCP structured (non-string) output bypasses redaction. Prefer `$ENV_VAR` references over inline literals in everything you generate.

**Ponytail (minimal-code enforcement).** [Ponytail](https://github.com/DietrichGebert/ponytail) v4.10.0 (MIT, vendored) — the 7-rung "lazy senior dev" ladder (YAGNI → reuse → stdlib → native → installed dep → one-liner → minimum-that-works), injected into coding agents via a **scoped wrapper** (`plugins/opencode-ponytail-scoped.ts`): read-only/research agents skip injection; per-agent mode overrides via `PONYTAIL_AGENT_MODE_MAP`; `/ponytail lite|full|ultra|off` per session, `/ponytail default <mode>` persists under the opencode data dir. Skill-only installs ship the wrapper plugin alongside the ponytail skills (#533); non-opencode targets get a notice.

**Learnings auto-inject.** Injects a compact manifest (~200-400 tokens) of `LEARNINGS/*.md` titles + paths into the system prompt at session start; the model `read()`s bodies on demand. Same off-set as ponytail (read-only agents). `/learnings`, `/learnings-on|off`, `/learnings-refresh`. Env: `LEARNINGS_AUTOINJECT_DEFAULT` (on), `LEARNINGS_AUTOINJECT_USER` (off), `LEARNINGS_AUTOINJECT_MAX` (30).

**Auto-continue v2.** Self-heals long-running sessions two ways: (1) transient provider errors (SSE timeouts, ECONNRESET, context overflow, tool-protocol failures) get a "continue" with exponential backoff at idle boundaries; (2) a busy-stall watchdog aborts sessions frozen "working" on a silent event stream (upstream #46310/#24900) after `OPENCODE_AUTO_CONTINUE_STALL_MS` (default 15 min; `0` disables) and resumes them the same way. Never aborts fresh-activity sessions, never resumes a user-cancelled session (ESC latch), hard cap 5 consecutive recoveries (reset by a real user message). Env prefix: `OPENCODE_AUTO_CONTINUE_*`.

**Question repair.** Normalizes malformed `question` tool payloads before the schema validator hard-fails (fills missing `label`/`description`/`question`/`header` from their counterparts, defaults `multiple`, drops beyond-repair items). Valid payloads pass through as the same reference. Debug: `OPENCODE_QUESTION_REPAIR_DEBUG=1` at server start.

**Location keepalive v2.** Protects actively-running sessions from OpenCode v2's 60-minute location TTL: the server evicts any location (per project directory) with no *durable* session event for 60 min and interrupts its running sessions — but streaming deltas and `session.tool.progress` are ephemeral, so a healthy agent inside a long silent tool or generation looks idle and dies mid-run with `reason: "inactivity"` (verified against v2.0.18: bulk same-second session interruptions matching `location services evicted` log lines). Every interval (default 30 min), each probe-confirmed busy session is PATCHed with its own unchanged title, publishing a durable `session.renamed` that resets the TTL; idle sessions are never touched, so idle locations still evict. Keep `OPENCODE_AUTO_CONTINUE_STALL_MS` (15 min default) below the keepalive interval so the auto-continue watchdog still wins races for true silent hangs. Env prefix: `OPENCODE_LOCATION_KEEPALIVE_*` (`ENABLED` on, `INTERVAL_MS` 30 min with a 90%-of-TTL clamp, `DEBUG` off).

Attribution: `plugins/ATTRIBUTION.md`; skill-level attributions in `THIRD_PARTY_LICENSES.md`.
</details>

<details>
<summary><strong>Skill catalog — 125 skills by category</strong></summary>

Current count: **125** (history: 123 after the BT-142 pptx migration → consolidations and vendoring brought it to 146; 6 superseded skills were archived under `skills/_archived/` and removed in #563; the six ticket skills were consolidated into `ticketing-skill` in #599 — `npx … add ticket-creation-skill|git-issue-labeler-skill|git-issue-updater-skill|jira-git-integration-skill|jira-status-updater-skill|jira-ticket-labeler-skill` are removed, use `add ticketing-skill`; the two creation skills were consolidated into `civiltekk-opencode-creation-skill` in #603 — their `add` names are removed, use `add civiltekk-opencode-creation-skill`; the two commits skills were consolidated into `civiltekk-git-commits-skill` in #603 — their `add` names are removed, use `add civiltekk-git-commits-skill`; the two context skills were consolidated into `civiltekk-context-optimization-skill` in #603 — their `add` names are removed, use `add civiltekk-context-optimization-skill`; the two documentation skills were consolidated into `civiltekk-documentation-sync-skill` in #603 — their `add` names are removed, use `add civiltekk-documentation-sync-skill`; the two startup docs skills were consolidated into `civiltekk-startup-docs-skill` in #603 — their `add` names are removed, use `add civiltekk-startup-docs-skill`; the three Python backend skills were consolidated into `civiltekk-python-backend-skill` in #603 — `npx … add python-backend-skill|python-packaging-skill|fastapi-pydantic-orm-patterns-skill` are removed, use `add civiltekk-python-backend-skill`; the two diagram skills were consolidated into `civiltekk-diagram-skill` in #603 — `npx … add ascii-diagram-creator-skill|mermaid-diagram-creator-skill` are removed, use `add civiltekk-diagram-skill`; the three ponytail skills were consolidated into `civiltekk-ponytail-audit-skill` in #603 — `npx … add ponytail-audit-skill|ponytail-review-skill|ponytail-debt-skill` are removed, use `add civiltekk-ponytail-audit-skill`; the two API skills were consolidated into `civiltekk-api-spec-skill` in #603 — `npx … add api-design-skill|openapi-contract-adherence-skill` are removed, use `add civiltekk-api-spec-skill`; the four React/TS quality skills were consolidated into `civiltekk-react-quality-skill` in #603 — `npx … add react-best-practices-skill|react-hooks-antipatterns-skill|react-render-antipatterns-skill|typescript-dry-principle-skill` are removed, use `add civiltekk-react-quality-skill`; the inline documentation and docstring skills were consolidated into `civiltekk-documentation-inline-skill` in #603 — `npx … add documentation-inline-skill|docstring-generator-skill` are removed, use `add civiltekk-documentation-inline-skill`; the two requirements skills were consolidated into `civiltekk-requirements-specs-skill` in #604 — `npx … add brd-creation-skill|srs-creation-skill` are removed, use `add civiltekk-requirements-specs-skill`; the four Next.js skills were consolidated into `civiltekk-nextjs-skill` in #604 — `npx … add nextjs-standard-setup-skill|nextjs-devtools-mcp-skill|nextjs-image-usage-skill|threejs-nextjs-skill` are removed, use `add civiltekk-nextjs-skill`; the four Z.AI media skills were consolidated into `civiltekk-zai-media-skill` in #604 — `npx … add zai-image-generation-skill|zai-video-skill|zai-asr-skill|zai-ocr-skill` are removed, use `add civiltekk-zai-media-skill`; the seven OpenTofu skills were consolidated into `civiltekk-opentofu-skill` in #604 — `npx … add opentofu-provider-setup-skill|opentofu-provisioning-workflow-skill|opentofu-aws-explorer-skill|opentofu-kubernetes-explorer-skill|opentofu-neon-explorer-skill|opentofu-keycloak-explorer-skill|opentofu-ecr-provision-skill` are removed, use `add civiltekk-opentofu-skill`; the two PR workflow skills were consolidated into `civiltekk-pr-workflow-skill` in #604 — `npx … add pr-creation-workflow-skill|pr-merge-workflow-skill` are removed, use `add civiltekk-pr-workflow-skill`; the three test-generation skills were consolidated into `civiltekk-test-generation-skill` in #604 — `npx … add test-generator-framework-skill|python-pytest-creator-skill|nextjs-unit-test-creator-skill` are removed, use `add civiltekk-test-generation-skill`; one cross-harness setup skill added in #654; one catalog install-assistant skill added in #657; the inline requirements delegate added in #641).

| Category | Skills | Purpose |
|-----------|---------|---------|
| **Framework** (16) | civiltekk-test-generation-skill, linting-workflow, civiltekk-pr-workflow-skill, error-resolver-workflow, tdd-workflow, docx-creation, xlsx-specialist, pdf-specialist, frontend-design, uiux-review-skill, civiltekk-api-spec-skill, performance-optimization-skill, civiltekk-requirements-specs-skill, technical-design-creation-skill, vision-creation-skill, interactive-document-rendering-skill | Generic workflows, testing patterns (one consolidated test-generation skill), document creation, UI design + review, API design, contract adherence, performance, and the document ladder (BRD/SRS/vision + technical design documents) |
| **Presentation** (3) | pptx-generate-slide-skill, pptx-generate-template-skill, pptx-template-modifier-skill | Template-driven PowerPoint generation — extract, fill, extend |
| **Office Utilities** (2) | ooxml-editing-skill, office-thumbnail-skill | Generic Office OOXML surgical edits and visual thumbnail/conversion |
| **Language-Specific** (3) | language-linting, changelog-python-cliff, civiltekk-python-backend-skill | Language-specific linting (Ruff/ESLint/Checkstyle/dotnet format), Python changelogs, and Python backend engineering — scaffolding, packaging, and production patterns (one consolidated skill) |
| **Framework-Specific** (4) | civiltekk-nextjs-skill, amplify-nextjs-deployment, civiltekk-react-quality-skill, accessibility-a11y-skill | Next.js 16, React 19, TypeScript, accessibility, and AWS Amplify deployment — setup, runtime diagnosis, image usage, and Three.js integration in one consolidated nextjs skill; React performance, hooks/render anti-patterns, and TypeScript DRY in one consolidated react-quality skill |
| **Frontend Animation** (8) | gsap-core, gsap-timeline, gsap-scrolltrigger, gsap-plugins, gsap-utils, gsap-react, gsap-frameworks, gsap-performance | GSAP web-animation guidance — tweens/easing/stagger, timeline sequencing, ScrollTrigger, plugins, utils helpers, React (`useGSAP`) and Vue/Svelte integration, performance. Vendored from official greensock/gsap-skills (MIT) |
| **OpenCode Meta** (7) | civiltekk-opencode-creation, opencode-skills-maintainer, opencode-repo-setup, civiltekk-documentation-sync, opencode-v2-migration, skill-generalizer, browser-fallback-skill | Agent and skill creation/maintenance (one consolidated creation skill), documentation sync + drift auditing (one consolidated doc-sync skill), per-repo MCP/project-config setup, v1→v2 migration detect/triage, skill generalization auditing, managed-browser toolset fallback routing |
| **Harness Setup** (1) | civiltekk-coding-harness-setup-skill | Cross-harness project parity — detects OpenCode v1/v2, pi, Claude Code, Codex and provisions the neutral `.agents/skills/` dir, canonical AGENTS.md with per-harness shims, per-harness config deltas, MCP only where supported |
| **OpenTofu** (1) | civiltekk-opentofu-skill | Infrastructure as Code — provider setup + auth + state backends, plan→apply workflow and lifecycle/state discipline, AWS/Kubernetes/Neon/Keycloak exploration, and ECR + GitHub OIDC provisioning per BETEKK standards (one consolidated skill) |

| **Git/Workflow** (12) | civiltekk-diagram, dev-uat-promotion-skill, ticketing-skill, plan-execution-skill, plan-execution-inline-skill, worktree-pipeline-skill, wayfinder-skill, gh-cli-setup-skill, civiltekk-git-commits, semantic-release-convention, version-bump-standard, git-branch-workflow-setup-skill | Diagrams (ASCII-to-image and Mermaid fenced blocks, one consolidated diagram skill), git operations, dev→uat promotion batching, release conventions, version bumping, commit discipline — conventional format plus compact budgets (one consolidated commits skill), branch workflow orchestration, the full ticket lifecycle (create/classify/start/update/close on GitHub Issues or JIRA) via `/create-ticket`, fully-automated per-phase plan execution via `/run-plan` (inline workers by default; subagent workers on explicit request), the tracker-ticket-to-merged-PR worktree pipeline via `/run-worktree-pipeline`, and oversized-work planning as decision-ticket maps |
| **Documentation** (4) | coverage-readme-workflow, unslop-skill, technical-writing-skill, civiltekk-documentation-inline-skill | Documentation generation — per-language docstrings (PEP 257, Javadoc, JSDoc, XML) and the in-session docs delegate (one consolidated skill) |
| **Communication** (1) | email-drafter-skill | Business-email drafting — process, tone frames, slop checklist |
| **Academic & Research Writing** (2) | horseshoe-paper-writing-skill, research-paper-generation-skill | Academic & research paper writing (Horseshoe Diagram Method, journal-submission formats; codebase→paper generation) |
| **Code Quality** (16) | solid-principles, clean-code, clean-architecture, design-patterns, object-design, code-smells, complexity-management, deprecated-code-cleanup-skill, blast-radius-skill, civiltekk-ponytail-audit-skill, language-review-checklists-skill, reviewer-baseline-skill, testing-inline-skill, linting-inline-skill, code-review-inline-skill, architecture-review-skill | Code quality analysis, patterns, @deprecated code cleanup, over-engineering audits and `ponytail:` debt ledgers (one consolidated ponytail skill), the inline testing/linting/code-review delegates, and the decision-tree architecture-review methodology |
| **Agent Optimization** (6) | continuous-learning, eval-harness, verification-loop, search-first, civiltekk-context-optimization, agent-introspection-debugging | AI agent session optimization, research-first workflow, context auditing and compaction strategy (one consolidated context skill), and agent debugging |
| **Autoresearch** (4) | autoresearch-core-skill, autoresearch-ml-skill, autoresearch-code-skill, autoresearch-research-skill | Autonomous research loops: 5-stage Understand→Hypothesize→Experiment→Evaluate→Log methodology. ML training (GPU), code optimization, literature review. Mechanical `{"pass":bool,"score":N}` evaluators — no LLM self-judgment |
| **Startup/Business** (2) | civiltekk-startup-docs-skill, construction-bd-skill | Startup pitch decks and founder business documentation (one consolidated startup-docs skill), construction proposals |
| **Configuration** (4) | markitdown-mcp-skill, docling-mcp-skill, mcp-install-assistant-skill, civiltekk-install-assistant | markitdown and docling MCP setup; guided MCP install assistant (inventory, precheck, enable, verify); guided skill/subagent catalog install assistant (find, dry-run install, maintain) |
| **Security** (2) | security-audit-skill, authentication-authorization-skill | Security auditing, vulnerability scanning, and auth implementation |
| **DevOps** (5) | docker-containerization-skill, monorepo-management-skill, database-migration-skill, logging-observability-skill, aws-iac-safety-skill | Containerization, monorepos, database migrations, observability, and IaC safety |
| **Planning & Alignment** (3) | grilling-skill, domain-modeling-skill, requirements-inline-skill | Relentless interview/grilling sessions, canonical domain-model capture, and the in-session requirements detection gate + Mode R/A delegate |
| **Responsive & Visual Testing** (3) | wireframer-skill, playwright-responsive-audit-skill, responsive-audit-inline-skill | Low-fidelity wireframes, Playwright-driven responsive UI audit + fix, and the in-session responsive audit delegate |
| **CAD & Hardware Design** (15) | cad-generation-skill, cad-viewer-skill, cad-step-parts-skill, cad-dxf-skill, cad-urdf-skill, cad-srdf-skill, cad-sdf-skill, cad-sendcutsend-skill, cad-gcode-skill, cad-bambu-labs-skill, cad-implicit-skill, autodesk-aps-skill, civil-3d-skill, open3d-skill, cad-redraw-skill | Parametric CAD (STEP/STL/3MF/GLB), CAD Viewer previews, off-the-shelf parts, DXF drawings, evidence-aware drawing redraw, robot descriptions (URDF/SRDF/SDF), G-code slicing, 3D printing, SendCutSend validation, implicit CAD, Autodesk APS, Civil 3D, Open3D |
| **Media Generation** (1) | civiltekk-zai-media-skill | Z.AI media endpoints: text-to-image (GLM-Image), text/image-to-video (CogVideoX-3), audio transcription (GLM-ASR), layout-aware OCR (GLM-OCR) — artifacts saved to local files |

Browse live: the [GitHub Pages catalog](https://darellchua2.github.io/civiltekk-opencode-claude-skills/) (deployed on every `main` push), or `opencode-init --list skills`.
</details>

<details>
<summary><strong>Agents — 34 subagents + 4 config-builtins</strong></summary>

34 agent `.md` files (plus 4 config-builtin agents defined in `opencode.json`: `build`, `plan`, `explore`, `general`). Highlights:

| Subagent | Purpose |
|----------|---------|
| **code-review-subagent** | Comprehensive code review (Code Quality skills, blast-radius evidence grading, ponytail lean lens) |
| **architecture-review-subagent** | Architecture and design patterns, call-graph analysis |
| **language-reviewer-subagent** | Multi-language review — Python, TS/JS, Go, Rust, Java |
| **pr-workflow-subagent** / **repo-ops-specialist-subagent** | PR creation / git + release operations |
| **tdd-subagent** / **testing-subagent** / **linting-subagent** | TDD workflow / test generation / lint execution |
| **nextjs-specialist-subagent** | Next.js 16 scaffolding + runtime diagnosis + audit |
| **docx/pptx/xlsx specialist subagents** | Office document pipelines (Word, PowerPoint, Excel) |
| **image-analyzer / zai-media / uiux-reviewer** | Vision tier — native multimodal analysis, media generation, 13-axis UI/UX review |
| **cad-specialist-subagent** | CAD/engineering/robotics — orchestrates 15 CAD skills |
| **discovery / requirements / technical-design specialists** | Discovery sessions → Vision docs; BRD/SRS drafting; technical design + ADRs |
| **autoresearch-ml/code/research subagents** | Autonomous loops (GPU training, code optimization, literature review) |
| **loop-operator-subagent** | Autonomous loop execution with self-correction |
| **opencode-tooling / opencode-v2-migration subagents** | Skills/agents/rules creation + doc sync; v1→v2 migration execution |
| **startup-founder / startup-ceo / office-document routers** | Business operations routing hubs |

Some subagents recognize natural-language triggers (e.g. "create pr", "pitch deck", "design review", "PowerPoint") — the trigger surface is each agent's `description` frontmatter in `agents/*.md`; per-class model assignments and delegation guidance: `AGENTS.md` § Subagent Model Tiering.

**Subagent nesting:** the shipped config (`deploy/opencode.json`) sets `subagent_depth: 3` (opencode default is 1) — required for the autoresearch delegation chains. Each level multiplies token cost; lower to 2 for tighter runs.

**Iteration protocol (opt-in):** a 5-stage autoresearch loop (Understand → Hypothesize → Experiment → Evaluate → Log) that 29 skills can opt into — off by default; enable via `AUTORESEARCH_PROTOCOL=1` or `ar-enable`. Retrofitted skills emit mechanical `{"pass":bool,"score":N}` output and auto-revert failed experiments. Safety: `skills/autoresearch-core-skill/references/iteration-safety.md`.
</details>

<details>
<summary><strong>Knowledge persistence — LEARNINGS + auto-inject</strong></summary>

Skills like `continuous-learning` persist knowledge across sessions:

| Storage | Scope | Purpose |
|---------|-------|---------|
| `LEARNINGS/` in target projects | Curated, git-committed | Patterns, ADRs, anti-patterns, solutions, conventions |
| `~/.config/opencode/learnings/` | User-level, cross-project | Personal preferences and patterns |

The `memory` tool's V1 plugin has no v2 release — `LEARNINGS/*.md` + the auto-inject plugin + `AGENTS.md` discovery is the memory layer (watch-list for v2-compatible re-adds in `AGENTS.md` § Project Learnings).

**How it works:** `setup.sh` creates `~/.config/opencode/learnings/` at user level; `continuous-learning` auto-provisions `LEARNINGS/` in target projects; review agents save findings as report content; agents discover learnings via the auto-injected manifest + explicit file reads. In this repo, `LEARNINGS/` ships as an empty skeleton — locally-written entries are gitignored (maintainer memory stays local).
</details>

<details>
<summary><strong>CodeGraph — pre-indexed code knowledge graph</strong></summary>

[CodeGraph](https://github.com/colbymchenry/codegraph) is a local SQLite knowledge-graph MCP server: symbol relationships, call graphs, and code structure instantly instead of grep/glob/Read chains.

| Metric | Without | With |
|--------|---------|------|
| Tool calls per exploration | 30-50+ | 1-6 |
| Exploration time | 1-2 min | 15-35 s |
| API key required | — | No (100% local) |

Per-project init (required before tools work): `codegraph init -i` → creates `.codegraph/` (gitignore it); a watcher auto-syncs. 19+ languages. Beneficiaries: `explore` (built-in), code-review (`codegraph_impact`), architecture-review (call graphs), testing (affected tests).
</details>

<details>
<summary><strong>Language Server Protocol (LSP)</strong></summary>

OpenCode v1 shipped native LSP (~30 servers) feeding diagnostics into the agent loop. **OpenCode v2 accepts `lsp` config but does not run language servers or produce diagnostics** — the block is inert; rely on the project's lint/typecheck/compiler commands (this repo's verification gates already work that way).

LSP is deliberately NOT enabled in the distributed config — this repository is a configuration distributor with no application code to diagnose. To enable in a target project: `"lsp": true` or selective (`{"lsp": {"typescript": {"disabled": false}}}`) in the project's `opencode.json`. Built-ins include tsserver, pyright, rust-analyzer, gopls, clangd, jdtls, terraform-ls. Set `OPENCODE_DISABLE_LSP_DOWNLOAD=true` to prevent auto-downloads (V1-era).
</details>

<details>
<summary><strong>Skill portability contract</strong></summary>

Skills ship to multiple harness targets and operating systems. Three conventions (rules 1–2 enforced by `tests/test_portability.bats`):

1. **Capability-binding blocks** — harness-specific mechanisms (background shells, interactive prompts, subagent delegation) are written with per-harness rows plus a portable fallback; agents self-select their row.
2. **Portability metadata** — `metadata.os: "linux, macos"` and `metadata.harness: "opencode"` in skill frontmatter; the installer warns when target or platform doesn't match.
3. **Bash rule** — shell snippets state `Requires bash (git-bash/WSL on Windows)` or use a `node -e` one-liner.

Full contract: `AGENTS.md` § Portability contract.
</details>

<details>
<summary><strong>Testing &amp; development recipes</strong></summary>

Test installer changes without touching your real `~/.config/opencode/`:

```bash
git clone https://github.com/darellchua2/civiltekk-opencode-claude-skills
node installer/init.mjs add tdd-subagent --dry-run     # 1. preview, write nothing
npm link && opencode-skill add solid-principles-skill --dry-run && npm unlink -g   # 2. real bin
npx github:darellchua2/civiltekk-opencode-claude-skills#feat/my-branch add X --dry-run   # 3. branch via npx
HOME="$(mktemp -d)" node installer/init.mjs add tdd-workflow-skill --yes             # 4. sandboxed HOME
bats tests/update.bats                                # 5. CI safety (--yes/--dry-run only)
```

**Downstream template:** [installer/templates/api-quality/](./installer/templates/api-quality/) — a Redocly lint ruleset + pre-commit hook enforcing OpenAPI authoring quality for repos this config's API skills work against (see its README for adoption).

Update installed content without a full setup rerun:

```bash
npx github:darellchua2/civiltekk-opencode-claude-skills update          # re-copy changed entries
npx github:darellchua2/civiltekk-opencode-claude-skills update --prune  # also remove registry-removed entries
```

**Redeploy contract:** `setup.sh --yes` force-copies content; full and `--skills-only` redeploys also prune manifest-tracked entries removed from this repo (the `update --prune` arm); existing skills/agents snapshot to the backup dir's `content-backup/` first — restore via the rollback flow. `--select` deploys also converge: a `prune-registry-removed` step runs `init.mjs prune` after the selected groups land, removing entries whose names left this repo and reporting them in the deploy output (#610). Manual convergence for any scope remains `update --prune` (or `init.mjs prune` for the registry-removed-only predicate).

Environment variable persistence: macOS/Linux writes shell rc; Windows uses `setx` / `$PROFILE` (Git Bash / PowerShell respectively).
</details>

#### Full setup reference

<details>
<summary><strong>Full setup reference — every flag</strong></summary>

Two setup scripts: `setup.sh` (macOS/Linux/WSL/Git Bash — full feature set) and `setup.ps1` (Windows — thin launcher forwarding to setup.sh via Git-Bash/WSL).

| Option (bash) | Option (PowerShell) | Description |
|----------------|----------------------|-------------|
| `--quick` | `-Quick` | Copy config + skills only (skip dependency checks) |
| `--skills-only` | `-SkillsOnly` | Deploy skills only (requires @opencode/cli installed) |
| `--update` | `-Update` | Update OpenCode CLI to latest |
| `--check-catalog` | `-CheckCatalog` | Warn if `installer/provider-models.json` drifted from models.dev; regenerate: `node deploy/regen-provider-models.mjs` |
| `--dry-run` | `-DryRun` | Preview all actions without changes |
| `--yes` | `-Yes` | Auto-accept all prompts |
| `-v, --verbose` | `-Verbose` | Enable detailed debug logging |
| `--rollback [TARGET]` | `-RollbackTarget <T>` | Restore from a previous backup: `list`, `latest`, `TIMESTAMP`, or `VERSION`. Pre-rollback safety backup first |
| `--no-zip-backup` | `-NoZipBackup` | Skip zip archive creation |
| `--keep-backups <N>` | `-KeepBackups <N>` | Keep N most recent backups (default 5; 0 = all deleted; negative = keep all) |
| `--provider <p>` | `-Provider <p>` | Swap provider (zai\|anthropic\|openai\|openrouter) |
| `--preset <name>` | `-Preset <name>` | Restore a saved preset (models.json; deploy-plan.json only consumed together with `--select`) |
| `--save-preset <name>` | `-SavePreset <name>` | Save models.json + deploy-plan.json as a named preset |
| `--list-items` | `-ListItems` | Dump the deploy item catalog (skills/agents/…) |
| `--select` | `-Select` | Pick deploy items interactively per item (emits a deploy plan) |
| `-P, --peonping` | `-Peonping` | Install PeonPing sound notifications only |
| `-A, --enable-auto-update` | `-EnableAutoUpdate` | (removed) accepted no-op — schedule updates externally, e.g. cron |
| `-D, --disable-auto-update` | `-DisableAutoUpdate` | Disable automatic updates |
| `-S, --schedule-update <s>` | `-ScheduleUpdate <s>` | Set update-check frequency: daily, weekly, monthly, manual (default) |
| `-C, --check-update` | `-CheckUpdate` | Check for available updates without installing |
| `--mix` | `-Mix` | Mix providers per tier |
| `--models-only` | `-ModelsOnly` | Re-resolve models only |
| `--migrate` | `-Migrate` | Run v1.x → v2.0 migration |
| `--force` | `-Force` | Re-resolve, ignoring preserved hand-edits |
| `--enable-pack <p>` | `-EnablePack <p>` | Provider packs (see MCP section) |
| `--skill-profile <p>` | `-SkillProfile <p>` | lean (default) \| full |
| `--help` | `-Help` | Detailed help + examples |

Subcommands (aliases over the flags): `install \| update \| rollback \| peonping \| plan \| check-catalog`

**What setup does:** copies `deploy/.AGENTS.md` → `~/.config/opencode/AGENTS.md`; copies `skills/` and agents; copies `deploy/opencode.json` → `~/.config/opencode/opencode.json` (single source of truth — v2 reads only `opencode.json`/`opencode.jsonc`; a coexisting `opencode.jsonc` is parked as `.legacy-ignored`, never deleted); backs up before overwriting. Installed `opencode-setup` symlinks back to the clone it deployed from — edit files there, re-run here.
</details>

## License

Apache-2.0 — see [`LICENSE`](./LICENSE). Vendored skills carry their own attributions in [`THIRD_PARTY_LICENSES.md`](./THIRD_PARTY_LICENSES.md).
