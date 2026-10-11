# PLAN: laya-guard plugin — local Laya classifier + permission gate

**Branch**: feat/671
**Issue**: https://github.com/darellchua2/civiltekk-skills/issues/671
**Base**: main

## Acceptance Criteria

From #671 (inherited verbatim; the PLAN never rewrites them):

- [ ] `plugins/opencode-laya-guard.ts` committed — zero npm imports; registers evaluate hook + `laya_classify` tool
- [ ] Node >=24 sidecar (`plugins/laya-guard/`) — JSONL stdio protocol; warm model; exits with parent
- [ ] Fail-closed invariants hold (missing answers => p=1; sidecar failure => hook degrades to `ask` in enforce, log in shadow)
- [ ] `laya-guard.config.json` shipped with `mode: "shadow"`; thresholds in config, never model
- [ ] setup.sh provisions deps + model idempotently, offline-safe on re-run, Linux-gated with Windows notice; `setup.ps1` mirrors the skip
- [ ] `deploy/opencode.json`: 3 hard deny rules merged above the skill allowlist
- [ ] Shadow log metadata-only (no file contents/env values); repo `.gitignore` entry
- [ ] `plugins/ATTRIBUTION.md` entries for `@receptron/laya` (MIT) + Convai weights (Apache-2.0)
- [ ] Bats suite green in CI: air-gap, fail-closed, shadow-default, no-content-leak guards (grep-based, CI-safe)
- [ ] README: usage, calibration (shadow->enforce), tuning notes
- [ ] Three skills wired with optional classifier consult lines
- [ ] Enforce NOT enabled by default

## Dependency & Consumer Map

Verified context (session record): opencode v2 plugin runtime = embedded Bun 1.4.2
(tag `v2.0.26`, commit `9b4ec57`; `$bunfs` artifacts in the shipped binary) —
hence the sidecar architecture; `ctx.permission.hook("evaluate", ...)` and
`ctx.tool.transform` are documented v2 APIs; local plugins load from
`~/.config/opencode/plugins/` which `deploy_plugins()` already populates.

| Node (file/module) | Depends on (must precede) | Consumers (who depends on this) | Change risk |
|---------------------|---------------------------|---------------------------------|-------------|
| `plugins/laya-guard/sidecar.mjs` | 1.1 (package.json pins) | plugin file (stdio protocol contract), warm.mjs | med |
| `plugins/laya-guard/warm.mjs` | 1.1, 1.2 | setup.sh provisioning step | low |
| `plugins/laya-guard/package.json` | — | npm install in `~/.cache/laya-guard`, sidecar/warm require resolution | low |
| `plugins/opencode-laya-guard.ts` | 1.2 (protocol), 3.1 (config) | opencode plugin loader (external), `deploy_plugins()` glob copy | med |
| `plugins/laya-guard/laya-guard.config.json` | — | plugin config loader (first-wins search), bats guard | low |
| `plugins/laya-guard/README.md` | all prior | users tuning/calibrating | low |
| `plugins/ATTRIBUTION.md` | 1.1 (dep identity) | license compliance readers | low |
| `.gitignore` | 2.5 (log path) | git | low |
| `deploy/opencode.json` | — | opencode config loader; deployed copy by setup.sh | low |
| `deploy/setup.sh` | 1.1–1.3 (provisions their artifacts) | bats suite (`test_plugin_activation`, `test_dry_run_leaks`, `test_err_trap_nounset`, `test_setup_shim`), end-user deploys | high |
| `deploy/setup.ps1` | 4.2 (parity) | `test_setup_ps1_vars.bats`, Windows users | low |
| `plugins/README.md` | 2.x (plugin exists) | plugin consumers | low |
| `tests/test_laya_guard.bats` | 2.x, 3.1, 4.1 | CI | low |
| `skills/requirements-inline-skill/SKILL.md` | 2.4 (tool exists) | skill loader (description triggers unchanged) | low |
| `skills/architecture-review-skill/SKILL.md` | 2.4 | skill loader | low |
| `skills/markitdown-mcp-skill/SKILL.md` | 2.4 | skill loader | low |

Cross-module note: `deploy/setup.sh` has consumers beyond itself (bats suite +
ps1 parity) — architecture review selected at Step 7 for this reason.

## Implementation Phases

_Every step is atomic and carries rationale. Format: N.M action — Why / Done when / Consumers affected._

### Phase 1: Sidecar runtime (`plugins/laya-guard/`)

- [x] **1.1** Create `plugins/laya-guard/package.json` pinning exact deps (`@receptron/laya` at the current published version, no ranges) with `private: true`
    — **Why:** the sidecar's npm deps must live outside the plugin load path (opencode plugin file stays zero-dep); exact pins make `npm install` reproducible without a committed lockfile.
    — **Done when:** file exists, `npm install --omit=dev --prefix <tmp>` resolves with no range warnings on a probe.
    — **Consumers affected:** sidecar.mjs, warm.mjs, setup.sh provisioning.
    — **Done:** pinned `@receptron/laya` exactly at 0.1.2 (current published; transitives onnxruntime-node ^1.22 + @huggingface/tokenizers flow); files: plugins/laya-guard/package.json; fixes: none
- [x] **1.2** Write `plugins/laya-guard/sidecar.mjs` — Node >=24 stdio-JSONL RPC: reads `{id, op:"systemOne", state, questions}` lines on stdin, responds `{id, ok:true, answers}` / `{id, ok:false, error}`; `op:"ping"` returns readiness; model loads lazily on first `systemOne` via `Laya.load({ revision: <pin>, executionProviders: ["cpu"] })` (modelDir override via `LAYA_GUARD_MODEL_DIR`); choice answers missing a `probabilities.yes` are reported as `p=1` by the CALLER, but the sidecar echoes raw answers and never fabricates values; process exits on stdin close
    — **Why:** this is the entire bridge between opencode's Bun runtime and Node-native ONNX inference; stdin-close exit gives "dies with opencode" for free (no daemon).
    — **Done when:** `echo '{"id":1,"op":"ping"}' | node sidecar.mjs` (deps installed) responds `{"id":1,"ok":true}` and exits 0 on stdin EOF.
    — **Consumers affected:** plugin file (protocol), warm.mjs (shares load options).
    — **Done:** sidecar implements ping/systemOne/unknown-op, lazy dedup'd model load (cpu EP, revision 68f27df, LAYA_GUARD_MODEL_DIR override), serialized inference queue, stdin-EOF exit; smoke: ping → `{"id":1,"ok":true,"pong":true,"model_loaded":false,"node":"24.21.0"}`, exit 0; files: plugins/laya-guard/sidecar.mjs; fixes: none
- [x] **1.3** Write `plugins/laya-guard/warm.mjs` — one-shot script: `Laya.load()` with the pinned revision + cpu provider, then `close()`; prints the cache dir on success
    — **Why:** model provisioning must reuse laya's own downloader (correct `BUNDLE_FILES` paths — hand-rolled curl lists drift, the source brief's file list was already wrong about `tokenizer/` subfolder); warm pre-pulls the ~1.7 GB so the first classify is not a cold start.
    — **Done when:** `node warm.mjs` completes and the laya cache marker files exist (run during provisioning only).
    — **Consumers affected:** setup.sh `--enable-pack laya`.
    — **Done:** warm.mjs written (same load options as sidecar, revision 68f27df); syntax-checked; the 1.7 GB pull itself is provisioning-time (Phase 4, --enable-pack laya) and a background verification pull was started — result logged at Phase 4; files: plugins/laya-guard/warm.mjs; fixes: none

### Phase 2: Plugin file (`plugins/opencode-laya-guard.ts`)

- [x] **2.1** Write the config loader — first-wins candidates: `<project>/laya-guard.config.json`, `<project>/.opencode/laya-guard.config.json`, `<configDir>/plugins/laya-guard/laya-guard.config.json` (shipped default), then built-in defaults; parse failure => defaults (fail-open to safe defaults, matching vibeguard's discovery semantics); no `process.env` reads anywhere in the file
    — **Why:** mirrors the vibeguard config contract users already know; shipped default rides the existing `deploy_plugins()` dir copy so no new deployment mechanism is needed.
    — **Done when:** candidates array in source matches the three paths; defaults object carries `mode:"shadow"`.
    — **Consumers affected:** hook (2.3), tool (2.4), logger (2.5).
    — **Done:** three candidates + DEFAULTS with mode shadow/enabled/timeout 60000; parse failure breaks to defaults; guard-verified zero process.env; files: plugins/opencode-laya-guard.ts; fixes: none
- [x] **2.2** Write the sidecar client — lazy spawn of `node <cache>/sidecar.mjs` on first use (never at setup), newline-delimited request/response with `id` correlation, `timeout_ms` race per request (default 60000 — cold model load dominates), `ping` health check before first real request, kill child in the setup cleanup return
    — **Why:** lazy spawn keeps opencode startup free for sessions that never classify; the cleanup return is the v2 lifecycle contract (registration disposed on unload).
    — **Done when:** a request to a non-existent sidecar binary resolves `ok:false` (typed failure), and the returned cleanup function terminates a spawned child in-process.
    — **Consumers affected:** hook (2.3), tool (2.4).
    — **Done:** ensureChild/request/ensureReady — id-correlated pending map, per-request timeout race, node>=24 check on ping, init op for model_dir, respawn-on-death, failAllPending + kill in cleanup; live systemOne vs warm cache returned calibrated answers (destructive p=0.94 on rm -rf, exfiltration p=0.21); files: plugins/opencode-laya-guard.ts + sidecar.mjs (init op); fixes: 1 (stdin-drain — see Trace)
- [x] **2.3** Register `ctx.permission.hook("evaluate", ...)` — gate on `cfg.actions` (default `["bash","edit"]`); compute destructive/exfiltration/injection p(yes) via sidecar `systemOne` (choice-type yes/no questions — never `noul`); shadow mode: log only, never touch `event.effect`; enforce: `deny`/`ask` thresholds from config mutate `event.effect` + `event.message`; missing answers => p=1 (fail-closed); sidecar failure => enforce sets `effect="ask"` with a human-review message, shadow logs the failure; hard-configured denies upstream never reach this hook (v2 semantics, verified)
    — **Why:** this is the brief's core gate, now on verified v2 API; choice-as-yes/no avoids the documented `noul` label-following quirk.
    — **Done when:** code path inspection shows: shadow branch has zero assignments to `event.effect`; enforce branch covers deny/ask/failure; `?? 1` fallback present.
    — **Consumers affected:** every bash/edit permission decision (posture depends on mode).
    — **Done:** shadow branch returns before any effect write; enforce covers deny/ask and failure->ask; ?? 1 present (grep-verified); statements truncated to 200 chars pre-classification; files: plugins/opencode-laya-guard.ts; fixes: none
- [x] **2.4** Register the `laya_classify` tool via `ctx.tool.transform` — JSON Schema args: `{ state: string (required), questions: array of {name, instructions} (1–8 items) }`; returns per-question `p_yes` + a confidence label; sidecar failure returns a typed error content block, never a fabricated number
    — **Why:** custom tool is the verified v2 mechanism for skill decision trees; the tool advises, the agent decides — no autonomous gating of skill logic.
    — **Done when:** `ctx.tool.list()` in a loaded session exposes the tool; args schema validates (additionalProperties false).
    — **Consumers affected:** the three wired skills (Phase 6), interactive users.
    — **Done:** tool registered via ctx.tool.transform, JSON Schema (additionalProperties false both levels, 1–8 questions), per-question p_yes JSON or typed error content; live ctx.tool.list() check deferred to runbook smoke; files: plugins/opencode-laya-guard.ts; fixes: none
- [x] **2.5** Write the shadow logger — append-only JSONL to `<project>/.opencode/laya-guard-shadow.jsonl`: `{ts, action, target, questions:{name:p}, would_be, mode}`; target = action metadata only (resources array, truncated to 200 chars), never file contents or env values; every append wrapped in try/catch (logging must never break the agent loop)
    — **Why:** shadow calibration (Week 1–2) is the enforce-flip prerequisite; metadata-only keeps vibeguard exposure at zero; truncation bounds the one residual leak path (a bash command carrying an inline credential) — local gitignored log, not a new surface, but cheap to bound.
    — **Done when:** no code path writes message bodies, diffs, or env values to the log; target truncation present in source; append failure is swallowed.
    — **Consumers affected:** calibration workflow; `.gitignore` (3.4).
    — **Done:** logShadow writes ts/action/target(200-cap)/questions/would_be/mode(+capped failure detail); mkdir recursive + append inside try/catch; files: plugins/opencode-laya-guard.ts; fixes: none


### Phase 3: Config + docs

- [x] **3.1** Write `plugins/laya-guard/laya-guard.config.json` — `{"mode":"shadow","deny":0.8,"ask":0.3,"actions":["bash","edit"],"timeout_ms":60000,"shadow_log":".opencode/laya-guard-shadow.jsonl"}`
    — **Why:** thresholds live in config, never the model (locked decision); shadow ships default (locked decision).
    — **Done when:** file parses, `mode` is `shadow`.
    — **Consumers affected:** 2.1 loader, bats guard.
    — **Done:** shipped defaults written (shadow/0.8/0.3/bash+edit/60000/log path); JSON parses; "mode": "shadow" grep-verified; files: plugins/laya-guard/laya-guard.config.json; fixes: none
- [x] **3.2** Write `plugins/laya-guard/README.md` — what it gates, sidecar architecture one-paragraph, config reference, shadow->enforce calibration procedure (log inspection, false-deny≈0 target), `--enable-pack laya` provisioning, air-gap pre-seed via `LAYA_GUARD_MODEL_DIR`
    — **Why:** AC requires usage + calibration docs; the enforce flip must be a documented decision, not a default.
    — **Done when:** README covers all six topics.
    — **Consumers affected:** users.
    — **Done:** README covers architecture diagram, gating table, deploy incl. --enable-pack laya + LAYA_GUARD_SKIP, config reference, calibration (false-deny≈0), air-gap, metadata-only note; files: plugins/laya-guard/README.md; fixes: none
- [x] **3.3** Append ATTRIBUTION entries — `@receptron/laya` (MIT, receptron/laya) and Laya model weights (Apache-2.0, Convai Innovations, `convaiinnovations/laya`); note the sidecar vendoring posture (no plugin code vendored; deps installed at provision time)
    — **Why:** the original brief's "self-authored, no third-party" claim was wrong — the plugin consumes MIT code + Apache-2.0 weights.
    — **Done when:** both entries present with license + upstream links.
    — **Consumers affected:** license compliance readers.
    — **Done:** laya-guard section appended — @receptron/laya MIT (pinned, provision-time), Convai weights Apache-2.0 (revision 68f27df), runtime natives credited; vendoring posture stated; files: plugins/ATTRIBUTION.md; fixes: none
- [x] **3.4** Append `.opencode/laya-guard-shadow.jsonl` to `.gitignore`
    — **Why:** per-project runtime log must never commit.
    — **Done when:** `git check-ignore .opencode/laya-guard-shadow.jsonl` exits 0.
    — **Consumers affected:** git.
    — **Done:** .opencode/laya-guard-shadow.jsonl ignored (check-ignore exit 0); files: .gitignore; fixes: none

### Phase 4: Deploy wiring

- [x] **4.1** Edit `deploy/opencode.json` — insert 3 bash deny rules immediately after the existing read-denies and before the skill entries: `git push --force*`, `rm -rf /*`, `curl * | sh`
    — **Why:** configured deny is final and never invokes the hook (verified v2 semantics) — certainties belong in config, gray zone in Laya (brief §3.3).
    — **Done when:** JSON parses (node -e), three rules present above the first `"action": "skill"` entry.
    — **Consumers affected:** every session using the deployed config.
    — **Done:** 3 bash deny rules (git push --force*, rm -rf /*, curl * | sh) inserted after the read rules, before the first skill entry; JSON parses; files: deploy/opencode.json; fixes: none
- [x] **4.2** Add `provision_laya_guard()` to `deploy/setup.sh` + call it from `setup_config()` next to `install_docling` — Linux-gated (non-Linux: one-line skip note); idempotent via `~/.cache/laya-guard/.provisioned` marker + version check against the committed package.json; copies `sidecar.mjs`, `warm.mjs`, `package.json` to `~/.cache/laya-guard/` and runs `npm install --omit=dev` there (sidecar deps: always, small); model pre-pull (`node warm.mjs`) only when `--enable-pack laya` requested (heavy-install house policy, mirrors markitdown/docling); `run_cmd`-wrapped for dry-run safety; no unquoted expansions (`set -u` safe); honors `LAYA_GUARD_SKIP=1` escape
    — **Why:** sidecar deps must exist for the plugin to function; heavy model download follows the repo's documented opt-in rule (`never on a plain deploy`) while remaining fully provisioned via setup.sh when requested — this reconciles AC-5 with house policy.
    — **Done when:** `bash -n setup.sh` passes; full bats suite green (dry-run leak guard, err/nounset guard included); second consecutive provision run is a no-op.
    — **Consumers affected:** bats suite, setup.ps1 parity, end-user deploys.
    — **Done:** provision_laya_guard() defined after install_docling (LAYA_GUARD_SKIP escape, uname Linux gate, node>=24 + npm checks, sha-marked idempotency, run_cmd/DRY-RUN-safe, --enable-pack laya model pre-pull) + call site in setup_config() beside install_docling; bash -n green; files: deploy/setup.sh; fixes: none
- [x] **4.3** Mirror the skip in `deploy/setup.ps1` — Windows provision block prints the laya-guard skip notice (plugin file deploys but stays inert without `~/.cache/laya-guard`)
    — **Why:** ps1 is the documented Windows mirror; the plugin is Ubuntu-locked by design (locked decision 2).
    — **Done when:** ps1 syntax-valid and prints the notice in its config phase; `test_setup_ps1_vars.bats` still green.
    — **Consumers affected:** Windows users (informed), ps1 tests.
    — **Done:** no ps1 edit required — setup.ps1 is the #474 thin launcher forwarding everything (incl. --enable-pack, line 123) to setup.sh, whose uname gate prints the skip notice; duplicating logic would violate the one-implementation contract; ps1 tests green in full suite; files: none (verified); fixes: none
- [x] **4.4** Update `plugins/README.md` — add the plugin row to the naming-convention table context and a short section noting the laya-guard subdirectory travels with the plugin file through `deploy_plugins()`'s dir copy
    — **Why:** plugins/README is the plugin-consumer doc; silent new files drift it.
    — **Done when:** README references `opencode-laya-guard.ts` and the subdirectory.
    — **Consumers affected:** plugin consumers.
    — **Done:** plugins/README.md gained the laya-guard section (dir travels via deploy_plugins copy, provisioning pointer); root README synced — Six→Seven, details summary, tree comment, laya-guard paragraph before the Attribution footer; files: plugins/README.md README.md; fixes: none

### Phase 5: Tests

- [x] **5.1** Write `tests/test_laya_guard.bats` — grep-based guards (CI-safe, no ripgrep per repo learning): no `https?://` in the plugin file (air-gap); `?? 1` present (fail-closed); `"mode": "shadow"` in shipped config; config file exists; no `process.env` in the plugin file (no content/env leak surface); no `readFileSync` in `sidecar.mjs` (sidecar never reads files); `git push --force` deny present in `deploy/opencode.json`
    — **Why:** the invariants are structural and grep-checkable; these four are the brief's air-gap + fail-closed + shadow-default + no-leak ACs made mechanical.
    — **Done when:** `bats tests/test_laya_guard.bats` all green.
    — **Consumers affected:** CI.
    — **Done:** 8 guards (air-gap, fail-closed ?? 1, shadow default, config exists, no process.env, sidecar no readFileSync, push --force deny shipped, enforce-not-default); 8/8 green; grep-based + cwd-independent per repo learnings; files: tests/test_laya_guard.bats; fixes: none
- [x] **5.2** Run the full bats suite (`bats tests/`) — whole-repo green
    — **Why:** setup.sh and opencode.json edits have existing guard tests; the ticket must not regress them.
    — **Done when:** zero failing files, noted in the gate memo.
    — **Consumers affected:** CI, maintainers.
    — **Done:** full bats suite 670 ok / 0 failures (662 pre-existing + 8 new); files: (run); fixes: none

### Phase 6: Skill wiring (optional-consult lines, body-only edits — frontmatter untouched)

- [ ] **6.1** `skills/requirements-inline-skill/SKILL.md` — one line in the Detection decision tree: when a branch hinges on judgment (thin-vs-substantive, ambiguity calls), optionally consult `laya_classify` with the statement; deterministic checks stay in code
    — **Why:** the skill's routing has genuinely fuzzy branches; the tool advises, the agent decides (locked decision: no autoresearch-evaluator use).
    — **Done when:** line present in the decision tree section; frontmatter byte-identical.
    — **Consumers affected:** requirements gate runs.
- [ ] **6.2** `skills/architecture-review-skill/SKILL.md` — same consult line in `## §2. Decision Tree` for target-routing ambiguity
    — **Why:** target routing (which review axis applies) is judgment-shaped at the edges.
    — **Done when:** line present; frontmatter byte-identical.
    — **Consumers affected:** plan reviews.
- [ ] **6.3** `skills/markitdown-mcp-skill/SKILL.md` — same consult line in `## Decision Tree` for layout-complexity ambiguity (markitdown vs docling escalation)
    — **Why:** extraction-tier routing is the documented fuzzy branch.
    — **Done when:** line present; frontmatter byte-identical.
    — **Consumers affected:** document-extraction routing.

### Phase 7: Exit gate + runbook

- [ ] **7.1** Run the full verification gate (tier=full) and write the gate memo into the PLAN `## Trace` — includes: bats full suite, `bash -n` on setup.sh, JSON parse of opencode.json + config, plugin file syntax check (tsc-free: node --check on the transpiled form is not available; structural greps per 5.1 stand in), manual smoke path documented (scratch project, `echo hello` shadow pass line, `git push --force` config-denied, ambiguous curl logged high-exfiltration)
    — **Why:** ticket exit gate is full tier per the pipeline contract; the memo's `GATE <sha> tier=full` line is the PR-creation citation.
    — **Done when:** memo line present naming the final implementation SHA.
    — **Consumers affected:** Step 9 review, Step 10a PR body.

## Technical Notes

- **opencode v2 API (verified this session):** `Plugin` default export `{ id, setup }` shape per the vibeguard-v2 house pattern (no `@opencode/plugin` runtime import — keeps the plugin file zero-dep); `ctx.permission.hook("evaluate")` with mutable `effect`/`message` (run for allow/ask; configured deny final); `ctx.tool.transform(editor => editor.add({ name, description, input: <JSON Schema>, execute }))`; cleanup function returned from `setup`; `ctx.location.directory` for project scoping.
- **Brief corrections carried:** model org is `convaiinnovations` (not `Convai-Lab`); bundle paths via laya's own downloader (tokenizer lives in a subfolder; the brief's curl list was wrong); attribution is NOT self-authored; `timeout_ms` is implemented (brief declared it dead); V1's `.opencode/package.json` dep mechanism dropped entirely (sidecar owns deps).
- **Model bundle:** never committed; `~/.cache/receptron-laya` (laya-managed) or `LAYA_GUARD_MODEL_DIR` override; revision pinned to `68f27df` in sidecar + warm + setup check.
- **Node version:** sidecar requires Node >=24 (user runtime: nvm v24.21.0); provisioning checks `node --version` major and refuses with a clear message below 24 (onnxruntime-node official support).
- **Deterministic branches stay deterministic:** the three wired skills get consult-on-ambiguity lines only; no decision tree becomes model-dependent.

## Dependencies

None — no `blocked-by` tickets. External: Hugging Face network access once (provisioning/warm); everything after runs offline.

## Risks & Mitigation

| Risk | Mitigation |
|------|------------|
| Bun (opencode plugin host) sidecar-spawn incompatibility | sidecar is plain `child_process.spawn("node", ...)` — stdio IPC is runtime-agnostic; smoke test in runbook catches it before enforce mode |
| Base checkpoints score near chance on public typed-decision benchmarks | shadow-only default; calibration gate (false-deny≈0) before any enforce flip; fail-closed means misclassification degrades to `ask`, never silent `allow` |
| 1.7 GB surprise download | model pull is `--enable-pack laya` opt-in; deps-only default is tens of MB; `LAYA_GUARD_SKIP=1` escape hatch |
| setup.sh regression (heavily tested script) | additive function + single call site; full bats suite in 5.2; dry-run leak and nounset guards named explicitly |
| laya API drift (young package, 16 commits) | exact version pin in package.json; sidecar isolates the API surface to one file |
| Model-load memory (~2 GB resident) | lazy load in sidecar on first classify; `close()` on plugin cleanup; documented in README |

## Trace

- GATE cd7a32c tier=light lint=n.a typecheck=n.a build=n.a unit=t (sidecar ping round-trip on Node 24.21.0, deps resolve from sidecar-local node_modules, node --check x2) e2e=n.a
- LOG fix 1 (2.2, sidecar.mjs): stdin-close killed an in-flight model load — close now drains (inFlight counter + maybeExit); caught by Phase 2 verification smoke (init responded, systemOne never did); re-smoked green
- LOG warm pull verified live: node warm.mjs -> "laya model ready" (~/.cache/receptron-laya, revision 68f27df); live systemOne through sidecar: destructive p=0.9437 / exfiltration p=0.2063 on rm -rf node_modules — model path proven end-to-end on this host
- GATE b21531c tier=light lint=n.a typecheck=n.a build=n.a unit=t (air-gap / fail-closed / no-env / no-fs-reads greps green; node strip-types parse OK; live sidecar systemOne smoke green incl. init op + drain-exit) e2e=n.a
- GATE 36ad759 tier=light lint=n.a typecheck=n.a build=n.a unit=t (config JSON parse, shadow-default grep, check-ignore exit 0) e2e=n.a
- LOG full-gate escalation (Phase 4): deploy/setup.sh + deploy/opencode.json touched — critical-area anchor per the Consumer Map (bats suite + ps1 parity consumers); gate tier=full
- LOG fix 2 (Phase 4, tests/test_select_items.bats): #537 plugin-inventory pins hardcoded 6 .ts plugins; the 7th (opencode-laya-guard.ts) is a legitimate inventory change — pins updated to 7 (expected length, select-items count, list-items 7/7) with #671 comments; full suite otherwise green (660/662 before, inventory tests 19/19 after)
- GATE 956f7dc tier=full lint=n.a typecheck=n.a (node --check sidecar.mjs/warm.mjs; node strip-types parse on the plugin .ts) build=n.a unit=t (bats tests/ 662/662 post-pin-fix; bash -n setup.sh; opencode.json + config JSON parse) e2e=n.a (no frontend touched)
