---
name: ticketing-skill
description: >-
  Ticket lifecycle for GitHub Issues (default) or JIRA — create, start
  (in-progress), classify/label, update from commits, close (post-merge,
  idempotent), ticket-key↔branch plumbing, epic/parent grouping. CRUD only:
  no branches, PLANs, execution. Triggers: any ticket/issue
  create·start·label·update·close, bug report, feature request.
license: Apache-2.0
compatibility: opencode
category: Git/Workflow
---

Consolidates `ticket-creation-skill`, `git-issue-labeler-skill`,
`git-issue-updater-skill`, `jira-git-integration-skill`,
`jira-status-updater-skill`, `jira-ticket-labeler-skill` (#599).

## What I do

Ticket CRUD and classification — **GitHub Issues is the default tracker;
JIRA is opt-in**:

1. **Resolve the tracker** (§Platform Detection) — `github` unless the user
   explicitly says JIRA; GitHub is also the fallback when JIRA is unavailable.
2. **Route the lifecycle op** (§Lifecycle): create · classify/label · start ·
   update · close · git plumbing — op mechanics live in the phase files.
3. **Load the values** for the resolved tracker (`references/github.md` /
   `references/jira.md`) plus the phase file for the op.

Branch creation, PLAN generation, execution, and release/versioning belong to
`worktree-pipeline-skill` (`/run-worktree-pipeline`) and
`semantic-release-convention-skill` — never here.

## Side files (load rules)

| Read | When | Use |
|------|------|-----|
| `references/github.md` | resolved tracker is `github` | gh commands, 3-tier tooling fallback, label vocabulary + LABELS array, semver rule, `#N` key format, epic/parent linking, attribution rules, templates contract |
| `references/jira.md` | resolved tracker is `jira` | MCP discovery workflow, REST endpoints, type/priority vocabulary, transitions, `PROJ-123` key format, epic/parent linking, attribution rules, description templates |
| `references/phases/create.md` | lifecycle op is **create** | five-stage intake mechanics, epic/sequence handoff, `blocked-by:` convention |
| `references/phases/update.md` | lifecycle op is **update** | ref-to-artifact mechanics, progress-comment template, idempotency check |
| `references/phases/close.md` | lifecycle op is **close** | post-merge transition mechanics, merge-comment template, failure isolation |

Side files carry VALUES and OP MECHANICS; this file carries the METHOD —
decision gates, contracts, vocab routing. An unknown platform (Linear, Azure
Boards, …) → detect-and-ask; if `references/<platform>.md` does not exist,
report the platform as unsupported and suggest contributing a side file —
never improvise endpoints.

## Platform Detection

GitHub Issues is the default tracker. JIRA is never assumed — not from
project configuration, installed tools, or conventions alone.

1. **The user names the tracker** — "JIRA" or a `PROJ-123`-style key →
   `jira`; a `#123` ref, "GitHub issue", "create issue" → `github`. Explicit
   beats everything.
2. **The artifacts name the ticket** (update/close ops): a `#N` in the
   branch/commits/PR → `github`; a JIRA-shaped key there → `jira`. The key
   IS the ticket's identity — there is no second ticket to prefer.
3. **No signal at all** → `github`. Never ask which platform; announce the
   default in one line ("defaulting to GitHub Issues") and proceed. A repo's
   JIRA usage (env vars, AGENTS.md mentions, enabled tools) is a data point
   to report, never a route.

Every `jira` resolution runs through §MCP Availability Guard before any
`atlassian_*` call. Before any GitHub operation, resolve the **tooling
tier** (`references/github.md` §Tooling fallback): `gh` present → full CRUD;
missing → prompt the user to install (`gh-cli-setup-skill`); declined →
git-only tier with its honest per-operation limits.

## Lifecycle

### Create

The agent runs the same intake a human runs in the browser issue form. Never
invent field values; ask for what is missing. The five-stage mechanics
(classify → intake → validate → preview → submit) are
`references/phases/create.md`; the parity contract is here.

**Field spec** (canonical; matches `templates/*.yml` verbatim so agent- and
form-created tickets are structurally identical):

*Bug variant* (mirrors `bug_report.yml`): Title (≤72 chars, required) ·
Problem description (required) · Steps to reproduce (numbered, required) ·
Expected vs Actual (one line each, required) · Environment (OS/Node/opencode
version + install method, required) · Logs / screenshots (optional) ·
References (optional).

*Feature/Task variant* (mirrors `feature_request.yml`): Title (≤72, required)
· Problem / use case (required) · Proposed solution (required) ·
Alternatives considered (optional) · Acceptance criteria (required,
definition of done) · Scope (required, agent flow only — flows to the PLAN,
never the browser form) · References (optional).

**Rendering schema** — one canonical schema, two renderings; variant selects
sections; sections mirror the form headings. The section-by-section schema:
`references/phases/create.md` §Rendering schema. JIRA description mapping per
`references/jira.md` §Description templates.

**Epic / parent grouping.** Single ticket vs parent with children — ask,
batched with intake. An epic is a parent ticket, not a new type: GitHub — a
normal parent issue whose children carry `Parent: #N` (the portable floor;
native sub-issues per `references/github.md` §Epic — verify locally). JIRA —
native Epic/parent per `references/jira.md` §Epic. "If possible" means the
body-ref link is always available; richer linkage is best-effort.

**Sequence handoff** (multi-ticket runs only) — ordering derivation and the
`blocked-by:` convention: `references/phases/create.md`.

### Classify / Label

Keyword + semantic analysis — keywords are intent signals, not substring
matches ("add" in "address" is not an enhancement); analyze title AND body;
check negations; explicit requests differ from questions; comments may carry
deciding context. Low confidence → leave unlabeled (or `enhancement`) and
comment a clarification request.

**Structural rules (method):**
- Issues get type + priority labels/fields; **PRs get exactly one semver
  label** derived structurally from the PR title's Conventional Commit prefix
  (`feat!`→major, `feat`→minor, else patch) — never from issue content.
  Semver definitions follow `semantic-release-convention-skill` — cited,
  never redefined. Tagging/version-bump are release tooling's job, not this
  skill's.
- Exactly one priority per issue; max 3 labels (type + priority + one
  auxiliary).
- Auto-create missing labels first (GitHub) — never fail on a missing label.

Vocabularies, keyword tables, LABELS arrays, GitHub↔JIRA mappings:
`references/github.md` §Label vocabulary, `references/jira.md` §Vocabulary.

### Start (execution begins)

When implementation of a ticket begins — the pipeline's worktree-creation
boundary; `worktree-pipeline-skill` Step 4 is the canonical caller:

1. **Check current status first** — already in-progress or beyond
   (done-category) → skip the transition. This is the check-first guard,
   mirroring §Close's transition-once rule.
2. **Transition** to the in-progress-category target: JIRA per
   `references/jira.md` §Transitions; **GitHub = no-op with a note** —
   issues have no status field; close-on-merge rides `Closes #N`.
3. **Honest state**: a ticket that fails, halts, or stays held mid-run
   legitimately remains In Progress — work started; never revert it to
   mask a failure.

Never block the calling workflow on this op (§MCP Availability Guard
applies — JIRA unavailable → report the transition skipped).

### Update (commit progress)

After pushing commits that reference a ticket (and before PR creation, to
keep the tracker current):

1. **Determine the ticket ref** — never guess: GitHub `#(\d+)` in the commit
   message first; then JIRA `[A-Z]+-\d+`; then branch name (`123` → `#123`,
   `PROJ-123` → `jira`, §Platform Detection point 2); else ask the user.
2. **One progress comment per commit push** — mechanics, idempotency check
   (skip when a comment with that commit hash exists), and the house
   comment template: `references/phases/update.md`. JIRA unavailable →
   report skipped (§MCP Availability Guard), never block the calling
   workflow.

### Close (post-merge)

After a PR merges, transition its tracker ticket **exactly once** and add a
merge comment. Driven by `worktree-pipeline-skill` / the PR merge flow —
never by PR creation itself.

1. **Detect the ticket ref** from the merged PR: title/body key patterns,
   branch name, or commit footers (`gh pr view <num> --json
   title,body,headRefName`). No key found → report and stop (never guess).
2. **Check current status first** — already done-category → skip the
   transition, still add/verify the merge comment. This is the
   transition-once guard.
3. **Transition + merge comment** — mechanics, the merge-comment template,
   and failure isolation (a comment failure must not trigger a second
   transition attempt): `references/phases/close.md`.

### Git plumbing (ticket keys ↔ branches ↔ commits)

The general rule: the ticket key rides the branch name first (parses back out
trivially) and the commits carry it in footers (`Refs: <key>` to reference,
`Closes: <key>` to close on merge) — this feeds §Update and §Close detection
and the plan-file conventions downstream skills consume. Per-platform key
formats and branch patterns: side files (`github.md` §Ticket key format,
`jira.md` §Ticket key format & git plumbing).

## MCP Availability Guard

**Canonical policy home** — other skills' §MCP Availability Guard sections
point here; edit the policy only in this file.

The `atlassian` MCP server is **disabled by default** (opt-in). Before any
`atlassian_*` call, check whether the tools exist in your tool list:

- If `atlassian_*` tools are absent, do NOT attempt or hallucinate them.
- Interactive: offer per-project enable via `opencode-repo-setup-skill`
  (writes the FULL atlassian server entry into the project `opencode.json` —
  a bare `{"disabled":false}` stub is inert; effective next session, so this
  session must degrade).
- Fallback: REST with an API token — `curl -u email:token` against
  `https://<site>.atlassian.net` (discover cloudId unauthenticated: `curl
  https://<site>.atlassian.net/_edge/tenant_info`); scoped tokens use
  `api.atlassian.com/ex/jira/{cloudId}`, unscoped use site-direct
  `/rest/api/3/`.
- No credentials/headless: report the JIRA operation as skipped — never block
  the calling workflow.

GitHub-side operations are unaffected (gh or git per the tooling tier).
Per-operation REST endpoints: `references/jira.md` §REST fallback endpoints.

## Boundaries

**Ticket-vs-plan** (this skill is upstream of `worktree-pipeline-skill`):

1. A ticket must be executable by someone who never saw the discussion —
   anything less belongs in comments, anything more belongs in the PLAN.
2. Every PLAN references exactly one ticket ID; the ticket's Acceptance
   Criteria become the PLAN's definition of done. The plan inherits AC; it
   never rewrites them.
3. Technical Notes (implementation considerations) belong to the PLAN, never
   the ticket body.

**Workflow skills stay external**: `worktree-pipeline-skill`,
`wayfinder-skill`, `dev-uat-promotion-skill` consume this skill; their
orchestration is never part of it.

## Agent behavior rules

- **Ask, don't invent**: missing required field → batched question round.
- **Search first**: search existing tickets before submit (the agent-side
  equivalent of the form's search-first attestation).
- **Parity of required-ness**: the required set equals the form's
  `validations.required`.
- **Headless/CI**: no asks — proceed only if every required field came in the
  original request; otherwise fail naming the missing fields.

> **Harness binding — interactive prompts** (AGENTS.md §Portability
> contract): OpenCode — `question` tool. Claude Code — `AskUserQuestion`.
> Other/none — batch the same fields in a plain reply; proceed per the
> Headless/CI rule if no answer comes.
