# PLAN: Stop writing LEARNINGS/_index.md and untrack it to kill merge conflicts

**Branch**: feat/684
**Issue**: https://github.com/darellchua2/civiltekk-skills/issues/684
**Base**: main

## Acceptance Criteria
- [ ] `LEARNINGS/_index.md` untracked via `git rm --cached` (local copy retained); `!LEARNINGS/_index.md` negation removed from `.gitignore`
- [ ] `skills/continuous-learning-skill/SKILL.md`: step 5 marker-append rule and step 6 commit list no longer reference `_index.md`; fallback search (line ~54) becomes glob-based
- [ ] `skills/worktree-pipeline-skill/SKILL.md` Step 9: sweep = bodies + `.gitignore` negations only
- [ ] `skills/code-review-inline-skill/SKILL.md` and `skills/reviewer-baseline-skill/SKILL.md`: references updated
- [ ] `deploy/.AGENTS.md` + root `AGENTS.md`: memory-hygiene commit line = body + negation; "dirty `_index.md` blocks pull" clause replaced (moot)
- [ ] Per-body `.gitignore` negation convention switched to end-of-file append (shrinks the remaining touchpoint)
- [ ] Deployed user-space copies (4 skills + AGENTS.md) synced via cp, checksummed
- [ ] Grep: no live skill/agent/AGENTS.md instructs writing `_index.md`; existing body negations intact; plugin manifest unaffected

## Dependency & Consumer Map

| Node (file/module) | Depends on (must precede) | Consumers (who depends on this) | Change risk |
|---------------------|---------------------------|---------------------------------|-------------|
| `LEARNINGS/_index.md` (git tracking) | — | humans browsing; agent fallback search (both served by glob/runtime manifest) | medium — untrack is one-way per clone until re-added |
| `.gitignore` (line 38 negation + per-body negations) | untrack must land in same commit | git tracking semantics for all LEARNINGS files | medium — wrong edit re-ignores tracked bodies |
| `skills/continuous-learning-skill/SKILL.md` | — | every capture flow (agents following memory hygiene) | low — prose |
| `skills/worktree-pipeline-skill/SKILL.md` | — | pipeline Step 9 end-of-ticket sweep | low — prose |
| `skills/code-review-inline-skill/SKILL.md` | — | inline review LEARNINGS writes | low — prose |
| `skills/reviewer-baseline-skill/SKILL.md` | — | every reviewer's learning-gate wording | low — prose |
| `deploy/.AGENTS.md` | source edits | deploys to `~/.config/opencode/AGENTS.md` (every session) | low |
| Deployed copies (`~/.config/opencode/skills/*`, AGENTS.md) | all source edits (sync last) | every future session | low |

## Implementation Phases

### Phase 1: Untrack the index + purge instruction sources
- [ ] **1.1** Untrack `LEARNINGS/_index.md`: `git rm --cached LEARNINGS/_index.md` (working-tree copy retained) and delete the `!LEARNINGS/_index.md` line from `.gitignore`
    — **Why:** the tracked index IS the merge hotspot; untracking removes it from every future merge while the local file keeps human browsability
    — **Done when:** `git ls-files LEARNINGS/_index.md` exits empty, `ls LEARNINGS/_index.md` succeeds, and `.gitignore` has no `_index.md` negation
    — **Consumers affected:** all future merges/pulls in this repo
- [ ] **1.2** Rewrite `skills/continuous-learning-skill/SKILL.md`: step 5 replaced (entry file only — `_index.md` is a local derived cache, never written or committed; discovery = autoinject runtime scan or glob), step 6 commit list drops `_index.md` and mandates end-of-file `.gitignore` negation appends, fallback-search line reads `LEARNINGS/**/*.md` via glob
    — **Why:** this skill is the single instruction source that creates the writes; every other echo inherits its fix
    — **Done when:** `grep -n "_index" skills/continuous-learning-skill/SKILL.md` returns only never-commit guidance, zero write instructions
    — **Consumers affected:** worktree-pipeline + review skills echo this rule
- [ ] **1.3** Update `skills/worktree-pipeline-skill/SKILL.md` Step 9: sweep = body files + `.gitignore` negations (end-of-file appends); drop the tracked-`_index.md`-entry-refresh clause
    — **Why:** the pipeline's end-of-ticket sweep is the highest-frequency writer
    — **Done when:** `grep -n "_index" skills/worktree-pipeline-skill/SKILL.md` returns no write/append instructions
    — **Consumers affected:** every future pipeline run in this repo
- [ ] **1.4** Update `skills/code-review-inline-skill/SKILL.md` (line ~49) and `skills/reviewer-baseline-skill/SKILL.md` (line ~79): LEARNINGS writes = body + negation, no index entry
    — **Why:** reviewers and the review loop repeat the rule; a stale echo would resurrect the write path
    — **Done when:** `grep -n "_index" skills/code-review-inline-skill/SKILL.md skills/reviewer-baseline-skill/SKILL.md` returns nothing
    — **Consumers affected:** inline review flows
- [ ] **1.5** Update `deploy/.AGENTS.md` Memory Hygiene commit bullet: commit = body + end-of-file `.gitignore` negation; replace the "dirty tracked `_index.md` blocks pull/rebase" clause with "`_index.md` is a local derived cache — never commit it"; verify root `AGENTS.md` carries zero `_index` references (confirmed at base — no edit expected)
    — **Why:** AGENTS.md is the ambient instruction every session reads; it must not re-teach the old rule
    — **Done when:** `grep -n "_index" deploy/.AGENTS.md` shows only never-commit guidance; `grep -c "_index" AGENTS.md` = 0
    — **Consumers affected:** deployed `~/.config/opencode/AGENTS.md` (synced in Phase 2)
- [ ] **1.6** Grep-verify: no live skill/agent instructs writing `_index.md` (search `skills/ agents/ plugins/ *.md` for `_index` write/append/commit phrasing near LEARNINGS); existing per-body `!LEARNINGS/` negations intact (count unchanged); commit Phase 1 and push
    — **Why:** belt check that no echo survived before the sync propagates it; per-phase atomic commit
    — **Done when:** verification grep prints only the untrack guidance; negation count matches base; commit `feat/684` pushed
    — **Consumers affected:** Phase 2 sync

### Phase 2: Deployed-copy sync + verification
- [ ] **2.1** Sync deployed user-space copies from updated source: `cp` the 4 edited skills' `SKILL.md` files into `~/.config/opencode/skills/<name>/SKILL.md` and `deploy/.AGENTS.md` into `~/.config/opencode/AGENTS.md`; checksum-verify each pair
    — **Why:** house rule is edit-source-then-sync; deployed copies drive live sessions
    — **Done when:** md5 pairs identical for all 5; deployed `grep -c "_index"` matches source counts
    — **Consumers affected:** every future OpenCode session
- [ ] **2.2** Final verification + PLAN exit state: repo grep clean of `_index` write instructions; `git status` clean; note the one-time untrack side effect for other clones (they keep their tracked index until they adopt this change)
    — **Why:** AC closure and honest documentation of per-clone adoption
    — **Done when:** all greps green; `grep -c '\- \[ \]' PLANS/PLAN-684.md` = 0 unticked ACs
    — **Consumers affected:** none

## Technical Notes
- The autoinject plugin (`plugins/opencode-learnings-autoinject.ts`) builds its manifest via `readdirSync` scan — it never reads `_index.md`; nothing runtime breaks when the index goes untracked.
- Untracking is per-clone: other checkouts keep their tracked copy until they pull this change AND run `git rm --cached`; the skill updates make new sessions stop writing either way.
- `.gitignore` per-body negations: switch insertion convention to end-of-file appends (was: insert after last `!LEARNINGS/` line — mid-file inserts raise parallel-branch conflict odds).
- Repo bats tests reference no `_index` paths (verified at base) — no test updates needed.

## Dependencies
None — single ticket.

## Risks & Mitigation
- **Re-ignoring tracked bodies by accident** (`.gitignore` edit): verify negation count before/after; only the `_index.md` line is removed.
- **Stale echoes resurrect the rule** (a skill file missed in the sweep): repo-wide grep in 1.6 covers `skills/ agents/ plugins/` and root markdown.
- **Human browsability loss**: local `_index.md` remains (untracked, stale-able by design); glob + runtime manifest are the primary paths.
