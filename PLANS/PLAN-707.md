# PLAN: Responsive-audit family — adopt authoring-gate practices, fix stale refs

**Branch**: feat/707
**Issue**: https://github.com/darellchua2/civiltekk-skills/issues/707
**Base**: dev

## Acceptance Criteria

- [ ] AC1 — the methodology skill documents the overflow measurement rule: root `scrollWidth` vs root `clientWidth`, never `window.innerWidth`
- [ ] AC2 — the methodology skill documents the six-viewport named house matrix (phone-portrait, phone-landscape, tablet-portrait, tablet-landscape, desktop, desktop-wide) with a subsetting note
- [ ] AC3 — the subagent's File Scope carries a presence-only rule for emitted regression specs
- [ ] AC4 — no `codegraph_impact`/`codegraph_callers`/`codegraph_callees`/`codegraph_search` reference remains in `agents/responsive-audit-subagent.md`
- [ ] AC5 — the subagent's execution-model section carries only subagent-specific deltas (the methodology skill owns the model)
- [ ] AC6 — generalization gate: the diffs name no origin project and no project-specific vocabulary
- [ ] AC7 — guard tests pass; no frontmatter changes (`installer/registry.json` untouched)

## Dependency & Consumer Map

| Node (file/module) | Depends on (must precede) | Consumers (who depends on this) | Change risk |
|---------------------|---------------------------|---------------------------------|-------------|
| `skills/playwright-responsive-audit-skill/SKILL.md` | — | `agents/responsive-audit-subagent.md` ("Loaded skill"), `skills/responsive-audit-inline-skill/SKILL.md` ("load that skill"), `skills/plan-execution-inline-skill` (delegates the responsive step) | med |
| `agents/responsive-audit-subagent.md` | playwright-responsive-audit-skill | `skills/uiux-review-skill` (delegates fixes), `skills/frontend-design-skill` (pipeline diagram) | med |
| `skills/responsive-audit-inline-skill/SKILL.md` | playwright-responsive-audit-skill | `skills/plan-execution-inline-skill` (delegation row) | low |

## Implementation Phases

### Phase 1: Methodology skill (`skills/playwright-responsive-audit-skill/SKILL.md`)

- [ ] **1.1** Add an "Overflow measurement" rule to the assertion documentation: measure root `scrollWidth` against root `clientWidth`; never compare against `window.innerWidth` (mobile emulation shrinks an overflowing page to fit and `innerWidth` grows with it); report the widest offending element with the viewport name. (AC1)
    — **Why:** assertion #1 (horizontal overflow) false-negatives under mobile emulation without this rule.
    — **Done when:** the methodology file contains the root-comparison rule and the explicit `window.innerWidth` prohibition.
    — **Consumers affected:** responsive-audit-subagent and responsive-audit-inline-skill inherit detection behavior.
- [ ] **1.2** Replace the 3-viewport "house standard" block with the six named viewports (phone-portrait 375×667 touch, phone-landscape 667×375 touch, tablet-portrait 768×1024 touch, tablet-landscape 1024×768 touch, desktop 1280×720, desktop-wide 1440×900), keeping the `playwright.config.ts` `devices[...]` guidance and adding a subsetting note (projects may subset for runtime cost; landscape phone is the highest-value addition). (AC2)
    — **Why:** landscape phones and tablets are unaudited today; they are where width-split layout bugs surface.
    — **Done when:** the matrix table lists all six named viewports with sizes and touch flags, plus one subsetting sentence.
    — **Consumers affected:** responsive-audit-subagent (pass count), responsive-audit-inline-skill (viewport phrasing).

### Phase 2: Subagent (`agents/responsive-audit-subagent.md`)

- [ ] **2.1** Rewrite the "CodeGraph Integration" section to the one exposed tool (`codegraph_explore`, run with the target project path) for change-radius and sibling-pattern checks, with a grep fallback when absent.
    — **Why:** the section names four tools (`codegraph_impact`, `codegraph_callers`, `codegraph_callees`, `codegraph_search`) that the MCP does not expose; an agent following it invents calls.
    — **Done when:** no `codegraph_impact`/`codegraph_callers`/`codegraph_callees`/`codegraph_search` string remains (AC4).
    — **Consumers affected:** none (self-contained guidance).
- [ ] **2.2** Replace the "Background Execution Model" restatement with a two-line pointer to the methodology skill's execution model, plus the one genuine subagent delta (screenshot capture stays one-shot `bash`; only DETECT/RE-VERIFY passes run as background commands).
    — **Why:** the section restates the methodology skill's model nearly line for line; parallel restatements drift.
    — **Done when:** the section is ≤4 lines, names the methodology skill as owner, and keeps the screenshot one-shot rule (AC5).
    — **Consumers affected:** none (the workflow steps reference the model generically).
- [ ] **2.3** Add the presence-only rule to File Scope's `e2e/responsive/**` line: emitted regression specs assert components are present and usable at each viewport — never class, pixel, or bounding-box assertions; geometry belongs to the audit pass, not to checked-in specs.
    — **Why:** emitted specs rot on every intentional layout change when they pin geometry.
    — **Done when:** the File Scope line carries the presence-only rule (AC3).
    — **Consumers affected:** the repos receiving emitted specs (their CI and future diffs).

- [ ] **2.4** Align `skills/responsive-audit-inline-skill/SKILL.md` §Decision tree step 2: replace the hardcoded "mobile/tablet/desktop viewports" phrasing with "the house viewport matrix (`playwright-responsive-audit-skill`)".
    — **Why:** AC2 widens the matrix to six viewports; the inline delegate's hardcoded trio would contradict it post-merge (found in plan review — consumer inspection of the map's third node).
    — **Done when:** the inline skill names the house matrix instead of the three viewport names.
    — **Consumers affected:** `skills/plan-execution-inline-skill` (delegation row unchanged).


### Phase 3: Verification and generalization gate

- [ ] **3.1** Generalizer gate over the full branch diff: no origin-project names and no project-specific vocabulary anywhere in the changed files. (AC6)
    — **Why:** AC6 — ported content must be transferable (a stranger's project executes it without the origin story).
    — **Done when:** `git diff origin/dev...feat/707` contains none of: "canvastekk", "Tekk", "phone-layout", "usePhoneLayout", "useDensity", "viewport-matrix".
    — **Consumers affected:** none.
- [ ] **3.2** Run the repo's skill guard tests and confirm no frontmatter change. (AC7)
    — **Why:** AC7 — the registry and the isolation guards must stay green for a body-only change.
    — **Done when:** the guard suite passes and `git status installer/registry.json` reports no diff.
    — **Consumers affected:** CI (test suite must stay green on the PR).
- [ ] **3.3** Acceptance-criteria sweep: re-read AC1–AC7 against the changed files; each must map to an implementing hunk.
    — **Why:** belt for the thin reviewer map — nothing silently forgotten.
    — **Done when:** each AC cites its hunk (file + section).
    — **Consumers affected:** Step 7 reviewers and Step 9 code review.

## Technical Notes

- The six-viewport matrix and the overflow rule generalize a partner project's responsive authoring gate (reviewed 2026-11-28). Its origin-specific architecture — owner tables, device hooks, a CSS regime variant, density provider — is deliberately NOT ported; only the transferable rules are, reworded to generic vocabulary.
- No frontmatter changes are planned, so `installer/registry.json` is untouched and the registry rebuild step does not run.
- The family stays three layers (methodology / background worker / inline worker); consolidation was considered and rejected — no duplicate to merge.

## Dependencies

None — no blocked-by tickets.

## Risks & Mitigation

- Six viewports raise per-audit runtime → the matrix carries an explicit subsetting note; projects with tight budgets subset and keep landscape phone.
- Wrapper files drifting from the methodology again → Phase 2 slims the restatement instead of editing the two copies in tandem.
