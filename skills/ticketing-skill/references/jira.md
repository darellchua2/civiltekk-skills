# JIRA — platform values for ticketing-skill

> **Load rule:** read only when the resolved platform is `jira` (per
> SKILL.md §Platform Detection — the user explicitly says JIRA or gives a
> `PROJ-123`-style key; the repo using Atlassian tools alone never selects
> this file). It carries the VALUES — MCP tools, REST endpoints, taxonomy
> vocabulary, key formats. The METHOD (guards, lifecycle routing,
> idempotency contracts) lives in SKILL.md and never here. The MCP
> availability policy is SKILL.md §MCP Availability Guard (canonical
> home) — this file only lists endpoints. Values marked *verify locally*
> must be confirmed against the target site/project (schemes vary by JIRA
> version).
>
> **Contributors:** copying this file's skeleton is the extension path for a
> new tracker platform (`references/<platform>.md`) — values only, no method.

## MCP tools (discovery workflow)

Resolve in order — each feeds the next:

```
atlassian_getAccessibleAtlassianResources   → cloudId + site name
atlassian_getUserInformation                → account id (assignee)
atlassian_getVisibleJiraProjects --cloudId  → pick project key (ABC, PROJ, DA…)
atlassian_createJiraIssue --cloudId --projectKey --issueTypeName
                           --summary --description [--assignee_account_id]
                           [--parent <STORY-KEY>]   # Sub-task creation — *verify locally*
atlassian_getJiraIssue / atlassian_addCommentToJiraIssue
atlassian_getTransitions / atlassian_transitionJiraIssue
```

*Verify locally:* Atlassian MCP v1 tool schemas (e.g. the
`atlassian_createJiraIssue` assignee parameter) are not statically published;
v2 exposes `createJiraIssue` / `editJiraIssue`. Re-inspect the live server's
tool list when the atlassian MCP is enabled — until then, field-level edits
go through the REST endpoints below.

## REST fallback endpoints (§MCP Availability Guard)

Base: `https://<site>.atlassian.net` (unscoped token) or
`api.atlassian.com/ex/jira/{cloudId}` (scoped token). Auth:
`curl -u email:api-token`.

| Purpose | Endpoint |
|---|---|
| cloudId discovery (unauthenticated) | `GET https://<site>.atlassian.net/_edge/tenant_info` |
| own accountId | `GET /rest/api/3/myself` → `.accountId` |
| assign a ticket | `PUT /rest/api/3/issue/{key}/assignee` `{"accountId":"<id>"}` |
| create | `POST /rest/api/3/issue` |
| progress comment | `POST /rest/api/3/issue/{key}/comment` `{"body":"…"}` |
| available transitions | `GET /rest/api/3/issue/{key}/transitions` |
| transition | `POST /rest/api/3/issue/{key}/transitions` `{"transition":{"id":<id>}}` |

## Vocabulary

### Issue types

| Type | When to use |
|------|-------------|
| **Bug** | Errors, crashes, incorrect behavior, regressions — it worked before and broke |
| **Story** | User-facing features, new APIs — delivers user value ("as a… I want…") |
| **Task** | Technical debt, refactoring, configuration, documentation |
| **Epic** | Multi-sprint initiative, cross-cutting concern — only for large bodies |
| **Sub-task** | Child of Story/Task — always nested, never standalone |

Hierarchy: `Epic → Story/Task → Sub-task (Bug, Sub-task)`.

**Type keyword signals** (intent signals, semantic judgment applies):
- Bug — fix, error, broken, crash, fail, doesn't work, incorrect, regression
- Story — add, implement, create, new, feature, support, as a user I want
- Task — update, refactor, configure, migrate, document, upgrade, cleanup
- Epic — initiative, project, overhaul, migration, platform
- No match → default `Task`

### Priority field

| Priority | When to use |
|----------|-------------|
| **Highest** | Production outage, data corruption, active exploit — rare |
| **High** | Core functionality impaired, significant user impact |
| **Medium** | Default — standard request, bug with workaround |
| **Low** | Cosmetic, minor UX annoyance, nice-to-have |
| **Lowest** | Trivial — typo in docs, minor visual glitch |

**Priority keyword signals**:
- Highest — critical, urgent, system down, data loss, security, outage
- High — high priority, blocking, unusable, regression, broken
- Medium — medium, moderate, workaround, intermittent
- Low — low priority, minor, cosmetic, nice to have, nit, typo
- Lowest — trivial, whenever, backlog, far future
- No match → default `Medium`

> **In-skill sync contract:** the priority keyword list mirrors
> `references/github.md` (priority labels). Update both together.

### GitHub → JIRA mapping (cross-platform)

| GitHub label | JIRA type | | GitHub priority | JIRA priority |
|---|---|---|---|---|
| `bug` | Bug | | `priority: critical` | Highest |
| `enhancement` | Story | | `priority: high` | High |
| `documentation` / `good first issue` | Task | | `priority: medium` | Medium |
| no type label | Task (default) | | `priority: low` | Low |
| | | | (none) | Medium (default) |

### Components (optional, project-specific)

Patterns: by layer (`frontend`, `backend`, `api`, `database`) · by feature
(`auth`, `billing`, `search`) · by module (`user-management`, `reporting`) ·
by platform (`web`, `mobile`). Components are project entities — find
existing ones via `atlassian_search`; skip assignment when absent. *Verify
locally: component names are per-project.*

## Transitions (start / post-merge close)

### Close (done target)

Pick target by priority: `to.name == "Done"` → `"Closed"` → any
`to.statusCategory.key == "done"`
(jq: `.transitions[] | select(.to.name=="Done") | .id`). The
check-current-status-first / transition-exactly-once contract is SKILL.md
§Close (method, not repeated here). *Verify locally: some projects customize
priorities and transition names — `atlassian_getJiraIssueTypeMetaWithFields`
lists the project's available values.*

### Start (in-progress target)

Pick the start target by priority: any transition whose
`to.statusCategory.key == "indeterminate"` → `to.name == "In Progress"`
(jq: `.transitions[] | select(.to.statusCategory.key=="indeterminate") | .id`
— take the first match). The category selector is the portable form:
projects customize status names, not status categories. Method
(check-first, transition-once) is SKILL.md §Start; same endpoints as close
(`GET`/`POST /rest/api/3/issue/{key}/transitions`).

## Epic / parent grouping

- Create the epic with type `Epic` (or the project's hierarchical parent
  type), children with `--parent <EPIC-KEY>` (v3 `parent` field — the same
  parameter the MCP discovery workflow lists for sub-tasks). *Verify
  locally: team-managed vs company-managed projects differ in epic support.*
- Hierarchy per §Vocabulary: `Epic → Story/Task → Sub-task`.

## Attribution (author/assignee)

- Reporter defaults to the account behind the MCP token / REST credentials —
  automatic, no field needed.
- Assignee must be set explicitly by `accountId` (JIRA never assigns by
  display name or email): own accountId via `GET /rest/api/3/myself`; set
  via `PUT /rest/api/3/issue/{key}/assignee` with `{"accountId": "<id>"}` —
  the only guaranteed path.
- `atlassian_createJiraIssue` (v1, pinned) assignee parameter: **unverified —
  server absent** (2026-09-19 static inspection: Atlassian's supported-tools
  page documents v2 only — there the create tool is `createJiraIssue` with no
  published per-parameter schema and `editJiraIssue` is the documented
  field-edit path; the pinned v1 schema is not statically published).
  Re-inspect live when a project enables the atlassian MCP; until then use
  the REST PUT above, or MCP v2 `editJiraIssue` where v2 is enabled.

## Ticket key format & git plumbing

- Key: `PROJ-123` (`[A-Z][A-Z0-9]+-\d+`)
- Branch: `feature/PROJ-123-short-slug` — key first so it parses back out trivially
- Commit footers: `Refs: PROJ-123` (reference) / `Closes: PROJ-123` (close-on-merge) — feed SKILL.md §Update / §Close detection

## Description templates

- **Bug**: same sections as the GitHub bug body (Problem / Steps / Expected vs Actual / Environment / Logs / References)
- **Story**: `As a <who>, I want <what>, so that <why>` + acceptance-criteria checklist
- **Task**: Context (problem/solution) + acceptance criteria + scope
- Full creation template: `## Description` / `## Type` / `## Context` / `## Acceptance Criteria` (checkboxes) / `## Files to Modify` / `## Notes`
