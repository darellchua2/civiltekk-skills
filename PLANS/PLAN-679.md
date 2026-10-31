# PLAN: Consolidate 15 CAD skills into cad-specialist-skill router

**Branch**: feat/679
**Issue**: https://github.com/darellchua2/civiltekk-skills/issues/679
**Base**: main

## Acceptance Criteria

- [ ] `skills/cad-specialist-skill/` ships: router SKILL.md ≤10KB (~2.5k tokens), decision tree, shared spine, load table (Route | Read | When | Skip-when), gates in router; description ≤50 words, trigger phrases preserved
- [ ] One `references/routes/<id>.md` per merged route; absorbed scripts + merged `requirements.txt` (dependency-conflict audit)
- [ ] Install-if-missing rows: dry-run + consent, never auto-install; no sibling path strings in fenced blocks
- [ ] The 10 merged skill dirs hard-removed (the 5 install-on-demand siblings remain: generation, dxf, implicit, redraw, viewer); orphan-reference grep clean for the 10 removed IDs (historical PLANS excepted)
- [ ] `agents/cad-specialist-subagent.md` rewired: permissions allowlist 15→1, routing table points at internal routes
- [ ] `installer/presets/pack-cad.json` updated; `installer/registry.json` regenerated via `node installer/build-registry.mjs`
- [ ] `README.md`, `deploy/setup.sh`, `deploy/setup.ps1` counts/banner updated
- [ ] Full bats suite passes (skill isolation, vendored-copy guard)
- [ ] Generalizer output contract deliverables: weight line before→after, change list, residual list

## Audit Baseline (measured at plan time)

15 skills, ~114,100 bytes of SKILL.md total (~28.5k tokens), ~25MB on disk. Merge set (10): cad-urdf, cad-srdf, cad-sdf, cad-gcode, cad-bambu-labs, cad-sendcutsend, cad-step-parts, civil-3d, autodesk-aps, open3d. Sibling set (5, stay installable): cad-generation (1.9MB), cad-dxf (732KB), cad-implicit (552KB), cad-redraw (180KB, borderline — runtime toolchain-heavy), cad-viewer (18.5MB vendored app).

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

- [ ] **1.1** Run named-entity, anecdote→rule, constants, and contradiction detectors over the 10 merge-set SKILL.mds; record every proper noun / anecdote / magic number with its disposition (generalize / pin / parameterize / delete) in a new `## Audit Notes` section of this PLAN
    — **Why:** the generalizer method requires the detector pass before merge content is written; dispositions drive route-file content
    — **Done when:** zero un-dispositioned named entities remain in the 10 files; notes list each finding + disposition
    — **Consumers affected:** Phase 2 route files
- [ ] **1.2** Confirm the merge/sibling split against the sizing rule (dir bytes, vendored third-party app detection, heavy runtime deps); decide borderline `cad-redraw` and record the outcome per skill
    — **Why:** the Phase 4 deletion list must be exact before any removal
    — **Done when:** audit notes name the final 10 merge IDs and 5 sibling IDs, each with the rule outcome that placed it
    — **Consumers affected:** Phases 2–4

### Phase 2: Build skills/cad-specialist-skill/

- [ ] **2.1** Write `skills/cad-specialist-skill/SKILL.md` router: frontmatter (name `cad-specialist-skill`, description ≤50 words carrying the family trigger phrases — STEP, STL, DXF, URDF, SRDF, SDF, G-code, 3D printing, SendCutSend, Civil 3D, APS, Open3D, robot description, Gazebo —, license Apache-2.0, compatibility opencode, metadata, category CAD & Hardware Design), identity, decision tree (task type → route, lifted from `agents/cad-specialist-subagent.md` routing table), shared CAD spine (model-first → validate-before-export → units/tolerances → review), load table (Route | Read | When | Skip-when), 5 install-if-missing sibling rows, hard rules as one-liners, gates
    — **Why:** the router is the contract every consumer and route file hangs off; built first so later steps reference a real file
    — **Done when:** file exists; `wc -c` ≤ 10240; description ≤50 words; all 15 routes represented (10 internal rows + 5 sibling rows); no preload instructions
    — **Consumers affected:** cad-specialist-subagent (Phase 3), installer registry (4.2), end users
- [ ] **2.2** Write `references/routes/<id>.md` for each of the 10 merged routes from the Phase 1 dispositions + each source SKILL.md's mechanics; absorb scripts/ trees under the route dirs; rewrite any intra-family path strings (e.g. `skills/cad-urdf-skill/scripts/x.py`) to own-dir relative paths so absorbed scripts actually execute
    — **Why:** route files carry the merged mechanics behind load rules; dead absolute paths would break at runtime and trip the isolation guard
    — **Done when:** 10 route files exist, each opening with a WHEN+WHAT load rule line; zero `skills/<removed-id>/` strings in any .py file or fenced block in the new skill dir
    — **Consumers affected:** router load table (2.1)
- [ ] **2.3** Merge the per-skill `requirements.txt` files into one with a dependency-conflict audit (dedupe, resolve version conflicts, note unverifiable pins); carry a smallest-runnable self-check (assert-based) for any non-trivial absorbed script logic
    — **Why:** one self-contained skill must not ship conflicting pins; ponytail check rule for non-trivial logic
    — **Done when:** single `requirements.txt` with no duplicate/conflicting pins (`pip install --dry-run -r` exits 0 or conflicts documented with resolution)
    — **Consumers affected:** route scripts runtime
- [ ] **2.4** Preserve provenance: carry each merged skill's LICENSE into its route dir (combined NOTICES file when licenses are identical)
    — **Why:** Apache-2.0 house license and any vendored licenses must survive the merge unmodified
    — **Done when:** every license text present in the 10 old dirs is present verbatim in the new skill tree
    — **Consumers affected:** compliance readers

### Phase 3: Rewire consumers (before any deletion)

- [ ] **3.1** Rewrite `agents/cad-specialist-subagent.md`: permissions `action:"skill"` allowlist 15→1 (`cad-specialist-skill`); routing table rows point at internal routes; workflow examples updated; the 5 sibling IDs appear only in install-if-missing context
    — **Why:** the agent must not allow or reference skills that Phase 4 removes; its frontmatter allow rules are the installer's primary dependency source
    — **Done when:** grep of the agent file finds zero references to the 10 removed IDs outside install-if-missing sibling mentions of the 5
    — **Consumers affected:** OpenCode runtime, registry build (4.2)
- [ ] **3.2** Update `installer/presets/pack-cad.json`: skills list → `cad-specialist-skill` + the 5 siblings; description updated; `$comment` hand-edit note kept accurate
    — **Why:** the preset must match the post-merge installable set or `--preset cad` breaks
    — **Done when:** preset lists exactly 6 skills + the subagent; JSON parses (`node -e` or jq)
    — **Consumers affected:** installer `--preset cad` users

- [ ] **3.3** Rewrite absorbed-capability references in the persisting sibling SKILL.mds: `skills/cad-generation-skill/SKILL.md:72` (references `cad-step-parts-skill`) and `skills/cad-dxf-skill/SKILL.md:30` (references `cad-sendcutsend-skill`) repoint at `cad-specialist-skill` and its matching route
    — **Why:** both referenced skills are deleted in 4.1; unrewired references dangle at first use (arch-review finding)
    — **Done when:** grep of the 5 persisting sibling SKILL.mds finds zero references to any of the 10 removed IDs
    — **Consumers affected:** users loading cad-generation-skill / cad-dxf-skill; 5.2 orphan grep

### Phase 4: Delete, regenerate, recount

- [ ] **4.1** `git rm -r` the 10 merged skill dirs
    — **Why:** hard removal per AC; strictly after Phase 3 so no consumer dangles mid-history
    — **Done when:** dirs gone; `git status` shows only the 10 intended deletions plus prior phases' changes
    — **Consumers affected:** registry build (4.2), counts (4.3)
- [ ] **4.2** Run `node installer/build-registry.mjs`; commit the regenerated `installer/registry.json`
    — **Why:** the registry is generated from skill/agent frontmatter and must never be hand-edited
    — **Done when:** registry contains `cad-specialist-skill`, contains none of the 10 removed IDs; diff shows no unrelated churn
    — **Consumers affected:** installer/init.mjs, npx installer consumers
- [ ] **4.3** Update `README.md` skill/category tables and counts, `deploy/setup.sh` + `deploy/setup.ps1` counts/banner/help text (repo-root docs included — not just skills-scoped sweeps)
    — **Why:** count drift across deploy scripts and root docs is the documented sync failure mode
    — **Done when:** case-insensitive grep across README.md, deploy/*.sh, deploy/*.ps1 finds no removed IDs; stated counts equal `ls skills/ | wc -l`
    — **Consumers affected:** deploy users, docs readers

### Phase 5: Verify + deliverables (full gate — ticket exit gate)

- [ ] **5.1** Run the full bats suite (`tests/`), including skill-isolation and vendored-copy guards
    — **Why:** the isolation contract is the repo's mechanical enforcement; this change touches its subject matter directly
    — **Done when:** every bats test exits 0 (guards use grep, not rg — CI parity)
    — **Consumers affected:** repo governance, CI
- [ ] **5.2** Orphan-reference grep for the 10 removed IDs repo-wide, case-insensitive, excluding `.git/` and historical `PLANS/` entries
    — **Why:** a missed consumer reference breaks at first use, not at review
    — **Done when:** remaining hits are only historical PLAN docs or are justified line-by-line in the run report
    — **Consumers affected:** none (verification)
- [ ] **5.3** Generalizer verification pass on the new skill: router ≤10240 bytes, description ≤50 words with triggers intact, every load-table row points at an existing file, route-file cross-references resolve within the skill, no load rule says "read all references", no sibling path strings in fenced blocks
    — **Why:** load-weight and load-rule integrity are the router pattern's correctness conditions
    — **Done when:** all checks pass with recorded measurements (bytes, word count, row→file map)
    — **Consumers affected:** skill consumers
- [ ] **5.4** Record the generalizer output contract in this PLAN's trace: weight line (SKILL.md bytes/tokens before → after; description word count before → after), change list (generalized / conditionalized / modularized / deleted — one line each), residual list (items flagged for the owner)
    — **Why:** the ticket AC requires the contract deliverables to be reviewable
    — **Done when:** PLAN contains the three deliverable blocks with final numbers
    — **Consumers affected:** reviewers, ticket close
- [ ] **5.5** Run the full verification gate per verification-loop-skill (command discovery in this repo: bats suite, registry build, JSON validity, shell syntax checks on touched deploy scripts); write the `tier=full` gate memo line for the final tree into the PLAN `## Trace` section
    — **Why:** the pipeline's PR step must cite a green full-gate memo for the exact pushed SHA
    — **Done when:** memo line `GATE <short-sha> tier=full` present in PLAN Trace matching the final pushed SHA
    — **Consumers affected:** PR creation (Step 10a)

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
