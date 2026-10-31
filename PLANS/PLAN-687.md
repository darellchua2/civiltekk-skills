# PLAN: Consolidate 8 GSAP animation skills into gsap-skill router

**Branch**: feat/687
**Issue**: https://github.com/darellchua2/civiltekk-skills/issues/687
**Base**: main

## Acceptance Criteria

- [ ] Router ships: ≤10240 bytes, ≤50-word description, triggers preserved, decision tree, load table (8 routes), gates, zero-preload
- [ ] 8 route files with Load-when/Skip-when headers; cross-references resolve inside the skill; no old-ID path strings in .py or fenced blocks
- [ ] Consumers rewired: `installer/init.mjs:2042` help example + `tests/test_help_parity.bats:45` literal (same commit), `deploy/opencode.json` shipped allows (8→1), `deploy/skill-profiles.json` lean (8→1), README category row + count literals (same commit), `AGENTS.md` naming-convention prose
- [ ] 8 old dirs hard-removed; orphan-reference grep clean (historical PLANS excepted)
- [ ] `installer/registry.json` regenerated; full bats suite green; generalizer output contract (weight line, change list, residual list) in trace

## Audit Baseline (measured at plan time)

8 markdown-only skills (zero scripts/assets/LICENSE files), all 8 in the lean profile, all 8 in shipped-config allows: gsap-core 14.8KB, gsap-plugins 21.6KB, gsap-scrolltrigger 18.4KB, gsap-utils 12.1KB, gsap-frameworks 10.7KB, gsap-react 6.6KB, gsap-timeline 4.4KB, gsap-performance 4.2KB — ~92.5KB total. Frontmatter `license: MIT` (vendored greensock/gsap-skills — grandfathered MIT). No subagent allows, no presets, no dependency-map edges, no surviving-sibling references (repo-wide grep clean). Consumer set is the smallest of all waves: 6 files.

## Dependency & Consumer Map

| Node (file/module) | Depends on (must precede) | Consumers (who depends on this) | Change risk |
|---------------------|---------------------------|---------------------------------|-------------|
| `skills/gsap-skill/` (new) | Phase 1 dispositions | installer registry, npx users, shipped config allow | med |
| `installer/init.mjs:2042` + `tests/test_help_parity.bats:45` | router named | installer help parity | low |
| `deploy/opencode.json` shipped skill allows | router named; old IDs final | apply-skill-profile, lean ⊆ allows tests | med |
| `deploy/skill-profiles.json` lean array | router named | README primary-visible literal; skill_profiles tests | med |
| `README.md` (category row + 6 count literals) | final roster | count-drift tests | low |
| `AGENTS.md` isolation-contract prose (`gsap-*` naming example) | final roster | docs readers | low |
| 8 old dirs (delete) | ALL consumer rewires landed (Phase 3) | registry build, counts, README | high |
| `installer/registry.json` | all frontmatter final; producer `installer/build-registry.mjs` per roster-affecting commit (not hand-edited) | installer/init.mjs, npx installer | med |

Phase ordering constraint: no deletion (4.1) before every consumer is rewired (Phase 3); registry regen + README count literals ride every roster-affecting commit (`skill-moves-are-roster-changes-carry-counts`).

## Implementation Phases

### Phase 1: Generalizer audit (detector pass)

- [ ] **1.1** Run named-entity, anecdote→rule, constants, and contradiction detectors over the 8 SKILL.mds; record dispositions (generalize / pin / keep / reword) in a new `## Audit Notes` section; inventory all intra-family cross-name references ("use gsap-react for React" etc.) for the transform
    — **Why:** the detector pass drives route-file content and catches every cross-name reference before the merge
    — **Done when:** zero un-dispositioned named entities remain; every cross-name reference inventoried with its route-name replacement
    — **Consumers affected:** Phase 2 route files
- [ ] **1.2** Confirm the merge boundary per the sizing rule and the router name (with/without `-skill` suffix); record the vendored-official re-absorption caveat as a residual
    — **Why:** the Phase 4 deletion list must be exact; the name choice is permanent (frontmatter = dir name)
    — **Done when:** audit notes name the final 8 merge IDs, the rule outcome each, and the router name with rationale
    — **Consumers affected:** Phases 2–4

### Phase 2: Build skills/gsap-skill/

- [ ] **2.1** Write the router SKILL.md: frontmatter (name matching dir, MIT license matching the vendored family, ≤50-word description carrying family triggers — GSAP, animation, tween, easing, stagger, timeline, ScrollTrigger, scroll-driven, useGSAP, plugin —, compatibility, category Frontend Animation), identity + provenance line (greensock/gsap-skills origin), decision tree (task type → framework binding), shared spine (matchMedia/responsive pattern, reduced-motion, transform-only perf rule, framework lifecycle cleanup), load table (8 routes), hard rules, gates
    — **Why:** the router is the contract every consumer and route file hangs off; built first so later steps reference a real file
    — **Done when:** file exists; `wc -c` ≤ 10240; description ≤50 words; 8 load-table rows; no preload instructions
    — **Consumers affected:** installer registry, shipped config (Phase 3), end users
- [ ] **2.2** Create `references/routes/<id>.md` for all 8 via `git mv` of each SKILL.md + transform: strip frontmatter, prepend Load-when/Skip-when header, rewrite intra-family cross-name references to route names, verify no path-form old IDs remain (anchor-specific rewrites BEFORE generic sweeps — `generic-rewrites-before-anchors-mangle-text`; residual grep after)
    — **Why:** routes carry the merged mechanics behind load rules; mangled anchors from rewrite-order bugs are the documented failure mode
    — **Done when:** 8 route files with headers; residual grep for old IDs and mangled tokens clean
    — **Consumers affected:** router load table (2.1)
- [ ] **2.3** Preserve provenance: MIT license fact carried on the router frontmatter + provenance line; verify no vendored LICENSE files were dropped (family ships none — README row attribution kept)
    — **Why:** vendored MIT content must stay truthfully licensed
    — **Done when:** router frontmatter license matches family provenance; README attribution row updated (not deleted)
    — **Consumers affected:** compliance readers

### Phase 3: Rewire consumers (before any deletion)

- [ ] **3.1** Installer surfaces in one commit: `installer/init.mjs:2042` example → router name + `tests/test_help_parity.bats:45` assertion same commit; `deploy/opencode.json` shipped allows 8→1; `deploy/skill-profiles.json` lean 8→1 (position-preserving); regenerate `installer/registry.json`
    — **Why:** installer surfaces must match the post-merge installable set or help parity and lean-⊆-allows tests fail
    — **Done when:** zero gsap-* IDs in the three files; JSON parses; parity test passes
    — **Consumers affected:** installer users, CI
- [ ] **3.2** Docs + counts in one commit: README Frontend Animation row (8→1 with capability text + vendored attribution), count literals 103→96 and primary-visible 66→59, AGENTS.md naming-convention prose (`gsap-*` example → suffix-or-not wording); regenerate registry if not already current
    — **Why:** count drift across README/registry is the documented failure mode; AGENTS.md prose would reference vanished dirs
    — **Done when:** count literals equal disk; no old IDs in README/AGENTS.md
    — **Consumers affected:** docs readers, count-drift tests

### Phase 4: Delete, final regen, recount

- [ ] **4.1** `git rm -r` the 8 old dirs (files already moved — dirs should be empty shells; remove leftover untracked pycache if any)
    — **Why:** hard removal per AC; strictly after Phase 3
    — **Done when:** dirs gone; only intended deletions staged
    — **Consumers affected:** registry (4.2), counts (4.3)
- [ ] **4.2** Final `node installer/build-registry.mjs`; commit regenerated registry
    — **Why:** generated artifact tracks the tree
    — **Done when:** registry has the router, zero gsap-* old IDs; diff reviewed
    — **Consumers affected:** installer/init.mjs, npx installer
- [ ] **4.3** Final sweep: README/deploy counts equal disk; case-insensitive orphan grep for the 8 removed IDs (historical PLANS excepted)
    — **Why:** count drift and dangling references are the documented failure modes
    — **Done when:** greps clean; counts match disk
    — **Consumers affected:** deploy users, docs readers

### Phase 5: Verify + deliverables (ticket exit gate — full)

- [ ] **5.1** Full bats suite green on the final tree
    — **Why:** isolation + governance enforcement
    — **Done when:** exit 0, zero `not ok`
    — **Consumers affected:** repo governance, CI
- [ ] **5.2** Generalizer verification on the router: ≤10240 bytes, ≤50-word description, load-table rows resolve, route cross-refs resolve, no preload rules, no old-ID path strings in .py/fences
    — **Why:** router-pattern correctness conditions
    — **Done when:** all checks pass with recorded measurements
    — **Consumers affected:** skill consumers
- [ ] **5.3** Record deliverables in the PLAN trace: weight line before→after, change list, residual list (incl. the upstream re-absorption caveat)
    — **Why:** ticket AC requires reviewable contract deliverables
    — **Done when:** three deliverable blocks present with final numbers
    — **Consumers affected:** reviewers, ticket close
- [ ] **5.4** Run the full exit gate and write the `tier=full` memo for the final implementation SHA into the PLAN `## Trace`
    — **Why:** PR step cites the memo for the pushed SHA
    — **Done when:** memo line present matching the final pushed SHA
    — **Consumers affected:** PR creation (Step 10a)

## Technical Notes

- Family ships no scripts, no LICENSE files, no requirements — pure prose skills; no dependency-conflict audit needed.
- Registry note from #684: registry drifts on ANY skill edit — rebuild after prose edits too, not just roster changes.
- AGENTS.md:17 uses `gsap-*` as the naming-convention example ("name suffix or not") — reword to keep the example truthful post-merge.

## Dependencies

- None external. Runs first in the Wave-3 chain (#687 → #688 → #689 → #690 → #691).

## Risks & Mitigation

| Risk | Mitigation |
|------|------------|
| Upstream GSAP re-vendor bump can no longer be a dir copy | Residual list names the re-absorption path; family is stable (long pin cycle) |
| Rewrite-order mangles anchors (generic swap before specific reword) | 2.2 orders anchor-specific first; residual grep for mangled tokens |
| Count/registry drift mid-phase | Regen + literals ride roster-affecting commits; count-drift tests verify |
| Description >50 words with 8 routes' triggers | Trim to task-type triggers; route files carry the long tails |

## Trace

(appended at execution: phase commits, gate memos, deliverables)
