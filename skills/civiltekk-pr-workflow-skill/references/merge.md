# Merge route — the 5-phase post-merge pipeline

Route `merge` of `civiltekk-pr-workflow-skill` (#604; formerly the
PR-merge member skill). Everything after the PR is approved and
ready to merge: "pr merge to main", "merge the PR to develop", "merge
to [branch]", "complete the PR", "merge it".

## Prerequisites

Before executing, confirm:
- Current branch has an open PR targeting the specified branch
- PR is in a mergeable state (no conflicts, reviews passed)
- If not, tell the user what's blocking and stop

## Phase 0: Promotion Pre-flight (long-lived → long-lived merges)

Runs ONLY when the PR's head AND base are both long-lived lanes (the Phase 1
classifier list — exact, case-sensitive; an unlisted environment-shaped name →
treat as long-lived or ask). Feature/fix heads skip this phase entirely.

### Divergence check (one API call, no local checkout)

`gh api repos/{owner}/{repo}/compare/{target}...{source}` — BASE=target,
HEAD=source — read `ahead_by` (source-side commits: what the promotion will
carry) and `behind_by` (target-only commits the source lacks — fixes that
landed directly on the target lane):

- `ahead_by == 0` and `behind_by == 0` → report "nothing to promote" and stop.
- `behind_by == 0` → no backmerge needed; go straight to Phase 1.
- `behind_by > 0` → backmerge first (below), then Phase 1.

### Backmerge PR (target → source)

Capture target-only fixes before promoting so both lanes converge:

1. Create the backmerge PR: `gh pr create --head <target> --base <source> --title "chore(backmerge): <target> → <source>" --body "Capture <target>-only fixes before promoting <source> → <target> (compare behind_by=N)."`
2. Merge with a merge commit (long-lived head): `gh pr merge <number> --merge --delete-branch=false` — never `--squash` (duplicates content under new SHAs) and never `--admin` (bypasses review protection).
3. Mergeable is `BLOCKED` (conflicts or missing review) → report the blocker and stop. Message convention per `semantic-release-convention-skill` §Promotion Merge Commits.
4. Watch CI on the source branch (Phase 2) — the backmerge must be green before promoting.

### Two modes

- **Promotion request** ("promote dev to uat", no PR open): full-auto — run the divergence check, backmerge if needed, then create the promotion PR (`chore(promote): <source> → <target>`) and continue into Phase 1.
- **Merging a specific open PR** whose head and base are both long-lived: run the divergence check; if `behind_by > 0`, confirm ONCE with the user before backmerging — a backmerge mutates that PR's head branch and re-triggers its CI. On decline, merge as-is and note the remaining divergence in the report.

## Phase 1: Merge the PR

1. Get PR info: `gh pr view --json number,url,headRefName,baseRefName,title,state,mergeable`
2. Verify state is `OPEN` and mergeable is `MERGEABLE`
3. Classify by the PR's **head** branch before merging (the harm exists when the
   head branch survives the merge — squash duplicates content under new SHAs and
   long-lived branches stop converging; verified against a real promotion-branch
   divergence incident):
   - Long-lived head (`main`, `master`, `dev`, `develop`, `development`,
     `production`, `prod`, `uat`, `staging`, `stage`, `preprod`, `pre-dev`,
     `qa`, `test`, `integration`, `release`, `release/*`) → merge commits only:
     `gh pr merge <number> --merge --delete-branch=false`
     Matching is exact and case-sensitive (`Main`/`DEV` do NOT match). A
     branch name that looks like an environment or release lane but is not
     listed → treat as long-lived (the harm asymmetry favors `--merge`) or
     ask the user.
   - Any other head (feature/*, fix/*, hotfix/*, chore/*) → squash default,
     regardless of base: `gh pr merge <number> --squash --delete-branch=false`
   - Escape hatch: an explicit user instruction for THIS PR overrides the
     classifier in either direction. Forcing squash on a long-lived head
     requires a prior warning that it creates SHA divergence — every later
     promotion re-fights the same diffs. The autonomous loop in Step 3b never
     uses this hatch.
   - Do NOT auto-delete branch yet — wait for CI
4. Record: PR number, source branch name, target branch name, JIRA ticket key (if any)

## Phase 2: Monitor GitHub Actions CI

1. Find the post-merge CI run: `gh run list --branch <target-branch> --limit 1`
2. If no CI workflow exists, skip to Phase 4 (no CI to monitor)
3. Monitor the run:
   - Use `gh run view <run-id>` to check status
   - Poll every 30 seconds if still `in_progress`
   - Maximum wait: 10 minutes (configurable by user)
4. Possible outcomes:
   - `completed` + `conclusion: success` → Phase 4
   - `completed` + `conclusion: failure` → Phase 3
   - Timeout → Report to user, ask how to proceed

## Phase 3: Fix CI Failures (Auto-Heal Loop)

This phase loops until CI passes or max retries hit (default: 3 attempts).

### Step 3a: Diagnose

1. Get failure logs: `gh run view <run-id> --log-failed`
2. Identify failing job and step
3. Determine if the failure is fixable by code changes (lint errors, test failures, type errors) or requires human intervention (infrastructure issues, secret rotation)

### Step 3b: Fix

For auto-fixable failures:
1. Checkout the target branch: `git checkout <target-branch> && git pull`
2. Create a fix branch: `git checkout -b fix/ci-<run-id>`
3. Read the failing files and apply fixes
4. Commit with message: `fix(ci): resolve <error-type> from run <run-id>`
5. Push and create PR: `gh pr create --base <target-branch> --title "fix(ci): ..." --body "..."`
6. Merge immediately if trivial, applying the same head-class classifier from
   Phase 1 step 3 (a `fix/ci-*` head resolves to
   `gh pr merge <number> --squash --delete-branch`; a long-lived head requires
   `gh pr merge <number> --merge --delete-branch`). The escape hatch never
   applies inside this autonomous loop.

### Step 3c: Re-Monitor

1. Find the new CI run on the target branch
2. Monitor until pass or fail
3. If pass → Phase 4
4. If fail → increment retry counter, go back to Step 3a
5. If max retries exceeded → report to user with full diagnostic, stop

### Common Auto-Fixes

| Failure Type | Auto-Fix Action |
|-------------|----------------|
| Lint errors | Run linter with --fix, review changes, commit as `fix(lint): <summary>` |
| Type errors | Fix type annotations or casts, commit as `fix(types): <summary>` |
| Test failures | Read test output, fix code or update test if test is wrong, commit as `fix(test): <summary>` |
| Build errors | Fix missing imports, syntax errors, commit as `fix(build): <summary>` |
| Format errors | Run formatter, commit as `style: <summary>` (style-only commit — never mixed with logic) |

### Not Auto-Fixable (Report and Stop)

- Infrastructure/service failures
- Missing secrets or credentials
- Flaky tests (intermittent)
- Dependency resolution conflicts requiring version decisions
- Any failure the agent is not confident about

## Phase 4: Post-Merge Cleanup

### Tracker Integration

If a tracker ticket key was found in the PR title or branch name (pattern: `[A-Z]+-\d+`):
1. Load `ticketing-skill` §Close and delegate the post-merge transition
   and merge comment per its contract
2. If no key found, skip silently

### Branch Cleanup

1. Delete remote source branch: `git push origin --delete <source-branch>`
2. Delete local source branch: `git branch -d <source-branch>`
3. If `--delete-branch=false` was used earlier (step 1.3), clean up now
4. Switch to target branch: `git checkout <target-branch>`

### PLAN.md Cleanup

1. Check if a PLAN.md exists for this branch (e.g., `plans/PLAN-GIT-*.md`)
2. If found and all phases complete, mark as fully complete
3. Commit the final PLAN state

## Summary Report

After all phases complete, report to user:

```
✓ PR #<number> merged into <target-branch>
✓ CI passed (run <run-id>)
✓ Tracker <ticket> → Done
✓ Branch <source-branch> deleted
```

Or if failures occurred:

```
✓ PR #<number> merged into <target-branch>
✗ CI failed (run <run-id>): <error summary>
✓ Auto-fixed and merged fix PR #<fix-number>
✓ CI passed on retry (run <run-id-2>)
✓ Tracker <ticket> → Done
✓ Branch <source-branch> deleted
```

## Agent Requirements

This skill expects the loading agent to have:
- `bash: allow` — for gh CLI, git operations (bash: git-bash/WSL on Windows)
- `edit: allow` — for CI failure fixes
- `read: allow` / `glob: allow` / `grep: allow` — for code analysis
- `ticketing-skill` — for ticket transitions (tracker policy per
  `ticketing-skill` §MCP Availability Guard)

The skill-wide Iteration Protocol (opt-in) lives in the host `SKILL.md`,
stated once — including the merge route's CI auto-fix crash-recovery
pattern with its `autoresearch-core-skill/references/evaluator-contract.md`
and `autoresearch-core-skill/references/crash-recovery.md` citations.
Not restated here.
