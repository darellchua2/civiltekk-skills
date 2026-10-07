# PLAN: Formalize ## Trace section in the PLAN contract

**Branch**: feat/662
**Issue**: https://github.com/darellchua2/civiltekk-skills/issues/662
**Base**: main

## Acceptance Criteria
- [x] `## Trace` declared in the canonical template (grilling-skill §PLAN emission), documented append-only with GATE/LOG/SKIP line types
- [x] Both executors append GATE/LOG/SKIP lines to `## Trace`; per-step `— Done:` lines unchanged
- [x] `verification-loop-skill` §Gate memo references the `## Trace` section with create-if-absent for legacy PLANs
- [x] `worktree-pipeline-skill` green assertion cites the `## Trace` section
- [ ] `grep -rn "trace block" skills/` returns empty
- [x] `--soft` acceptance-criteria check reads to the next `^## ` heading instead of a fixed 20-line window
- [ ] Existing bats suite green (body-only edits, no structural changes)

## Dependency & Consumer Map

| Node (file/module) | Depends on (must precede) | Consumers (who depends on this) | Change risk |
|---------------------|---------------------------|---------------------------------|-------------|
| `skills/grilling-skill/SKILL.md` | — | plan-execution-skill, plan-execution-inline-skill (parse the template contract); authors of every future PLAN | medium — canonical contract source |
| `skills/plan-execution-skill/SKILL.md` | 1.1 (template must declare the section first) | verification-loop-skill (memo destination), worktree-pipeline-skill Steps 8–10 | low — body-only prose |
| `skills/plan-execution-inline-skill/SKILL.md` | 1.1 | worktree-pipeline-skill Step 8 (default arm) | low — body-only prose, mirrors 1.2 |
| `skills/verification-loop-skill/SKILL.md` | 1.1 | both executors (gate memo format + destination), worktree-pipeline-skill 10a citation | low |
| `skills/worktree-pipeline-skill/SKILL.md` | 1.4 (memo pointer must exist to cite) | pipeline runs (green assertion, Step 10a prompt) | low |

## Trace

GATE ea646a3 tier=light lint=n.a typecheck=n.a build=- unit=t e2e=n.a

## Implementation Phases

### Phase 1: Contract + executor updates
- [x] **1.1** Declare `## Trace` in `skills/grilling-skill/SKILL.md` §PLAN emission — add the append-only section to the template block (after `## Dependency & Consumer Map`) and extend the contract-rules paragraph with the GATE/LOG/SKIP line types and the never-rewrite rule
    — **Why:** every other step writes into a section this template must first declare; the template is the contract source all executors parse
    — **Done when:** the template block in the file contains `## Trace` and the contract-rules paragraph names GATE/LOG/SKIP as append-only line types
    — **Consumers affected:** plan-execution-skill, plan-execution-inline-skill, verification-loop-skill, worktree-pipeline-skill
    — **Done:** template block carries `## Trace` with the three line types; contract-rules paragraph documents append-only + never-rewrite; files: skills/grilling-skill/SKILL.md; fixes: none
- [x] **1.2** Point `skills/plan-execution-skill/SKILL.md` at the `## Trace` section — reword 4c ("PLAN trace block" → `## Trace`), give 4d fix attempts a home (LOG lines in `## Trace`), add the SKIP-line rule to 4e, split the §Traceability section into per-step Done lines vs run-level Trace, and replace the `--soft` step-4 `grep -A 20` with an awk read-to-next-`^## `-heading scan
    — **Why:** this executor is the subagent-arm writer of gate memos and the owner of the brittle acceptance-criteria check
    — **Done when:** the file contains no "trace block" wording, 4d names `## Trace` as the LOG-line home, and no `-A 20` remains in the `--soft` final-validation step
    — **Consumers affected:** worktree-pipeline-skill Steps 8–10, verification-loop-skill §Gate memo
    — **Done:** 4c/4d/4e reworded to `## Trace`, Traceability split added, awk heading-scan replaced the `-A 20` grep; files: skills/plan-execution-skill/SKILL.md; fixes: none
- [x] **1.3** Mirror 1.2 in `skills/plan-execution-inline-skill/SKILL.md` — identical 4c/4d/4e wording and §Traceability split (isolation contract: the two executors intentionally duplicate; `--soft` does not exist here, so no grep change)
    — **Why:** the inline arm is the default `/run-plan` executor; contract drift between the twins is the regression class the isolation contract tolerates only when both carry identical text
    — **Done when:** the inline file's 4c/4d/4e and §Traceability text matches the subagent file's wording for these sections and contains no "trace block" wording
    — **Consumers affected:** worktree-pipeline-skill Step 8 (inline default arm)
    — **Done:** 4c/4d/4e + Traceability split mirrored verbatim (modulo the pre-existing "§Tiered gating there selects" vs "it selects" divergence, out of scope); files: skills/plan-execution-inline-skill/SKILL.md; fixes: none
- [x] **1.4** Repoint `skills/verification-loop-skill/SKILL.md` §Gate memo — "PLAN trace block" → "the PLAN's `## Trace` section (declared in the canonical template; create it if absent when appending to a legacy PLAN)"
    — **Why:** this skill owns the canonical memo format; its destination reference is what both executors defer to
    — **Done when:** §Gate memo names `## Trace` and carries the create-if-absent rule
    — **Consumers affected:** plan-execution-skill, plan-execution-inline-skill, worktree-pipeline-skill
    — **Done:** §Gate memo names `## Trace` with template citation + create-if-absent for legacy PLANs; files: skills/verification-loop-skill/SKILL.md; fixes: none
- [x] **1.5** Update `skills/worktree-pipeline-skill/SKILL.md` — the Step 10a green-assertion citation ("from the PLAN trace block") names "the PLAN's `## Trace` section"
    — **Why:** the pipeline's merge authorization cites the memo's location; a stale location string would send the citation to a section that no longer matches the contract
    — **Done when:** no "trace block" wording remains in the file and the citation reads `## Trace`
    — **Consumers affected:** pipeline Step 10a PR-creation prompts
    — **Done:** 10a citation reads "from the PLAN's `## Trace` section"; files: skills/worktree-pipeline-skill/SKILL.md; fixes: none

### Phase 2: Verification
- [ ] **2.1** Run the dangling-reference grep gate: `grep -rn "trace block" skills/` must return empty
    — **Why:** proves the cross-reference consumed by four skills now resolves to a declared section — the ticket's core defect is gone
    — **Done when:** the grep command exits with no matches
    — **Consumers affected:** none
- [ ] **2.2** Run the bats suite (`bats tests/`) and confirm green
    — **Why:** body-only edits must not break the isolation, portability, or registry guard tests
    — **Done when:** the suite exits 0
    — **Consumers affected:** none

## Technical Notes
- Isolation contract (#437): the two executor skills intentionally duplicate prose — apply identical wording to both; never extract a shared module.
- Body-only edits: no frontmatter keys change → no `installer/build-registry.mjs` rebuild, no README/setup.sh count sync.
- Gate memo format itself is unchanged (`verification-loop-skill` §Gate memo) — only its destination is named.
- Repo has no markdown linter; the scoped-lint gate leg is n.a. for `.md`-only phases (light tier = affected tests only).

## Dependencies
None — single-ticket run.

## Risks & Mitigation
- Prose drift between the two executor files → identical wording applied in 1.2/1.3, verified by the Step 9 review diff.
- A "trace block" mention outside the five planned files → repo-wide grep gate at 2.1 catches strays.
