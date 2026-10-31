# PLAN: Consolidate office-document skills into one router skill

**Branch**: feat/680
**Issue**: https://github.com/darellchua2/civiltekk-skills/issues/680
**Base**: main

## Acceptance Criteria

- [ ] Generalizer detector pass (1–8) documented; merge/sibling boundary recorded
- [ ] Router skill ships: SKILL.md ≤10KB (~2.5k tokens), decision tree, spine, load table, gates in router; description ≤50 words, triggers preserved
- [ ] pptx vendored `scripts/_common` constraint resolved (single tree; guard updated or retired)
- [ ] markitdown/docling routes follow civiltekk-install-assistant conventions (dry-run + consent, never auto-install)
- [ ] Replaced skills hard-removed; orphan-reference grep clean (historical PLANS excepted)
- [ ] Consumers rewired: subagent permission allowlists, presets, `README.md`, `deploy/setup.sh` + `setup.ps1`, registry regenerated
- [ ] Full bats suite passes
- [ ] Generalizer output contract deliverables: weight line, change list, residual list

## Dependency & Consumer Map

| Node (file/module) | Depends on (must precede) | Consumers (who depends on this) | Change risk |
|---------------------|---------------------------|---------------------------------|-------------|
| `skills/office-document-router-skill/` (new) | Phase 1 audit | 9 subagents' allowlists, presets, registry, npx users | med |
| 9 subagent frontmatters (office-document-router, docx-creation, xlsx-specialist, pptx-specialist, documentation, discovery, requirements-specialist, startup-founder, technical-design-specialist) | router exists | OpenCode runtime, registry build, requiresSkills derivation | med |
| `deploy/skill-profiles.json` lean array (docling, markitdown, pdf entries) | router named + old IDs final | README primary-visible count literal; count-drift tests | med |
| `installer/dependency-map.json` (impliesMcp markitdown/docling; requiresSkills HANDOFF1 pptx pair) | removal set final | installer/init.mjs | med |
| `tests/test_skill_isolation.bats` rule 4 (pptx _common byte-identity) + HANDOFF1 blocks (`test_requires_skills.bats`, isolation HANDOFF vars) | single _common tree landed; HANDOFF1 pair retired | repo governance, CI | med |
| 11 old skill dirs (delete) | ALL consumer rewires landed (Phase 3) | registry build, counts, README, AGENTS.md routing section | high |
| `AGENTS.md` Office Document Extraction Routing section | router exists | docs readers | low |
| 7 surviving skills referencing office IDs (civiltekk-diagram, civiltekk-requirements-specs ×3 files, civiltekk-startup-docs, horseshoe-paper-writing, research-paper-generation, technical-design-creation, vision-creation) + `THIRD_PARTY_LICENSES.md:251` | router exists | users of those skills/docs; Phase 4 deletion must not orphan them | med |
| `installer/init.mjs:2040` help example + `tests/test_help_parity.bats:43` assertion | router named | installer help parity | low |
| `installer/registry.json` | all frontmatter final; producer `installer/build-registry.mjs` run per roster change (not edited by hand) | installer/init.mjs, npx installer | med |
| `README.md`, `deploy/setup.sh`, `deploy/setup.ps1` | final roster post-deletion | deploy users, docs readers | low |

Phase ordering constraint: no deletion (4.1) before every consumer is rewired (Phase 3); registry regeneration rides every roster-affecting commit (project anti-pattern: skill-moves-are-roster-changes).

## Audit Notes (Phase 1 — detector pass, 2026-10-31)

### Boundary (step 1.2)

**All 11 merge — zero siblings.** Every member is text + house-authored scripts; no vendored third-party apps (the Wave-1 sibling trigger never fires). The pptx trio merges with ONE `scripts/_common` tree (byte-identical verified: tree-hash 655335a4 ×3). `interactive-document-rendering-skill` is in-family: it is the shared HTML/DOCX output standard consumed by vision-creation + civiltekk-requirements-specs (both rewired in 3.5). Flat `scripts/` layout for the trio: every `SKILL_DIR`-relative sys.path snippet survives; the modifier's `SLIDE_SKILL_DIR` cross-skill mechanism collapses to `$SKILL_DIR/scripts` (same dir now) and its "only handoff in this catalog" note retires with HANDOFF1.

Routes: `docx`, `xlsx`, `pdf`, `slides` (pptx-generate-slide), `template` (pptx-generate-template), `modifier` (pptx-template-modifier), `markitdown`, `docling`, `ooxml`, `thumbnails`, `rendering` (interactive-document-rendering).

### Consumer list (step 1.2, complete — repo-wide all-filetype grep)

9 subagents (office-document-router, docx-creation, xlsx-specialist, pptx-specialist, documentation, discovery, requirements-specialist, startup-founder, technical-design-specialist) · `deploy/skill-profiles.json` lean (docling, markitdown, pdf) · `installer/dependency-map.json` (impliesMcp ×2; HANDOFF1 requiresSkills) · `installer/init.mjs:2040` help example + `tests/test_help_parity.bats:43` assertion · `tests/test_skill_isolation.bats` (rule 4 + HANDOFF vars, positional args) + `tests/test_requires_skills.bats` (HANDOFF1 blocks) · `installer/presets/pack-business.json` + `pack-docs.json` · `AGENTS.md` routing section · `README.md` (counts incl. Configuration category + primary-visible) · `THIRD_PARTY_LICENSES.md:251` · 7 surviving skills (civiltekk-diagram; civiltekk-requirements-specs SKILL.md+brd.md+srs.md; civiltekk-startup-docs pitch-deck.md; horseshoe-paper-writing; research-paper-generation; technical-design-creation; vision-creation — the last two via `interactive-document-rendering-skill` name references) · registry (regen). Verified NON-consumers: `deploy/packs/*.json` (MCP-only), `deploy/opencode.json` (MCP server infra), `test_pack_permissions.bats` (MCP infra), `docs/opencode-agent-tooling-research-2026-09-24.md` (dated history — justified residual).

### Named-entity dispositions (step 1.1)

- **Reword (origin artifacts, 2):** docx "tracked-change/comment author = **'Claude'**" → "the agent's display identity"; docling "follow the AGENTS.md → Office Document Extraction Routing rule" → "follow the router's extraction ladder" (ownership inverts — the router spine now owns the ladder the AGENTS.md section informally carried).
- **Reword (cross-skill mechanics, 3):** pptx-modifier's `SLIDE_SKILL_DIR` sibling default + `npx add pptx-generate-slide-skill` handoff note → single-skill wording; pptx-template's `SKILL_DIR` export example path → router path; pptx-slide/template/modifier "Peer skills" lines → route names.
- **Keep (attribution/provenance):** #262/#370/#487/#437/#47/BT-142/US-x/MAJOR-2 issue refs; "Removed 2026-09" trailers; PLAN-GIT-56 provenance line (marked historical); upstream links (microsoft/markitdown, docling PyPI).
- **Keep (domain vocabulary/standards):** tool names (pandoc, docx-js, LibreOffice, openpyxl, pandas, python-pptx, pypdf, qpdf, poppler, pytesseract, pdfplumber, reportlab, defusedxml, pptxgenjs, playwright, sharp), WCAG 2.1 / ECMA-376 / IEEE 830, DXA numbers, financial color codes, density budgets, version pins.

### Constants audit

All kept: DXA page geometry (universal), WCAG thresholds (standard), pptx density budgets + form-fill coordinate rules (protocol contracts), markitdown `>=0.1.1,<0.2.0` / docling `>=2.0,<3.0` pins (trust-boundary contracts). No case-local numbers found.

### Cross-reference resolution (pass 8)

- The extraction ladder (AGENTS.md informal table + markitdown decision tree + docling tiers) unifies in the ROUTER SPINE; route files keep specifics and point back. markitdown/docling keep their consent-gated `--enable-pack` / CLI-on-demand enablement (AC: install-assistant conventions — never auto-install; impliesMcp auto-enable edges removed in 3.2 for on-demand parity).
- Shared scripts: `soffice.py` appears in docx/pdf/thumbnail trees (+ xlsx prose reference) — dedupe to ONE copy at router `scripts/` (byte-check first; keep the superset).
- Shared spine candidates promoted once: design-aesthetics "no generic AI slop" principle (docx+xlsx both carry it); extraction ladder; MCP opt-in enablement pattern.

### Category note

Family categories were Framework / Presentation / Configuration / Office Utilities. Router ships as `Office & Documents`; Configuration count drops by 2 (markitdown, docling leave) — README Configuration literal + configuration-category test re-verified in 4.3 (the test reads both sides dynamically).

## Implementation Phases

### Phase 1: Generalizer audit (detector pass + boundary)

- [x] **1.1** Run named-entity, anecdote→rule, constants, and contradiction detectors over the 11 SKILL.mds; record every proper noun / anecdote / magic number with its disposition in a new `## Audit Notes` section of this PLAN
    — **Why:** the detector pass drives route-file content and catches cross-skill references before the merge
    — **Done when:** zero un-dispositioned named entities remain; notes list findings + dispositions
    — **Consumers affected:** Phase 2 route files
    — **Done:** all 11 files read in full; 5 disposition classes recorded (2 origin rewords, 3 mechanics rewords, provenance keeps, vocabulary keeps, constants all-keep); files: PLANS/PLAN-680.md; fixes: none
- [x] **1.2** Confirm the merge/sibling boundary per the sizing rule; decide `interactive-document-rendering-skill` (in-family or out) and whether the pptx trio merges with a single `_common` tree; map every consumer hit from the repo-wide ID grep into the Phase 3 rewire list
    — **Why:** the Phase 4 deletion list and Phase 3 rewire list must be exact before building
    — **Done when:** audit notes name the final merge set with the rule outcome each, plus the complete consumer list (subagents, presets, profiles, guards, AGENTS.md, README)
    — **Consumers affected:** Phases 2–4
    — **Done:** all-11-merge boundary recorded (no siblings — no vendored apps); interactive = in-family rendering route; consumer list complete incl. 7 surviving skills, THIRD_PARTY_LICENSES, init.mjs example + parity test; verified non-consumers recorded; files: PLANS/PLAN-680.md; fixes: none

### Phase 2: Build skills/office-document-router-skill/

- [ ] **2.1** Write `skills/office-document-router-skill/SKILL.md` router: frontmatter (name matching dir, description ≤50 words carrying the family triggers — DOCX, XLSX, PPTX, PDF, OOXML, document extraction, thumbnails, markitdown, docling —, license, compatibility, metadata, category), identity, decision tree (document task → route), shared document spine, load table, hard rules, gates
    — **Why:** the router is the contract every consumer and route file hangs off
    — **Done when:** file exists; `wc -c` ≤ 10240; description ≤50 words; all 11 routes represented; no preload instructions
    — **Consumers affected:** subagents (Phase 3), registry (4.2), end users
- [ ] **2.2** Create `references/routes/<id>.md` for each merged route via `git mv` of each SKILL.md + transform (strip frontmatter → WHEN+WHAT header, self-references → `<id>/` paths, cross-skill references → route/sibling wording); absorb reference dirs and scripts trees beside their route files; pptx trio's `scripts/_common` unified to ONE tree at the skill root `scripts/_common`
    — **Why:** route files carry merged mechanics behind load rules; the single `_common` retires the drift guard by construction
    — **Done when:** 11 route files with headers; every `<id>/…` target exists; zero old-ID path strings in .py or fenced blocks; `_common` exists exactly once
    — **Consumers affected:** router load table (2.1)
- [ ] **2.3** Preserve provenance: LICENSE files carried to the skill root or route dirs; merged `requirements.txt` when present (dependency-conflict audit); AST syntax check over absorbed scripts
    — **Why:** licenses and working scripts must survive the merge unmodified
    — **Done when:** every old LICENSE text present verbatim; scripts parse clean (`ast.parse`); no conflicting pins
    — **Consumers affected:** compliance readers, script runtime

### Phase 3: Rewire consumers (before any deletion)

- [ ] **3.1** Rewire the 9 subagent frontmatters: office-skill allow rules → single `office-document-router-skill` allow; routing tables point at router routes; prose references → route names
    — **Why:** agents must not allow or reference skills Phase 4 removes; allow rules feed requiresSkills derivation
    — **Done when:** grep of agents/ finds zero references to removed IDs outside install-if-missing/MCP-context mentions
    — **Consumers affected:** OpenCode runtime, registry (4.2)
- [ ] **3.2** Update `deploy/skill-profiles.json` lean array (docling/markitdown/pdf entries → `office-document-router-skill`), `installer/presets/pack-business.json` + `pack-docs.json` rosters, and `installer/dependency-map.json` (remove impliesMcp markitdown/docling entries — on-demand MCP enablement moves into the routes per install-assistant conventions; remove the HANDOFF1 requiresSkills pptx pair)
    — **Why:** installer surfaces must match the post-merge installable set or presets/edges dangle
    — **Done when:** JSON parses; zero removed IDs in the three files; dependency-map comment updated; `installer/init.mjs:2040` example + `tests/test_help_parity.bats:43` assertion updated to the router in the same commit
    — **Consumers affected:** installer users, init.mjs
- [ ] **3.3** Update the guard tests: retire the pptx `_common` byte-identity rule (test_skill_isolation.bats rule 4 block) and the HANDOFF1 pair (isolation test vars + test_requires_skills.bats HANDOFF1 assertions) — retired BY CONSTRUCTION (single tree, no handoff left)
    — **Why:** guards enforcing the pre-merge topology would fail on the correct post-merge tree
    — **Done when:** bats skill_isolation + requires_skills tests pass on the merged tree; `test_help_parity.bats` and `test_pack_permissions.bats` verified: the former updated per 3.2, the latter is MCP-infra-only and untouched
    — **Consumers affected:** repo governance, CI
- [ ] **3.4** Repoint `AGENTS.md` Office Document Extraction Routing section at the router routes; update README count literals (incl. primary-visible) IN THE SAME COMMITS as roster changes per project anti-pattern; regenerate `installer/registry.json`
    — **Why:** docs routing and generated artifacts must track the tree
    — **Done when:** AGENTS.md section references router routes; count literals equal disk; registry contains the router, zero removed IDs
    — **Consumers affected:** docs readers, installer

- [ ] **3.5** Rewire surviving-sibling references (arch-review finding, #679 class): `skills/civiltekk-diagram-skill/SKILL.md`, `skills/civiltekk-requirements-specs-skill/` (SKILL.md + references/brd.md + references/srs.md), `skills/civiltekk-startup-docs-skill/references/pitch-deck.md`, `skills/horseshoe-paper-writing-skill/SKILL.md`, `skills/research-paper-generation-skill/SKILL.md`, `skills/technical-design-creation-skill/SKILL.md`, `skills/vision-creation-skill/SKILL.md`, and `THIRD_PARTY_LICENSES.md:251` — repoint at `office-document-router-skill` and its matching route
    — **Why:** all referenced skills are deleted in 4.1; unrewired references dangle at first use
    — **Done when:** grep of the surviving tree (excluding PLANS history and the deleted dirs) finds zero references to the 11 removed IDs
    — **Consumers affected:** users of those skills/docs; 4.3 orphan grep

### Phase 4: Delete, final regen, recount

- [ ] **4.1** `git rm -r` the 11 replaced skill dirs
    — **Why:** hard removal per AC; strictly after Phase 3
    — **Done when:** dirs gone; only intended deletions staged
    — **Consumers affected:** registry (4.2), counts (4.3)
- [ ] **4.2** Final `node installer/build-registry.mjs`; commit regenerated registry
    — **Why:** generated artifact tracks the tree
    — **Done when:** registry has the router + zero removed IDs; diff reviewed
    — **Consumers affected:** installer/init.mjs, npx installer
- [ ] **4.3** Final count sweep: README + deploy scripts counts equal `ls skills/ | wc -l`; case-insensitive orphan grep for the 11 removed IDs (historical PLANS excepted)
    — **Why:** count drift and dangling references are the documented failure modes
    — **Done when:** greps clean; counts match disk; `docs/opencode-agent-tooling-research-2026-09-24.md` residual justified as dated history
    — **Consumers affected:** deploy users, docs readers

### Phase 5: Verify + deliverables (ticket exit gate — full)

- [ ] **5.1** Full bats suite green on the final tree
    — **Why:** isolation + governance enforcement
    — **Done when:** exit 0, zero `not ok`
    — **Consumers affected:** repo governance, CI
- [ ] **5.2** Generalizer verification on the router: ≤10240 bytes, ≤50-word description, load-table rows resolve, route cross-refs resolve, no preload rules, no old-ID path strings
    — **Why:** router-pattern correctness conditions
    — **Done when:** all checks pass with recorded measurements
    — **Consumers affected:** skill consumers
- [ ] **5.3** Record deliverables in the PLAN trace: weight line before→after, change list, residual list
    — **Why:** ticket AC requires reviewable contract deliverables
    — **Done when:** three deliverable blocks present with final numbers
    — **Consumers affected:** reviewers, ticket close
- [ ] **5.4** Run the full exit gate and write the `tier=full` memo for the final implementation SHA into the PLAN `## Trace

LOG phase-1: docs-only phase (PLAN audit notes); no source files touched.
GATE (phase-1 tree) tier=light lint=n.a typecheck=n.a build=- unit=n.a e2e=n.a
`
    — **Why:** PR step cites the memo for the pushed SHA
    — **Done when:** memo line present matching the final pushed SHA
    — **Consumers affected:** PR creation (Step 10a)

## Technical Notes

- markitdown/docling become ROUTES whose install-if-absent instruction is the MCP pack (`--enable-pack markitdown` / docling via mcp-install-assistant, consent-gated) — the impliesMcp auto-enable edges are removed so installing the router does not silently enable MCP servers (on-demand parity with Wave 1's sibling contract).
- The pptx trio merges with one `scripts/_common` tree at the router root; per-format scripts stay in per-route subdirs; the byte-identity guard retires by construction.
- deploy/opencode.json MCP server definitions (markitdown, docling) are infrastructure — unchanged; only the skill→MCP edges move.
- Router routes load one-at-a-time; extraction-tier guidance (markitdown → docling escalation) lives in the router spine, replacing the AGENTS.md informal table.

## Dependencies

- Wave 1 (#679) merged (satisfied — main carries cad-specialist-skill).

## Risks & Mitigation

| Risk | Mitigation |
|------|------------|
| 9 subagent rewrites drift | scripted exact-anchor swaps + grep gates per step |
| lean-array length change breaks README primary-visible literal | 3.4 updates both in the same commit; count-drift tests verify |
| guard retirement leaves stale HANDOFF vars referenced elsewhere | 3.3 greps tests/ for HANDOFF1 before finishing |
| pptx scripts assume old relative layout | 2.2 rewrite + AST check + 5.2 sweep |
| registry/README counts drift mid-phase | regen + literals ride every roster-affecting commit (Wave 1 lesson) |

## Trace

(appended at execution: phase commits, gate memos, deliverables)
