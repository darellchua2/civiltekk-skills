# PLAN: Consolidate office-document skills into one router skill

**Branch**: feat/680
**Issue**: https://github.com/darellchua2/civiltekk-skills/issues/680
**Base**: main

## Acceptance Criteria

- [x] Generalizer detector pass (1–8) documented; merge/sibling boundary recorded
- [x] Router skill ships: SKILL.md ≤10KB (~2.5k tokens), decision tree, spine, load table, gates in router; description ≤50 words, triggers preserved
- [x] pptx vendored `scripts/_common` constraint resolved (single tree; guard updated or retired)
- [x] markitdown/docling routes follow civiltekk-install-assistant conventions (dry-run + consent, never auto-install)
- [x] Replaced skills hard-removed; orphan-reference grep clean (historical PLANS excepted)
- [x] Consumers rewired: subagent permission allowlists, presets, `README.md`, `deploy/setup.sh` + `setup.ps1`, registry regenerated
- [x] Full bats suite passes
- [x] Generalizer output contract deliverables: weight line, change list, residual list

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

- [x] **2.1** Write `skills/office-document-router-skill/SKILL.md` router: frontmatter (name matching dir, description ≤50 words carrying the family triggers — DOCX, XLSX, PPTX, PDF, OOXML, document extraction, thumbnails, markitdown, docling —, license, compatibility, metadata, category), identity, decision tree (document task → route), shared document spine, load table, hard rules, gates
    — **Why:** the router is the contract every consumer and route file hangs off
    — **Done when:** file exists; `wc -c` ≤ 10240; description ≤50 words; all 11 routes represented; no preload instructions
    — **Consumers affected:** subagents (Phase 3), registry (4.2), end users
    — **Done:** router written — 4851 bytes, description 42 words, 11 route rows + extraction-ladder spine + consent-gated MCP rule; files: skills/office-document-router-skill/SKILL.md; fixes: none
- [x] **2.2** Create `references/routes/<id>.md` for each merged route via `git mv` of each SKILL.md + transform (strip frontmatter → WHEN+WHAT header, self-references → `<id>/` paths, cross-skill references → route/sibling wording); absorb reference dirs and scripts trees beside their route files; pptx trio's `scripts/_common` unified to ONE tree at the skill root `scripts/_common`
    — **Why:** route files carry merged mechanics behind load rules; the single `_common` retires the drift guard by construction
    — **Done when:** 11 route files with headers; every `<id>/…` target exists; zero old-ID path strings in .py or fenced blocks; `_common` exists exactly once
    — **Consumers affected:** router load table (2.1)
    — **Done:** 11 route files via git mv + transform (headers, script paths per-format, cross-route names, SKILL_DIR examples, modifier single-skill mechanics incl. SLIDE_SKILL_DIR retirement, docx author-artifact reword, docling ladder inversion, 8 stale comment mentions); _common ×3→1; slide tests merged with unified conftest; template/ assets moved; pre-existing template_reader.py doc drift corrected; files: references/routes/*, scripts/*, template/; fixes: transform order bug (swaps before anchors) caught by residual grep and re-applied
- [x] **2.3** Preserve provenance: LICENSE files carried to the skill root or route dirs; merged `requirements.txt` when present (dependency-conflict audit); AST syntax check over absorbed scripts
    — **Why:** licenses and working scripts must survive the merge unmodified
    — **Done when:** every old LICENSE text present verbatim; scripts parse clean (`ast.parse`); no conflicting pins
    — **Consumers affected:** compliance readers, script runtime
    — **Done:** no LICENSE/requirements.txt existed upstream (house Apache-2.0; deps are per-route prose installs); 107 absorbed scripts AST-parse clean (BOM file pre-existing, valid utf-8-sig); files: none needed; fixes: none

### Phase 3: Rewire consumers (before any deletion)

- [x] **3.1** Rewire the 9 subagent frontmatters: office-skill allow rules → single `office-document-router-skill` allow; routing tables point at router routes; prose references → route names
    — **Why:** agents must not allow or reference skills Phase 4 removes; allow rules feed requiresSkills derivation
    — **Done when:** grep of agents/ finds zero references to removed IDs outside install-if-missing/MCP-context mentions
    — **Consumers affected:** OpenCode runtime, registry (4.2)
    — **Done:** 9 subagents rewired (allow blocks collapsed to single router allow — effect-line bug found by YAML assertions and fixed across all 9; prose refs → route names); zero old IDs in agents/; files: agents/*.md; fixes: collapse_perms missing-effect-line bug
- [x] **3.2** Update `deploy/skill-profiles.json` lean array (docling/markitdown/pdf entries → `office-document-router-skill`), `installer/presets/pack-business.json` + `pack-docs.json` rosters, and `installer/dependency-map.json` (remove impliesMcp markitdown/docling entries — on-demand MCP enablement moves into the routes per install-assistant conventions; remove the HANDOFF1 requiresSkills pptx pair)
    — **Why:** installer surfaces must match the post-merge installable set or presets/edges dangle
    — **Done when:** JSON parses; zero removed IDs in the three files; dependency-map comment updated; `installer/init.mjs:2040` example + `tests/test_help_parity.bats:43` assertion updated to the router in the same commit
    — **Consumers affected:** installer users, init.mjs
    — **Done:** pack-business 26→18, pack-docs 20→10 (router added); dependency-map impliesMcp ×2 + HANDOFF1 requiresSkills removed ($comment updated); deploy/opencode.json shipped allows 106→102 rules (router added); init.mjs:2040 example + test_help_parity assertion repointed; skill-profiles lean 68→66 (3 entries → router); files: installer/*, deploy/*, tests/test_help_parity.bats; fixes: opencode.json misclassified as MCP-infra-only in the map — corrected
- [x] **3.3** Update the guard tests: retire the pptx `_common` byte-identity rule (test_skill_isolation.bats rule 4 block + vendored-pairwise test) and the HANDOFF1 pair (isolation test vars — positional args renumber — + test_requires_skills.bats HANDOFF1 assertions); adapt `test_docling_skill.bats` + `test_markitdown_skill.bats` to validate the router's route files; update `skill_profiles.bats` 68-hardcodes to the new lean length — gate-red discovery, pulled into 3.3's scope
    — **Why:** guards enforcing the pre-merge topology would fail on the correct post-merge tree
    — **Done when:** bats skill_isolation + requires_skills + skill_profiles + docling/markitdown skill tests pass on the merged tree; `test_help_parity.bats` updated per 3.2, `test_pack_permissions.bats` is MCP-infra-only and untouched
    — **Consumers affected:** repo governance, CI
    — **Done:** isolation rule 4 retired (+ vendored-pairwise test removed); HANDOFF1 retired with positional renumber across isolation + requires_skills (+ test_code_review_inline 298 and test_requirements_inline 589 HANDOFF renumbers); requires_skills map-entry heredoc rebuilt coherently (splice debris + stale names); skill_profiles 68→66 ×3; docling/markitdown test files retargeted to route files; test_master_cloner stale sibling path hook fixed; files: tests/*; fixes: heredoc splice debris + f-string/eval issue + fixture repoint (MODIFIER/SLIDE → plan-execution-inline/testing-inline)
- [x] **3.4** Repoint `AGENTS.md` Office Document Extraction Routing section at the router routes; update README count literals (incl. primary-visible) IN THE SAME COMMITS as roster changes per project anti-pattern; regenerate `installer/registry.json`
    — **Why:** docs routing and generated artifacts must track the tree
    — **Done when:** AGENTS.md section references router routes; count literals equal disk; registry contains the router, zero removed IDs
    — **Consumers affected:** docs readers, installer
    — **Done:** AGENTS.md routing section repointed at the router (ladder ownership inverted); AGENTS.md isolation-contract prose updated (HANDOFF1 exception retired); README category rows (Framework 16→12, Presentation row retired, Office Utilities → Office & Documents (1), Configuration list corrected); registry regenerated; files: AGENTS.md, README.md, installer/registry.json; fixes: none

- [x] **3.5** Rewire surviving-sibling references (arch-review finding, #679 class): `skills/civiltekk-diagram-skill/SKILL.md`, `skills/civiltekk-requirements-specs-skill/` (SKILL.md + references/brd.md + references/srs.md), `skills/civiltekk-startup-docs-skill/references/pitch-deck.md`, `skills/horseshoe-paper-writing-skill/SKILL.md`, `skills/research-paper-generation-skill/SKILL.md`, `skills/technical-design-creation-skill/SKILL.md`, `skills/vision-creation-skill/SKILL.md`, and `THIRD_PARTY_LICENSES.md:251` — repoint at `office-document-router-skill` and its matching route
    — **Why:** all referenced skills are deleted in 4.1; unrewired references dangle at first use
    — **Done when:** grep of the surviving tree (excluding PLANS history and the deleted dirs) finds zero references to the 11 removed IDs
    — **Consumers affected:** users of those skills/docs; 4.3 orphan grep
    — **Done:** 16 references rewired across 7 surviving skills + THIRD_PARTY_LICENSES.md:251; route-file leftover refs (docx/pdf/slides reference.md + DESIGN doc) rewired; files: skills/{7}, THIRD_PARTY_LICENSES.md; fixes: vision-creation line-165 ref missed by first pass — caught by final grep

### Phase 4: Delete, final regen, recount

- [x] **4.1** `git rm -r` the 11 replaced skill dirs
    — **Why:** hard removal per AC; strictly after Phase 3
    — **Done when:** dirs gone; only intended deletions staged
    — **Consumers affected:** registry (4.2), counts (4.3)
    — **Done:** 11 dirs removed (already empty of tracked files — the git mv moves carried the deletions; rmdir + pycache purge only); disk 103; files: skills/{11 dirs}; fixes: none
- [x] **4.2** Final `node installer/build-registry.mjs`; commit regenerated registry
    — **Why:** generated artifact tracks the tree
    — **Done when:** registry has the router + zero removed IDs; diff reviewed
    — **Consumers affected:** installer/init.mjs, npx installer
    — **Done:** final regen after all frontmatter edits (+23/−172: subagent permissions + router entry); registry contains router, zero removed IDs; files: installer/registry.json; fixes: none
- [x] **4.3** Final count sweep: README + deploy scripts counts equal `ls skills/ | wc -l`; case-insensitive orphan grep for the 11 removed IDs (historical PLANS excepted)
    — **Why:** count drift and dangling references are the documented failure modes
    — **Done when:** greps clean; counts match disk; `docs/opencode-agent-tooling-research-2026-09-24.md` residual justified as dated history
    — **Consumers affected:** deploy users, docs readers
    — **Done:** counts equal disk (103); Configuration literal 2 = registry 2; orphan grep: PLANS history + dated research doc + absorbed router-internal history mentions only (justified line-by-line in trace); files: none; fixes: none

### Phase 5: Verify + deliverables (ticket exit gate — full)

- [x] **5.1** Full bats suite green on the final tree
    — **Why:** isolation + governance enforcement
    — **Done when:** exit 0, zero `not ok`
    — **Consumers affected:** repo governance, CI
    — **Done:** full bats green on final tree (0 not-ok after 28→9→3→1→0 gate cycle); files: tests/; fixes: see LOG history
- [x] **5.2** Generalizer verification on the router: ≤10240 bytes, ≤50-word description, load-table rows resolve, route cross-refs resolve, no preload rules, no old-ID path strings
    — **Why:** router-pattern correctness conditions
    — **Done when:** all checks pass with recorded measurements
    — **Consumers affected:** skill consumers
    — **Done:** router 4851 bytes ≤10240; description 42 words ≤50; 11 load-table rows resolve; route cross-refs resolve; only preload hits are negations; zero path-form old IDs in .py or fenced blocks; files: skills/office-document-router-skill/; fixes: none
- [x] **5.3** Record deliverables in the PLAN trace: weight line before→after, change list, residual list
    — **Why:** ticket AC requires reviewable contract deliverables
    — **Done when:** three deliverable blocks present with final numbers
    — **Consumers affected:** reviewers, ticket close
    — **Done:** deliverables block written above (weight line, 4-part change list, 4-item residual list); files: PLANS/PLAN-680.md; fixes: none
- [x] **5.4** Run the full exit gate and write the `tier=full` memo for the final implementation SHA into the PLAN `## Trace

LOG phase-1: docs-only phase (PLAN audit notes); no source files touched.
GATE (phase-1 tree) tier=light lint=n.a typecheck=n.a build=- unit=n.a e2e=n.a
LOG phase-2/3 gate history: first full gate red ×28 — clusters: skill-profiles 68-hardcode + lean⊆allows (subagent allows pending), docling/markitdown skill tests validating absorbed files, requires_skills HANDOFF1 fixtures, isolation rule 4 + sibling-path, presets-dependent deploy tests. Root causes: consumer rewires (Phase 3) are prerequisites of roster coherence; two test files missed by the map (skill_profiles.bats hardcode; docling/markitdown validators). Phase 3 executed within the same gate cycle; registry regen + README counts rode the roster-affecting commit set per the project anti-pattern. Second gate red ×9 (HANDOFF renumber stragglers: cr_inline 298, req_inline 589, requires_skills heredoc, docling/markitdown config assertions encoding the retired impliesMcp design, routing-matrix literal). Third gate: green except isolation 656 → test_master_cloner stale sibling hook. Fourth gate: green.
LOG phase-2: roster-affecting commit — registry regen + README count literals (113→103, lean 68→66, Configuration 4→2) + skill-profiles lean entries ride THIS commit per the project anti-pattern (the git-mv moves already emptied the 11 old dirs, so disk = final roster now; Phase 4's deletion step reduces to rmdir + verify).
`
    — **Why:** PR step cites the memo for the pushed SHA
    — **Done when:** memo line present matching the final pushed SHA
    — **Consumers affected:** PR creation (Step 10a)
    — **Done:** exit gate full on b00a0610 (memo above); files: none; fixes: none

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

LOG phase-5: exit gate full on the pushed implementation tree — bats 0 failures, registry build green (timestamp-only delta), count-drift green.
GATE b00a0610 tier=full lint=t typecheck=n.a build=t unit=t e2e=n.a

## Deliverables (generalizer output contract)

**Weight line**: trigger-time SKILL.md load: 11 catalog entries, 106,586 bytes / ~26.6k tokens across the family (avg ~9.7KB full-body load per trigger) → 1 router at 4,851 bytes (~1.2k tokens) + one route file loaded on match; catalog rows 113 → 103; lean roster 68 → 66; description: per-skill 20–45 words × 11 → one 42-word description with family triggers preserved.

**Change list**:
- Generalized: extraction ladder (AGENTS.md informal table + markitdown tree + docling tiers) → router spine, stated once; design-no-slop principle (docx+xlsx) → spine line; MCP opt-in enablement pattern → spine rule.
- Conditionalized: 11 routes behind WHEN+WHAT load rules; detail files per-route on demand; MCP enablement consent-gated in-route (impliesMcp auto-edges removed for on-demand parity).
- Modularized: single `scripts/_common` pptx engine (×3→1); per-format script dirs (docx/ooxml/pdf/xlsx/thumbnails); `soffice.py` ×4→1 (byte-identical); slide+modifier test suites merged under one conftest.
- Deleted: 11 skill identities; the #437 HANDOFF1 cross-skill handoff (retired by construction); the modifier's SLIDE_SKILL_DIR sibling mechanism; docx "author = Claude" origin artifact; AGENTS.md informal-router ownership (inverted into the router).

**Residual list (owner)**:
- Version pins carried in prose (markitdown `>=0.1.1,<0.2.0`, docling `>=2.0,<3.0`) — trust-boundary re-audit due on major bumps (docling route documents the policy).
- `docs/opencode-agent-tooling-research-2026-09-24.md` retains pre-consolidation skill names — dated research history, left as-is.
- Absorbed docstrings in `_common/` + tests retain historical peer-skill names in narrative comments (non-functional, non-path) — cleanup optional.
- `civiltekk-init`/init.mjs help example now cites `office-document-router-skill`; update again if the example skill changes.
