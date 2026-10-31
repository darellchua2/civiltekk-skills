# PLAN: Consolidate 15 CAD skills into cad-specialist-skill router

**Branch**: feat/679
**Issue**: https://github.com/darellchua2/civiltekk-skills/issues/679
**Base**: main

## Acceptance Criteria

- [x] `skills/cad-specialist-skill/` ships: router SKILL.md ≤10KB (~2.5k tokens), decision tree, shared spine, load table (Route | Read | When | Skip-when), gates in router; description ≤50 words, trigger phrases preserved
- [x] One `references/routes/<id>.md` per merged route; absorbed scripts + merged `requirements.txt` (dependency-conflict audit)
- [x] Install-if-missing rows: dry-run + consent, never auto-install; no sibling path strings in fenced blocks
- [x] The 10 merged skill dirs hard-removed (the 5 install-on-demand siblings remain: generation, dxf, implicit, redraw, viewer); orphan-reference grep clean for the 10 removed IDs (historical PLANS excepted)
- [x] `agents/cad-specialist-subagent.md` rewired: permissions allowlist 15→1, routing table points at internal routes
- [x] `installer/presets/pack-cad.json` updated; `installer/registry.json` regenerated via `node installer/build-registry.mjs`
- [x] `README.md`, `deploy/setup.sh`, `deploy/setup.ps1` counts/banner updated
- [x] Full bats suite passes (skill isolation, vendored-copy guard)
- [x] Generalizer output contract deliverables: weight line before→after, change list, residual list

## Audit Notes (Phase 1 — detector pass, 2026-10-31)

### Split confirmation (step 1.2)

Merge set confirmed — all self-contained text + stdlib/pip scripts:

| Skill | Route id | Side assets |
|---|---|---|
| cad-urdf-skill | `urdf` | refs 6 files, scripts/urdf + packages/cadpy_metadata, req |
| cad-srdf-skill | `srdf` | refs 8 files, scripts/srdf + same cadpy_metadata (byte-identical), req |
| cad-sdf-skill | `sdf` | refs 12 files, scripts/sdf + same cadpy_metadata (byte-identical), req |
| cad-gcode-skill | `gcode` | refs 2 files, scripts/gcode_tool.py |
| cad-bambu-labs-skill | `bambu` | refs 3 files, scripts/bambu_lan_print.py |
| cad-sendcutsend-skill | `sendcutsend` | refs 2 files, no scripts |
| cad-step-parts-skill | `step-parts` | refs 1 file, scripts/download_step_part.py |
| civil-3d-skill | `civil3d` | text-only |
| autodesk-aps-skill | `aps` | text-only |
| open3d-skill | `open3d` | text-only |

Sibling set confirmed — vendored app or heavy toolchain: cad-generation (1.9MB engine), cad-dxf (732KB), cad-implicit (552KB), cad-redraw (180KB, ODA toolchain runtime deps), cad-viewer (18.5MB vendored browser app). **cad-redraw → sibling** (its weight is runtime tooling, not bytes).

### Named-entity dispositions (step 1.1)

- **Keep (attribution/provenance, not method):** `earthtojake/text-to-cad` provenance links; `extracted from *-specialist-subagent` provenance lines (civil3d/aps/open3d).
- **Keep (domain vocabulary = route identity/service facts):** step.parts / api.step.parts; SendCutSend; Bambu Lab, A1 Mini, p1s-0.4, OrcaSlicer, PrusaSlicer, CuraEngine, Bambu Studio; RViz, Gazebo/Ignition, MoveIt, ROS; Autodesk Civil 3D / Revit / Fusion 360 / AutoCAD / ObjectARX / Dynamo / LINZ; Open3D + dataset/sensor names (KITTI, NuScenes, ScanNet, Azure Kinect, RealSense, LIVOX).
- **Drop (origin-story phrasing, 1 hit):** bambu "the validated A1 Mini path **from this repo's LAN debugging**" → "the validated A1 Mini path (LAN debugging)".
- **Reword (cross-skill path reference, 1 hit):** srdf → "in that skill, read `references/moveit2-server.md`" names a sibling's internal file; reword to skill-name reference without repo path.

### Anecdote→rule scan

No rewrite needed: bambu Failure Modes and gcode backend notes are already signature + mechanism + test form. The STS3215 alias example generalizes (search aliases/vendor spellings) — keep.

### Constants audit

- **Protocol facts (keep unconditional):** Civil 3D PROGID mapping (13.6→13.3), SDF `version="1.12"`, DXF `$INSUNITS` 1=inch/4=mm, Bambu error codes 83935248 / 0500-C010, Open3D API signatures/RANSAC parameters.
- **Examples (keep, clearly illustrative):** 180×180 bed, 220/65 °C temps in JSON shapes.

### Cross-reference resolution (pass 8)

- urdf ↔ srdf ↔ sdf format-boundary references → internal route references.
- gcode ↔ bambu boundary → internal route references.
- sendcutsend → cad-generation-skill → **sibling install-if-missing row** (generation stays out of the merge).
- 6 of 10 routes → cad-viewer-skill handoff → **shared router hard rule** + viewer install-if-missing row ("report if unavailable, never silently omit").
- gcode → references/slicer-backends.md, gcode-validation.md; urdf/srdf/sdf → per-format reference files: absorbed into `references/routes/<id>/` subdirs.
- Repeated verbatim blocks promoted to router spine once: `python`-as-placeholder interpreter note; viewer handoff rule; generation-time validation + report-assumptions shape.

### Vendor facts

- `cadpy_metadata` package byte-identical ×3 (diff -rq clean) → single copy at `scripts/packages/cadpy_metadata`; scripts/urdf|srdf|sdf subdirs preserved as-is.
- LICENSE: all 7 present merge-set LICENSE files identical — **vendored MIT (Copyright earthtojake)** covering the text-to-cad payload → kept at skill root; civil3d/aps/open3d prose is house Apache-2.0 under the repo license. SKILL.md frontmatter Apache-2.0 applied to the prose only. `requirements.txt` ×3 all `--editable ./scripts/packages/cadpy_metadata` → single merged file.


## Dependency & Consumer Map

| Node (file/module) | Depends on (must precede) | Consumers (who depends on this) | Change risk |
|---------------------|---------------------------|---------------------------------|-------------|
| `skills/cad-specialist-skill/` (new) | Phase 1 audit findings | cad-specialist-subagent, installer registry, npx add consumers | med |
| `agents/cad-specialist-subagent.md` | router skill exists (its allow rules reference it) | OpenCode runtime, installer frontmatter dependency edges, registry build | med |
| `installer/presets/pack-cad.json` | final skill roster (Phase 3) | `installer/init.mjs --preset cad` | low |
| `installer/registry.json` | all skill/agent frontmatter final; producer `installer/build-registry.mjs` run in 4.2 (not edited) | installer/init.mjs, npx installer | med |
| 5 persisting sibling SKILL.mds (generation, dxf, implicit, redraw, viewer) | router exists (references repoint at it) | users loading those skills; Phase 4 deletion must not orphan their references | med |
| 10 old skill dirs (delete) | ALL consumer rewires landed (Phase 3) | registry build, setup counts, README tables | high |
| `README.md`, `deploy/setup.sh`, `deploy/setup.ps1` | final roster post-deletion | deploy users, docs readers | low |

Phase ordering constraint: no deletion (4.1) before every consumer of the 10 IDs is rewired (Phase 3); registry regeneration (4.2) strictly after deletion.

## Implementation Phases

### Phase 1: Generalizer audit (detector pass)

- [x] **1.1** Run named-entity, anecdote→rule, constants, and contradiction detectors over the 10 merge-set SKILL.mds; record every proper noun / anecdote / magic number with its disposition (generalize / pin / parameterize / delete) in a new `## Audit Notes` section of this PLAN
    — **Why:** the generalizer method requires the detector pass before merge content is written; dispositions drive route-file content
    — **Done when:** zero un-dispositioned named entities remain in the 10 files; notes list each finding + disposition
    — **Consumers affected:** Phase 2 route files
    — **Done:** all 10 files scanned (read in full); 4 disposition classes recorded in Audit Notes — 2 drop/reword hits, 0 un-dispositioned entities; files: PLANS/PLAN-679.md; fixes: none
- [x] **1.2** Confirm the merge/sibling split against the sizing rule (dir bytes, vendored third-party app detection, heavy runtime deps); decide borderline `cad-redraw` and record the outcome per skill
    — **Why:** the Phase 4 deletion list must be exact before any removal
    — **Done when:** audit notes name the final 10 merge IDs and 5 sibling IDs, each with the rule outcome that placed it
    — **Consumers affected:** Phases 2–4
    — **Done:** split table recorded with per-skill rule outcomes; cad-redraw → sibling (runtime toolchain weight); files: PLANS/PLAN-679.md; fixes: none

### Phase 2: Build skills/cad-specialist-skill/

- [x] **2.1** Write `skills/cad-specialist-skill/SKILL.md` router: frontmatter (name `cad-specialist-skill`, description ≤50 words carrying the family trigger phrases — STEP, STL, DXF, URDF, SRDF, SDF, G-code, 3D printing, SendCutSend, Civil 3D, APS, Open3D, robot description, Gazebo —, license Apache-2.0, compatibility opencode, metadata, category CAD & Hardware Design), identity, decision tree (task type → route, lifted from `agents/cad-specialist-subagent.md` routing table), shared CAD spine (model-first → validate-before-export → units/tolerances → review), load table (Route | Read | When | Skip-when), 5 install-if-missing sibling rows, hard rules as one-liners, gates
    — **Why:** the router is the contract every consumer and route file hangs off; built first so later steps reference a real file
    — **Done when:** file exists; `wc -c` ≤ 10240; description ≤50 words; all 15 routes represented (10 internal rows + 5 sibling rows); no preload instructions
    — **Consumers affected:** cad-specialist-subagent (Phase 3), installer registry (4.2), end users
    — **Done:** router written — 5022 bytes, description 47 words, 10 internal route rows + 5 sibling rows + viewer handoff, only "preload" hits are negation rules; files: skills/cad-specialist-skill/SKILL.md; fixes: none
- [x] **2.2** Write `references/routes/<id>.md` for each of the 10 merged routes from the Phase 1 dispositions + each source SKILL.md's mechanics; absorb scripts/ trees under the route dirs; rewrite any intra-family path strings (e.g. `skills/cad-urdf-skill/scripts/x.py`) to own-dir relative paths so absorbed scripts actually execute
    — **Why:** route files carry the merged mechanics behind load rules; dead absolute paths would break at runtime and trip the isolation guard
    — **Done when:** 10 route files exist, each opening with a WHEN+WHAT load rule line; zero `skills/<removed-id>/` strings in any .py file or fenced block in the new skill dir
    — **Consumers affected:** router load table (2.1)
    — **Done:** 10 route files via git mv + transform (headers with Load when/Skip when/Route dir; viewer boilerplate collapsed to router rule in 7 files; interpreter note → spine pointer in 3; both Phase-1 rewords applied); 10 route detail dirs absorbed; 0 sibling path strings in .py; scripts history-preserving via git mv; files: references/routes/*, scripts/*; fixes: none
- [x] **2.3** Merge the per-skill `requirements.txt` files into one with a dependency-conflict audit (dedupe, resolve version conflicts, note unverifiable pins); carry a smallest-runnable self-check (assert-based) for any non-trivial absorbed script logic
    — **Why:** one self-contained skill must not ship conflicting pins; ponytail check rule for non-trivial logic
    — **Done when:** single `requirements.txt` with no duplicate/conflicting pins (`pip install --dry-run -r` exits 0 or conflicts documented with resolution)
    — **Consumers affected:** route scripts runtime
    — **Done:** single requirements.txt (`--editable ./scripts/packages/cadpy_metadata`; gcode/bambu/step-parts scripts verified all-stdlib, zero third-party imports); closest-executable check: editable+dry-run conflict → 21 absorbed scripts AST-parse clean + package pyproject layout verified; no new logic written → no new test owed (moved proven code); files: requirements.txt; fixes: none
- [x] **2.4** Preserve provenance: carry each merged skill's LICENSE into its route dir (combined NOTICES file when licenses are identical)
    — **Why:** Apache-2.0 house license and any vendored licenses must survive the merge unmodified
    — **Done when:** every license text present in the 10 old dirs is present verbatim in the new skill tree
    — **Consumers affected:** compliance readers
    — **Done:** vendored MIT (earthtojake, byte-identical ×7) at skill root; audit note corrected (frontmatter Apache-2.0 = prose only; civil3d/aps/open3d under repo license); files: LICENSE, PLANS/PLAN-679.md; fixes: audit-note accuracy fix

### Phase 3: Rewire consumers (before any deletion)

- [x] **3.1** Rewrite `agents/cad-specialist-subagent.md`: permissions `action:"skill"` allowlist 15→1 (`cad-specialist-skill`); routing table rows point at internal routes; workflow examples updated; the 5 sibling IDs appear only in install-if-missing context
    — **Why:** the agent must not allow or reference skills that Phase 4 removes; its frontmatter allow rules are the installer's primary dependency source
    — **Done when:** grep of the agent file finds zero references to the 10 removed IDs outside install-if-missing sibling mentions of the 5
    — **Consumers affected:** OpenCode runtime, registry build (4.2)
    — **Done:** permissions 15→1 (siblings deliberately NOT allowed in frontmatter — installer would derive them as requiresSkills and force-install the 18MB viewer, defeating the hybrid); routing table → router routes; pipelines → router flows; point refs → routes; zero removed-ID refs; files: agents/cad-specialist-subagent.md; fixes: none
- [x] **3.2** Update `installer/presets/pack-cad.json`: skills list → `cad-specialist-skill` + the 5 siblings; description updated; `$comment` hand-edit note kept accurate
    — **Why:** the preset must match the post-merge installable set or `--preset cad` breaks
    — **Done when:** preset lists exactly 6 skills + the subagent; JSON parses (`node -e` or jq)
    — **Consumers affected:** installer `--preset cad` users
    — **Done:** preset = router + 5 siblings (6 skills) + subagent; JSON parses; $comment + description updated; files: installer/presets/pack-cad.json; fixes: none

- [x] **3.3** Rewrite absorbed-capability references in the persisting sibling SKILL.mds: `skills/cad-generation-skill/SKILL.md:72` (references `cad-step-parts-skill`) and `skills/cad-dxf-skill/SKILL.md:30` (references `cad-sendcutsend-skill`) repoint at `cad-specialist-skill` and its matching route
    — **Why:** both referenced skills are deleted in 4.1; unrewired references dangle at first use (arch-review finding)
    — **Done when:** grep of the 5 persisting sibling SKILL.mds finds zero references to any of the 10 removed IDs
    — **Consumers affected:** users loading cad-generation-skill / cad-dxf-skill; 5.2 orphan grep
    — **Done:** both anchors rewritten (generation → step-parts route; dxf → sendcutsend route); grep of 5 siblings clean; files: skills/cad-generation-skill/SKILL.md, skills/cad-dxf-skill/SKILL.md; fixes: none

### Phase 4: Delete, regenerate, recount

- [x] **4.1** `git rm -r` the 10 merged skill dirs
    — **Why:** hard removal per AC; strictly after Phase 3 so no consumer dangles mid-history
    — **Done when:** dirs gone; `git status` shows only the 10 intended deletions plus prior phases' changes
    — **Consumers affected:** registry build (4.2), counts (4.3)
    — **Done:** 10 dirs removed (3 already empty from the moves — rmdir; 6 via git rm of tracked residue); only intended deletions staged; files: skills/{10 removed dirs}; fixes: none
- [x] **4.2** Run `node installer/build-registry.mjs`; commit the regenerated `installer/registry.json`
    — **Why:** the registry is generated from skill/agent frontmatter and must never be hand-edited
    — **Done when:** registry contains `cad-specialist-skill`, contains none of the 10 removed IDs; diff shows no unrelated churn
    — **Consumers affected:** installer/init.mjs, npx installer consumers
    — **Done:** final regen run — registry contains cad-specialist-skill, zero removed IDs; files: installer/registry.json; fixes: none
- [x] **4.3** Update `README.md` skill/category tables and counts, `deploy/setup.sh` + `deploy/setup.ps1` counts/banner/help text (repo-root docs included — not just skills-scoped sweeps)
    — **Why:** count drift across deploy scripts and root docs is the documented sync failure mode
    — **Done when:** case-insensitive grep across README.md, deploy/*.sh, deploy/*.ps1 finds no removed IDs; stated counts equal `ls skills/ | wc -l`
    — **Consumers affected:** deploy users, docs readers
    — **Done:** README preset row, CAD category listing (15→6 with capability text), subagent blurb, Autodesk MCP policy pointer updated; setup.sh/ps1 carry no removed IDs (help text count-free, still accurate); case-insensitive grep 0/0/0; counts consistent (113); files: README.md; fixes: README:225 MCP-policy straggler repointed

### Phase 5: Verify + deliverables (full gate — ticket exit gate)

- [x] **5.1** Run the full bats suite (`tests/`), including skill-isolation and vendored-copy guards
    — **Why:** the isolation contract is the repo's mechanical enforcement; this change touches its subject matter directly
    — **Done when:** every bats test exits 0 (guards use grep, not rg — CI parity)
    — **Consumers affected:** repo governance, CI
    — **Done:** full bats suite green on final trees (phase-4 68e57fc and exit-gate 3651923): 703/703, exit 0, 0 `not ok`; files: tests/; fixes: none
- [x] **5.2** Orphan-reference grep for the 10 removed IDs repo-wide, case-insensitive, excluding `.git/` and historical `PLANS/` entries
    — **Why:** a missed consumer reference breaks at first use, not at review
    — **Done when:** remaining hits are only historical PLAN docs or are justified line-by-line in the run report
    — **Consumers affected:** none (verification)
    — **Done:** case-insensitive orphan grep repo-wide: only PLANS history (PLAN-513/553/679) + registry.json (fixed via 3651923, now 0 hits); files: none changed; fixes: registry fix commit 3651923
- [x] **5.3** Generalizer verification pass on the new skill: router ≤10240 bytes, description ≤50 words with triggers intact, every load-table row points at an existing file, route-file cross-references resolve within the skill, no load rule says "read all references", no sibling path strings in fenced blocks
    — **Why:** load-weight and load-rule integrity are the router pattern's correctness conditions
    — **Done when:** all checks pass with recorded measurements (bytes, word count, row→file map)
    — **Consumers affected:** skill consumers
    — **Done:** router 5022 bytes ≤10240; description 47 words ≤50; 10 load-table rows all resolve; 10 route dirs exist; route cross-refs resolve in-skill; only 'preload' hits are negation rules; zero sibling path strings; files: skills/cad-specialist-skill/; fixes: none
- [x] **5.4** Record the generalizer output contract in this PLAN's trace: weight line (SKILL.md bytes/tokens before → after; description word count before → after), change list (generalized / conditionalized / modularized / deleted — one line each), residual list (items flagged for the owner)
    — **Why:** the ticket AC requires the contract deliverables to be reviewable
    — **Done when:** PLAN contains the three deliverable blocks with final numbers
    — **Consumers affected:** reviewers, ticket close
    — **Done:** deliverables block written above (weight line, 4-part change list, 4-item residual list); files: PLANS/PLAN-679.md; fixes: none
- [x] **5.5** Run the full verification gate per verification-loop-skill (command discovery in this repo: bats suite, registry build, JSON validity, shell syntax checks on touched deploy scripts); write the `tier=full` gate memo line for the final tree into the PLAN `## Trace` section
    — **Why:** the pipeline's PR step must cite a green full-gate memo for the exact pushed SHA
    — **Done when:** memo line `GATE <short-sha> tier=full` present in PLAN Trace matching the final pushed SHA
    — **Consumers affected:** PR creation (Step 10a)
    — **Done:** exit gate full on 3651923: build green (regen timestamp-only), bats 703/703 green, memo below; files: none; fixes: registry fix 3651923

## Technical Notes

- Router architecture follows the skill-generalizer router pattern: contract in SKILL.md, mechanics in load-ruled side files, sibling installs on the reader's informed decision (dry-run + consent via civiltekk-install-assistant conventions, never auto-install).
- `installer/dependency-map.json` needs NO edit: no requiresSkills/impliesMcp edges involve the cad family, and install-if-missing rows use skill IDs + installer commands (no sibling path strings), which the isolation guard does not police.
- The 4 robotics/fabrication `requirements.txt` files may pin conflicting versions — the merge audit (2.3) resolves or documents.
- Absorbed scripts keep executable bits; route files document their script entry points.
- git history preserves the old content via the deletion commits; no archive copies (repo history is the archive).

## Dependencies

- None external. Wave 2 (office docs, #680) is blocked-by this ticket per its body.

## Risks & Mitigation

| Risk | Mitigation |
|------|------------|
| requirements.txt merge produces broken pins | 2.3 dry-run audit; document any resolution |
| Absorbed scripts carry sibling path strings that break runtime or trip guards | 2.2 rewrite + 5.3 grep |
| Count/banner drift in deploy scripts or root docs | 4.3 case-insensitive sweep incl. repo-root docs |
| Registry regen picks up unrelated churn | 4.2 diff review |
| Deleted content needed later | git history preserves everything; siblings remain for heavy tooling |

## Trace

(appended at execution: phase commits, gate memos, deliverables)

LOG phase-1: docs-only phase (PLAN audit notes); no source files touched.
GATE b58170f tier=light lint=n.a typecheck=n.a build=- unit=n.a e2e=n.a
LOG phase-2 fix-on-fail: full gate red ×9 with ONE root cause — committed registry.json + README count literals still described the pre-merge roster, while the moves changed disk state (installer `add --all`/setup.sh deploy fail on first missing dir; #659 same-PR rule requires roster changes to carry counts). Fix pulled 4.2's regen + the 6 README count literals (122→113) into this phase commit; skill-profiles.json lean array verified untouched (68). Remaining 4.2/4.3 scope (final regen delta, category listing content, deploy-script help text) unchanged.

GATE 9f0f1a8 tier=full lint=t typecheck=n.a build=t unit=t e2e=n.a
GATE (phase-3 tree) tier=full lint=t typecheck=n.a build=t unit=t e2e=n.a
GATE (phase-4 tree) tier=full lint=t typecheck=n.a build=t unit=t e2e=n.a

LOG phase-5 fix: phase-3's registry regen had been reverted by a gate-time `git checkout installer/registry.json` and never committed — exit-gate orphan grep caught the subagent entry still carrying 15 requiresSkills (incl. 10 deleted dirs, breaking `add --all`). Fix commit 3651923 (regen, requiresSkills 15→1). Rule captured in LEARNINGS (skill-moves-are-roster-changes).

## Deliverables (generalizer output contract)

**Weight line**: trigger-time SKILL.md load: 15 catalog entries, ~5.7KB avg full-body load each (~114,100 bytes / ~28.5k tokens across the family) → 1 router at 5,022 bytes (~1.25k tokens) + one route file (5–13KB) loaded only when matched; route detail dirs (72,914 bytes across 10) load on named demand; catalog rows 15 → 6 (router + 5 install-on-demand siblings); description: per-skill ~25–35 words × 15 → one 47-word description with family triggers preserved.

**Change list**:
- Generalized: viewer-handoff boilerplate (×7) + interpreter-placeholder note (×3) + gen-source-is-truth / validate-before-export rules → router shared spine, stated once.
- Conditionalized: per-route mechanics behind WHEN+WHAT load rules (10 route files + 10 detail dirs); sibling capability behind install-if-missing (dry-run + consent, never auto-install).
- Modularized: 10 absorbed routes (urdf, srdf, sdf, gcode, bambu, sendcutsend, step-parts, civil3d, aps, open3d); vendored cadpy_metadata deduped ×3 → 1; per-format scripts preserved as subdirs.
- Deleted: 10 skill identities (dirs + registry/preset/README/subagent refs); origin-story phrase ("from this repo's LAN debugging"); 2 cross-skill path references reworded; 5 heavy skills deliberately retained as siblings.

**Residual list (owner)**:
- bambu route: device/firmware-specific validated paths (A1 Mini template-project, error codes) — refresh per Bambu firmware releases.
- civil3d + open3d routes: version tables (2022–2026 builds; 0.13–0.19) are time-sensitive — verify per release cycle.
- aps route: official-only Autodesk MCP policy stands; re-admit only with a verified official server.
- npx `add cad-<absorbed>-skill` now 404s by design (hard removal); the router is the entry point.

## Trace
GATE 3651923 tier=full lint=t typecheck=n.a build=t unit=t e2e=n.a
