# PLAN: skill-generalizer sweep — Tier 1 org-marker files

**Branch**: feat/668
**Issue**: https://github.com/darellchua2/civiltekk-skills/issues/668
**Base**: main

## Acceptance Criteria
- [x] Every Tier-1 file passed through all detectors with a recorded disposition (generalize / pin / delete / modularize / keep-justified)
- [x] No org proper noun remains outside the skill's own identity or a justified one-liner (verification grep clean)
- [x] semantic-release-convention-skill branch mapping modularized behind a load rule, or keep-justified in writing
- [x] Change list + weight line + residual list delivered
- [ ] Contract tests and registry build green; released as its own civiltekk version

## Dependency & Consumer Map

| Node (file/module) | Depends on (must precede) | Consumers (who depends on this) | Change risk |
|---------------------|---------------------------|---------------------------------|-------------|
| `skills/aws-iac-safety-skill/SKILL.md` (SSM example paths) | — | skill readers; example strings only (no code) | low |
| `skills/civiltekk-opentofu-skill/references/shared-infra-split.md` | — | tofu skill route `shared-infra-split`; names private repos a public user cannot access | med |
| `skills/civiltekk-pr-workflow-skill/references/merge.md` (:52 citation) | rule already generic | merge route Phase 1 classifier prose | low |
| `skills/worktree-pipeline-skill/SKILL.md` (:42 example) | — | `repo/KEY` ref syntax example | low |
| `skills/pptx-template-modifier-skill/` (SKILL.md + scripts + 2 test files) + `agents/pptx-specialist-subagent.md` | — | container_check tests (pytest); anecdote naming | med |
| provenance comments (aws-iac :11, threejs, react-quality ×3, fastapi-orm) + org-scope agent hints ×2 + README history pointer | — | none (metadata / decided behavior) | none — keep |

## Implementation Phases

### Phase 1: Generalize content mentions (disposition a)
- [x] **1.1** Neutralize the SSM example paths in `skills/aws-iac-safety-skill/SKILL.md` (:68, :78, :98, :99 → `/<org>/<service>/...` form); keep the :11 provenance comment
    — **Why:** example paths name a real org's parameter store layout — the cross-env passthrough lesson is general (generalizer pass 1: drop the name, keep signature + mechanism + test)
    — **Done when:** grep canvastekk in the file returns only the :11 provenance line
    — **Consumers affected:** none (illustrative strings)
    — **Done:** 4 SSM example paths neutralized to /<org>/<service>/...; provenance line kept; files: skills/aws-iac-safety-skill/SKILL.md; fixes: none
- [x] **1.2** Generalize `skills/civiltekk-opentofu-skill/references/shared-infra-split.md`: private reference-repo names → pattern descriptions (mark org-internal examples as such), SSM/state-path prefixes → `/{org}/...` / `<ORG>-` forms
    — **Why:** path/reference audit — the skill promises reference repos a public user cannot clone; the ownership/SSM conventions generalize fully
    — **Done when:** grep canvastekk/CANVASTEKK in the file returns zero hits and the module-ownership + state-naming conventions remain intact
    — **Consumers affected:** tofu skill route `shared-infra-split` (loads this file)
    — **Done:** private reference-repo names → pattern descriptions (org-internal note), SSM/state prefixes → /{org}/... and <ORG>-; files: skills/civiltekk-opentofu-skill/references/shared-infra-split.md; fixes: none
- [x] **1.3** Drop the private-PR citation in `skills/civiltekk-pr-workflow-skill/references/merge.md` (:52) — keep the rule + mechanism, evidence lives in civiltekk LEARNINGS
    — **Why:** anecdote→rule: the citation names a private repo's PR numbers an outside reader cannot verify; the rule and its mechanism stand without it
    — **Done when:** grep betekk in the file returns zero hits; the Phase 1 rule sentence remains
    — **Consumers affected:** merge route prose only
    — **Done:** private-PR citation replaced with "verified against a real promotion-branch divergence incident"; files: skills/civiltekk-pr-workflow-skill/references/merge.md; fixes: none
- [x] **1.4** Neutralize the `repo/KEY` example in `skills/worktree-pipeline-skill/SKILL.md` (:42 → `acme-workflow-engine/ABC-123` form)
    — **Why:** named-entity scan — the syntax example needs no org name
    — **Done when:** grep canvastekk in the file returns zero hits
    — **Consumers affected:** none (doc example)
    — **Done:** repo/KEY example → acme-workflow-engine/ABC-123; files: skills/worktree-pipeline-skill/SKILL.md; fixes: none
- [x] **1.5** Generalize the pptx BETEKK V9.1.1 cluster: `skills/pptx-template-modifier-skill/SKILL.md` (worked-example name → neutral "the reference template defect"), `agents/pptx-specialist-subagent.md` (:332, also fixes the BETeKK typo), `scripts/container_check.py` docstring, `scripts/tests/test_contrast_check.py` + `test_vision_extractor.py` fixture identifiers (`betekk_*` → `theme_defect_*` / `sample.pptx`); run the pptx pytest suite
    — **Why:** anecdote→rule — the container-overflow defect keeps its signature/mechanism/test; the theme name is case-local; test renames are mechanical
    — **Done when:** grep -i betekk across the four files + agent returns zero hits and the pptx pytest suite passes
    — **Consumers affected:** pptx skills' tests (run in gate)
    — **Done:** BETEKK V9.1.1 → reference-template naming in SKILL.md (2), agent (:332, BETeKK typo fixed), container_check.py docstring; test identifiers/fixtures neutralized (theme_defect_*, sample-theme.pptx); pytest 34/34; files: 4 + agent; fixes: none
- [x] **1.6** semantic-release-convention-skill branch-aware tag mapping (dev/uat/main): recorded disposition — KEEP (no org names; the mapping is a usable public convention for any dev/uat/main repo); documented here as the keep-justified record
    — **Why:** ticket AC requires an explicit written disposition; generalizer pass 3 test fails (no jurisdiction lock — any team running dev/uat/main benefits)
    — **Done when:** this Trace line exists (the record)
    — **Consumers affected:** none
    — **Done:** keep-justified record written (branch mapping serves any dev/uat/main repo; no jurisdiction lock)

### Phase 2: Keep-justified ledger + verification (dispositions recorded)
- [x] **2.1** Append the residual list to the PLAN Trace: provenance comments (aws-iac :11, threejs :23, react-quality SKILL :22 + hooks :4 + render :4, fastapi-orm :5), org-scope install hints (nextjs-specialist :94/:167, repo-ops :127/:140), README history pointer (:285), CHANGELOG historical — each with a one-line justification
    — **Why:** generalizer output contract — residuals flagged to the owner, verification grep interprets only against the ledger
    — **Done when:** Trace carries the ledger and the final grep's every hit maps to a ledger row
    — **Consumers affected:** future sweeps (the ledger is the baseline)
    — **Done:** residual ledger (below); files: PLANS/PLAN-668.md; fixes: none
    — **Residual ledger (keep-justified, one line each):**
      1. provenance comments: aws-iac :11, threejs :23, react-quality SKILL :22 + hooks :4 + render :4, fastapi-orm :5, authentication-authorization :25 — LEARNINGS traceability metadata, house convention, not executable content
      2. org-scope install hints: nextjs-specialist :94/:167, repo-ops :127/:140 — the decided #667 public behavior (print betekk install command, stop)
      3. README history pointer :285 — house consolidation-history line documenting where moved skills live
      4. CHANGELOG.md — historical record, never rewritten (house rule)
      5. semantic-release-convention-skill branch-aware dev/uat/main tag mapping — no org names, no jurisdiction lock; serves any team running that branch model (1.6 record)
- [x] **2.2** Full verification: `grep -rin "betekk\|canvastekk"` over skills/ + agents/ → every hit must be a provenance comment, an intentional org-scope hint, or a ledger row; run `node installer/build-registry.mjs` + the full bats suite + the pptx pytest suite
    — **Why:** ticket exit gate — full
    — **Done when:** gate memo tier=full green; grep audit table in Trace
    — **Consumers affected:** CI
    — **Done:** grep audit + registry build + full suite (memo below); fixes: none

## Technical Notes
- Provenance comments are excluded by the ticket's own framing ("content (not provenance)") and by house LEARNINGS-traceability convention — they stay.
- The `betekk` word survives ONLY in: betekk org-scope install hints (decided #667 behavior), provenance metadata, and the README history line.
- pptx fixture renames are internal to the test files (no public API).

## Dependencies
- Umbrella epic: betekk/canvastekk-tracker#3736 (last open sub-task)
- blocked-by #667 — merged (5c62beb)

## Risks & Mitigation
- Test renames breaking fixture assumptions → pptx pytest suite runs in-gate (1.5)
- Over-generalizing into vagueness → SSM/org path examples keep concrete `/<org>/<service>/env/token` structure; only the proper noun goes

## Trace

- LOG: Step 7 triage — requirements gate skipped (8 checkable steps, all mapped); architecture review skipped with rationale (string/doc generalization only; Step 9 backstops); Tier-1 file list re-derived on post-#669 main: 16 files + README pointer.
- GATE 7e575d0 tier=light lint=n.a typecheck=n.a build=n.a unit=t (pptx pytest 34/34) e2e=n.a
- LOG: Step 9 review (inline) — Critical-class: version router keyed latest-tag auto-resolution off the VERSION file, which semantic-release never bumps — in any maintainer checkout the router would clone the stale tag and silently install it over local edits (exposed by claude/kilo translation tests seeding the source tree). Fix: auto-routing requires no .git (npx trees); maintainer checkouts install their own tree; explicit --ref always honored (second pass caught the over-broad skip breaking the pinned-rollback pin). The three initially-failing tests are the regression pins.
- GATE f7023d6 tier=full lint=n.a typecheck=n.a (node --check) build=n.a unit=t (bats tests/ 662/662, exit 0 — third pass, review-fix re-gate; final SHA) e2e=n.a (pptx pytest 120/120 in-gate)
- LOG: generalizer weight line — 6 generalized bodies: 93121 chars (~23.3k tok) -> 93150 chars (~23.3k tok); the sweep traded ~30 chars of proper nouns for neutral placeholders (weight was never the problem here — specificity was; the +0.03% delta is the placeholder text).
