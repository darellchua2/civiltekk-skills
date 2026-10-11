# PLAN: skill-generalizer sweep — Tier 1 org-marker files

**Branch**: feat/668
**Issue**: https://github.com/darellchua2/civiltekk-skills/issues/668
**Base**: main

## Acceptance Criteria
- [ ] Every Tier-1 file passed through all detectors with a recorded disposition (generalize / pin / delete / modularize / keep-justified)
- [ ] No org proper noun remains outside the skill's own identity or a justified one-liner (verification grep clean)
- [ ] semantic-release-convention-skill branch mapping modularized behind a load rule, or keep-justified in writing
- [ ] Change list + weight line + residual list delivered
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
- [ ] **1.1** Neutralize the SSM example paths in `skills/aws-iac-safety-skill/SKILL.md` (:68, :78, :98, :99 → `/<org>/<service>/...` form); keep the :11 provenance comment
    — **Why:** example paths name a real org's parameter store layout — the cross-env passthrough lesson is general (generalizer pass 1: drop the name, keep signature + mechanism + test)
    — **Done when:** grep canvastekk in the file returns only the :11 provenance line
    — **Consumers affected:** none (illustrative strings)
- [ ] **1.2** Generalize `skills/civiltekk-opentofu-skill/references/shared-infra-split.md`: private reference-repo names → pattern descriptions (mark org-internal examples as such), SSM/state-path prefixes → `/{org}/...` / `<ORG>-` forms
    — **Why:** path/reference audit — the skill promises reference repos a public user cannot clone; the ownership/SSM conventions generalize fully
    — **Done when:** grep canvastekk/CANVASTEKK in the file returns zero hits and the module-ownership + state-naming conventions remain intact
    — **Consumers affected:** tofu skill route `shared-infra-split` (loads this file)
- [ ] **1.3** Drop the private-PR citation in `skills/civiltekk-pr-workflow-skill/references/merge.md` (:52) — keep the rule + mechanism, evidence lives in civiltekk LEARNINGS
    — **Why:** anecdote→rule: the citation names a private repo's PR numbers an outside reader cannot verify; the rule and its mechanism stand without it
    — **Done when:** grep betekk in the file returns zero hits; the Phase 1 rule sentence remains
    — **Consumers affected:** merge route prose only
- [ ] **1.4** Neutralize the `repo/KEY` example in `skills/worktree-pipeline-skill/SKILL.md` (:42 → `acme-workflow-engine/ABC-123` form)
    — **Why:** named-entity scan — the syntax example needs no org name
    — **Done when:** grep canvastekk in the file returns zero hits
    — **Consumers affected:** none (doc example)
- [ ] **1.5** Generalize the pptx BETEKK V9.1.1 cluster: `skills/pptx-template-modifier-skill/SKILL.md` (worked-example name → neutral "the reference template defect"), `agents/pptx-specialist-subagent.md` (:332, also fixes the BETeKK typo), `scripts/container_check.py` docstring, `scripts/tests/test_contrast_check.py` + `test_vision_extractor.py` fixture identifiers (`betekk_*` → `theme_defect_*` / `sample.pptx`); run the pptx pytest suite
    — **Why:** anecdote→rule — the container-overflow defect keeps its signature/mechanism/test; the theme name is case-local; test renames are mechanical
    — **Done when:** grep -i betekk across the four files + agent returns zero hits and the pptx pytest suite passes
    — **Consumers affected:** pptx skills' tests (run in gate)
- [ ] **1.6** semantic-release-convention-skill branch-aware tag mapping (dev/uat/main): recorded disposition — KEEP (no org names; the mapping is a usable public convention for any dev/uat/main repo); documented here as the keep-justified record
    — **Why:** ticket AC requires an explicit written disposition; generalizer pass 3 test fails (no jurisdiction lock — any team running dev/uat/main benefits)
    — **Done when:** this Trace line exists (the record)
    — **Consumers affected:** none

### Phase 2: Keep-justified ledger + verification (dispositions recorded)
- [ ] **2.1** Append the residual list to the PLAN Trace: provenance comments (aws-iac :11, threejs :23, react-quality SKILL :22 + hooks :4 + render :4, fastapi-orm :5), org-scope install hints (nextjs-specialist :94/:167, repo-ops :127/:140), README history pointer (:285), CHANGELOG historical — each with a one-line justification
    — **Why:** generalizer output contract — residuals flagged to the owner, verification grep interprets only against the ledger
    — **Done when:** Trace carries the ledger and the final grep's every hit maps to a ledger row
    — **Consumers affected:** future sweeps (the ledger is the baseline)
- [ ] **2.2** Full verification: `grep -rin "betekk\|canvastekk"` over skills/ + agents/ → every hit must be a provenance comment, an intentional org-scope hint, or a ledger row; run `node installer/build-registry.mjs` + the full bats suite + the pptx pytest suite
    — **Why:** ticket exit gate — full
    — **Done when:** gate memo tier=full green; grep audit table in Trace
    — **Consumers affected:** CI

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
