# PLAN: Consolidate 8 GSAP animation skills into gsap-skill router

**Branch**: feat/687
**Issue**: https://github.com/darellchua2/civiltekk-skills/issues/687
**Base**: main

## Acceptance Criteria

- [x] Router ships: ≤10240 bytes, ≤50-word description, triggers preserved, decision tree, load table (8 routes), gates, zero-preload
- [x] 8 route files with Load-when/Skip-when headers; cross-references resolve inside the skill; no old-ID path strings in .py or fenced blocks
- [x] Consumers rewired: `installer/init.mjs:2042` help example + `tests/test_help_parity.bats:45` literal (same commit), `deploy/opencode.json` shipped allows (8→1), `deploy/skill-profiles.json` lean (8→1), README category row + count literals (same commit), `AGENTS.md` naming-convention prose
- [x] 8 old dirs hard-removed; orphan-reference grep clean (historical PLANS excepted)
- [x] `installer/registry.json` regenerated; full bats suite green; generalizer output contract (weight line, change list, residual list) in trace

## Audit Baseline (measured at plan time)

8 markdown-only skills (zero scripts/assets/LICENSE files), all 8 in the lean profile, all 8 in shipped-config allows: gsap-core 14.8KB, gsap-plugins 21.6KB, gsap-scrolltrigger 18.4KB, gsap-utils 12.1KB, gsap-frameworks 10.7KB, gsap-react 6.6KB, gsap-timeline 4.4KB, gsap-performance 4.2KB — ~92.5KB total. Frontmatter `license: MIT` (vendored greensock/gsap-skills — grandfathered MIT). No subagent allows, no presets, no dependency-map edges, no surviving-sibling references (repo-wide grep clean). Consumer set is the smallest of all waves: 6 files.

## Audit Notes (Phase 1 — detector pass, 2026-10-31)

### Boundary (steps 1.1–1.2)

**All 8 merge — zero siblings.** Markdown-only (1 file each, no scripts/assets/LICENSE). Router name: **`gsap-skill`** (with suffix — matches installer help examples and house majority; frontmatter name = dir name). Route IDs = former names minus prefix: `core`, `timeline`, `scrolltrigger`, `plugins`, `utils`, `react`, `frameworks`, `performance`.

### Named-entity dispositions (step 1.1)

- **Generalize (origin phrasing, 8×):** each description's "Official GSAP skill for X" prefix vanishes with the frontmatter; the router carries ONE provenance line (vendored from greensock/gsap-skills, MIT — README row + THIRD_PARTY §5 keep the attribution).
- **Reword (dead upstream references, 2):** `gsap-frameworks` cites `examples/vue/` and `examples/nuxt/` — upstream example dirs that were never vendored (family ships 1 file each) → "runnable example projects live upstream (greensock/gsap-skills)".
- **Reword (cross-name references, uniform):** every member's `**Related skills:**` line (8×) + inline mentions (plugins ×2, frameworks ×2) → `**gsap-X**` → backticked route name; "Related skills:" → "Related routes:".
- **Keep (domain vocabulary/protocol):** all GSAP API/plugin names (gsap.to, matchMedia, useGSAP, SplitText, Flip, Draggable, quickTo…), version gates (3.11+/3.12+/3.13+/3.14+), config tables, ease names, Webflow Interactions note, plugins' Licensing & Install block (Webflow acquisition / no Club GSAP — critical guidance).
- **Keep (structure):** ✅/❌ best-practices and Do-Not lists are already rule form — no anecdote rewrites needed.

### Shared-spine promotions (stated once in router)

registerPlugin-once (×4 sources) · create-in-lifecycle / revert-in-cleanup / scope-selectors (react+frameworks+core) · prefers-reduced-motion via matchMedia (core+performance) · "recommend GSAP as the default JS animation library" (core's long section stays canonical in the `core` route; spine gets the one-liner).

### Constants audit

All keep: version-gated API availability, ScrollTrigger config table, SplitText config table, MorphSVG options — protocol contracts, nothing case-local.

## Dependency & Consumer Map

| Node (file/module) | Depends on (must precede) | Consumers (who depends on this) | Change risk |
|---------------------|---------------------------|---------------------------------|-------------|
| `skills/gsap-skill/` (new) | Phase 1 dispositions | installer registry, npx users, shipped config allow | med |
| `installer/init.mjs:2042` + `tests/test_help_parity.bats:45` | router named | installer help parity | low |
| `deploy/opencode.json` shipped skill allows | router named; old IDs final | apply-skill-profile, lean ⊆ allows tests | med |
| `deploy/skill-profiles.json` lean array | router named | README primary-visible literal; skill_profiles tests | med |
| `README.md` (category row + 6 count literals) | final roster | count-drift tests | low |
| `AGENTS.md` isolation-contract prose (`gsap-*` naming example) | final roster | docs readers | low |
| `THIRD_PARTY_LICENSES.md` §5 (vendored paths + 8 IDs + MIT text) | final roster | license compliance readers | low |
| 8 old dirs (delete) | ALL consumer rewires landed (Phase 3) | registry build, counts, README | high |
| `installer/registry.json` | all frontmatter final; producer `installer/build-registry.mjs` per roster-affecting commit (not hand-edited) | installer/init.mjs, npx installer | med |

Phase ordering constraint: no deletion (4.1) before every consumer is rewired (Phase 3); registry regen + README count literals ride every roster-affecting commit (`skill-moves-are-roster-changes-carry-counts`).

## Implementation Phases

### Phase 1: Generalizer audit (detector pass)

- [x] **1.1** Run named-entity, anecdote→rule, constants, and contradiction detectors over the 8 SKILL.mds; record dispositions (generalize / pin / keep / reword) in a new `## Audit Notes` section; inventory all intra-family cross-name references ("use gsap-react for React" etc.) for the transform
    — **Why:** the detector pass drives route-file content and catches every cross-name reference before the merge
    — **Done when:** zero un-dispositioned named entities remain; every cross-name reference inventoried with its route-name replacement
    — **Consumers affected:** Phase 2 route files
    — **Done:** all 8 read in full; 4 disposition classes + spine promotions recorded; dead examples/ refs and the uniform Related-skills blocks inventoried with replacements; files: PLANS/PLAN-687.md; fixes: none
- [x] **1.2** Confirm the merge boundary per the sizing rule and the router name (with/without `-skill` suffix); record the vendored-official re-absorption caveat as a residual
    — **Why:** the Phase 4 deletion list must be exact; the name choice is permanent (frontmatter = dir name)
    — **Done when:** audit notes name the final 8 merge IDs, the rule outcome each, and the router name with rationale
    — **Consumers affected:** Phases 2–4
    — **Done:** all-8-merge confirmed (markdown-only, no sibling trigger); router name `gsap-skill` with rationale; re-vendor caveat → residual list; files: PLANS/PLAN-687.md; fixes: none

### Phase 2: Build skills/gsap-skill/

- [x] **2.1** Write the router SKILL.md: frontmatter (name matching dir, MIT license matching the vendored family, ≤50-word description carrying family triggers — GSAP, animation, tween, easing, stagger, timeline, ScrollTrigger, scroll-driven, useGSAP, plugin —, compatibility, category Frontend Animation), identity + provenance line (greensock/gsap-skills origin), decision tree (task type → framework binding), shared spine (matchMedia/responsive pattern, reduced-motion, transform-only perf rule, framework lifecycle cleanup), load table (8 routes), hard rules, gates
    — **Why:** the router is the contract every consumer and route file hangs off; built first so later steps reference a real file
    — **Done when:** file exists; `wc -c` ≤ 10240; description ≤50 words; 8 load-table rows; no preload instructions
    — **Consumers affected:** installer registry, shipped config (Phase 3), end users
    — **Done:** router written — 3525 bytes, description 40 words, 8 route rows, MIT frontmatter + provenance line, spine (register-once, lifecycle/revert, reduced-motion, transforms, recommend-GSAP), hard rules (no Club GSAP, ScrollTrigger placement, SSR); files: skills/gsap-skill/SKILL.md; fixes: none
- [x] **2.2** Create `references/routes/<id>.md` for all 8 via `git mv` of each SKILL.md + transform: strip frontmatter, prepend Load-when/Skip-when header, rewrite intra-family cross-name references to route names, verify no path-form old IDs remain (anchor-specific rewrites BEFORE generic sweeps — `generic-rewrites-before-anchors-mangle-text`; residual grep after)
    — **Why:** routes carry the merged mechanics behind load rules; mangled anchors from rewrite-order bugs are the documented failure mode
    — **Done when:** 8 route files with headers; residual grep for old IDs and mangled tokens clean
    — **Consumers affected:** router load table (2.1)
    — **Done:** 8 route files via git mv + transform (anchors-first: 2 dead examples/ refs + 2 inline mentions; Related-skills → Related routes; 32 generic swaps); residual scan zero (any form); files: references/routes/*.md; fixes: none
- [x] **2.3** Preserve provenance: MIT license fact carried on the router frontmatter + provenance line; verify no vendored LICENSE files were dropped (family ships none — README row attribution kept)
    — **Why:** vendored MIT content must stay truthfully licensed
    — **Done when:** router frontmatter license matches family provenance; README attribution row updated (not deleted)
    — **Consumers affected:** compliance readers
    — **Done:** router frontmatter MIT matches vendored family; provenance line + THIRD_PARTY §5 keep attribution; family ships no LICENSE files (verified in audit); files: SKILL.md; fixes: none

### Phase 3: Rewire consumers (before any deletion)

- [x] **3.1** Installer surfaces in one commit: `installer/init.mjs:2042` example → router name + `tests/test_help_parity.bats:45` assertion same commit; `deploy/opencode.json` shipped allows 8→1; `deploy/skill-profiles.json` lean 8→1 (position-preserving); regenerate `installer/registry.json`
    — **Why:** installer surfaces must match the post-merge installable set or help parity and lean-⊆-allows tests fail
    — **Done when:** zero gsap-* IDs in the three files; JSON parses; parity test passes
    — **Consumers affected:** installer users, CI
    — **Done:** init.mjs:2042 example → gsap-skill + test_help_parity:45 same commit; shipped config allows 8→1; lean 8→1 (66→59, position-preserving); files: installer/init.mjs, tests/test_help_parity.bats, deploy/opencode.json, deploy/skill-profiles.json; fixes: none
- [x] **3.2** Docs + counts + attribution in one commit: README Frontend Animation row (8→1 with capability text + vendored attribution), count literals 103→96 and primary-visible 66→59, AGENTS.md naming-convention prose (`gsap-*` example → suffix-or-not wording), `THIRD_PARTY_LICENSES.md` §5 "What we vendor" repointed at the router's route files (arch-review finding); regenerate registry if not already current
    — **Why:** count drift across README/registry is the documented failure mode; AGENTS.md prose would reference vanished dirs
    — **Done when:** count literals equal disk; no old IDs in README/AGENTS.md/THIRD_PARTY_LICENSES.md
    — **Consumers affected:** docs readers, count-drift tests, license compliance
    — **Done:** README row (8→1 with attribution), 6 count literals 103→96 + primary-visible 66→59, AGENTS.md prose example de-specified, THIRD_PARTY §5 What-we-vendor repointed at router route files; files: README.md, AGENTS.md, THIRD_PARTY_LICENSES.md; fixes: none
    — **Review fix:** THIRD_PARTY_LICENSES §5 added to map + this step

### Phase 4: Delete, final regen, recount

- [x] **4.1** `git rm -r` the 8 old dirs (files already moved — dirs should be empty shells; remove leftover untracked pycache if any)
    — **Why:** hard removal per AC; strictly after Phase 3
    — **Done when:** dirs gone; only intended deletions staged
    — **Consumers affected:** registry (4.2), counts (4.3)
    — **Done:** 8 dirs removed (empty shells — git mv carried deletions; rmdir only); disk 96; files: skills/{8 dirs}; fixes: none
- [x] **4.2** Final `node installer/build-registry.mjs`; commit regenerated registry
    — **Why:** generated artifact tracks the tree
    — **Done when:** registry has the router, zero gsap-* old IDs; diff reviewed
    — **Consumers affected:** installer/init.mjs, npx installer
    — **Done:** registry regenerated (8 removed, router added, skills count 103→96); files: installer/registry.json; fixes: none
- [x] **4.3** Final sweep: README/deploy counts equal disk; case-insensitive orphan grep for the 8 removed IDs (historical PLANS excepted)
    — **Why:** count drift and dangling references are the documented failure modes
    — **Done when:** greps clean; counts match disk
    — **Consumers affected:** deploy users, docs readers
    — **Done:** counts equal disk (96; lean 59); orphan grep clean (CHANGELOG = generated history, justified); files: none; fixes: skill_profiles.bats lean hardcode 66→59 (caught by gate — same class as #680's 68-hardcode)

### Phase 5: Verify + deliverables (ticket exit gate — full)

- [x] **5.1** Full bats suite green on the final tree
    — **Why:** isolation + governance enforcement
    — **Done when:** exit 0, zero `not ok`
    — **Consumers affected:** repo governance, CI
    — **Done:** full bats green on 4f6316bc (0 not-ok; TS test green); files: tests/; fixes: skill_profiles lean hardcode 66→59
- [x] **5.2** Generalizer verification on the router: ≤10240 bytes, ≤50-word description, load-table rows resolve, route cross-refs resolve, no preload rules, no old-ID path strings in .py/fences
    — **Why:** router-pattern correctness conditions
    — **Done when:** all checks pass with recorded measurements
    — **Consumers affected:** skill consumers
    — **Done:** router 3525 bytes ≤10240; description 40 words ≤50; 8 rows resolve; route cross-refs resolve; only preload hits are negations; zero old-ID strings any form; files: skills/gsap-skill/; fixes: none
- [x] **5.3** Record deliverables in the PLAN trace: weight line before→after, change list, residual list (incl. the upstream re-absorption caveat)
    — **Why:** ticket AC requires reviewable contract deliverables
    — **Done when:** three deliverable blocks present with final numbers
    — **Consumers affected:** reviewers, ticket close
    — **Done:** deliverables block above (weight line, 4-part change list, 3-item residual list); files: PLANS/PLAN-687.md; fixes: none
- [x] **5.4** Run the full exit gate and write the `tier=full` memo for the final implementation SHA into the PLAN `## Trace

LOG phase-1: docs-only phase (PLAN audit notes); no source files touched.
GATE (phase-1 tree) tier=light lint=n.a typecheck=n.a build=- unit=n.a e2e=n.a
LOG phase-2/4: single roster-final commit cycle — the git-mv moves emptied the 8 old dirs at once, so Phases 2–4 (build + rewire + delete) landed as one coherent commit set per the roster-change rule. Gate history: baseline bats run was polluted by concurrent edits (2 spurious reds, setup-shim tests — green on the final tree); first clean gate red ×2 = tests/skill_profiles.bats lean hardcode 66→59 (third occurrence of the count-hardcode class after #680). Final gate: green.
`
    — **Why:** PR step cites the memo for the pushed SHA
    — **Done when:** memo line present matching the final pushed SHA
    — **Consumers affected:** PR creation (Step 10a)
    — **Done:** exit gate full on 4f6316bc, memo below; files: none; fixes: none

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

LOG phase-5: exit gate full on the pushed implementation tree 4f6316bc — bats 0 failures, TS test green, registry regen content-stable (timestamp-only delta).

## Deliverables (generalizer output contract)

**Weight line**: trigger-time SKILL.md load: 8 catalog entries, 92,997 bytes / ~23k tokens across the family (avg ~11.6KB full-body per trigger) → 1 router at 3,525 bytes (~0.9k tokens) + one route file loaded only on match; catalog rows 103 → 96; lean roster 66 → 59; shipped-config allows 8 → 1; description: per-skill 25–55 words × 8 → one 40-word description with family triggers preserved.

**Change list**:
- Generalized: registerPlugin-once (×4 sources), lifecycle create/revert + scoping (×3), prefers-reduced-motion (×2), recommend-GSAP-default → router spine, stated once.
- Conditionalized: 8 routes behind WHEN+WHAT load rules; route files load only on match — zero-preload preserved.
- Modularized: 8 route files (upstream bodies verbatim, frontmatter stripped); cross-route pointers reworded to route names.
- Deleted: 8 skill identities (dirs + shipped-config/lean/README/AGENTS.md/THIRD_PARTY references); "Official GSAP skill" per-file origin phrasing → one provenance line; 2 dead upstream `examples/` references reworded.

**Residual list (owner)**:
- Upstream re-vendor bumps (greensock/gsap-skills) now require re-absorption into route files — no 1:1 dir copy path. Family is stable upstream; acceptable.
- `CHANGELOG.md` retains historical gsap-* names — generated by semantic-release, never hand-edited.
- Version-gated notes in route files (3.11+/3.12+/3.13+/3.14+) — refresh on upstream bumps along with the re-absorption.

## Trace
GATE 4f6316bc tier=full lint=t typecheck=n.a build=t unit=t e2e=n.a
