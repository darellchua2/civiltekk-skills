# ticketing-skill

One skill for the whole ticket lifecycle on **GitHub Issues** (the default)
or **JIRA** (opt-in) — create, start (in-progress), classify/label, update
from commits, close post-merge, and the ticket-key ↔ branch ↔ commit plumbing
that ties tickets to git.

Consolidates six former skills (#599): `ticket-creation-skill`,
`git-issue-labeler-skill`, `git-issue-updater-skill`,
`jira-git-integration-skill`, `jira-status-updater-skill`,
`jira-ticket-labeler-skill`. The method lives in
[`SKILL.md`](SKILL.md); platform values live in
[`references/github.md`](references/github.md) and
[`references/jira.md`](references/jira.md).

## Workflow

```mermaid
flowchart TD
    T["Ticket request"] --> P{"Platform? §Platform Detection"}
    T --> L{"Lifecycle op? §Lifecycle"}
    P -- "explicit: #N / 'GitHub issue'" --> G["github → references/github.md"]
    P -- "explicit JIRA only: 'JIRA' or PROJ-123 key" --> J["jira → references/jira.md"]
    P -- "no signal" --> D["default: github — announce, never ask"]

    L -->|create| C["§Create — field spec + rendering schema; mechanics in phases/create.md"]
    L -->|classify / label| CL["§Classify/Label — type + priority; PRs: exactly one semver label"]
    L -->|start| S["§Start — execution begins; check-first idempotent"]
    L -->|update| U["§Update — commit → progress comment, idempotent; phases/update.md"]
    L -->|close| X["§Close — post-merge transition, exactly once; phases/close.md"]
    L -->|plumbing| K["§Git plumbing — key ↔ branch ↔ commit footers"]

    C --> EP["single vs parent? ask at intake — epic = parent ticket<br/>(GitHub: Parent: #N, sub-issues verify-locally · JIRA: native)"]
    C --> HAND["multi-ticket? sequence handoff + blocked-by: refs<br/>→ /run-worktree-pipeline"]
    G --> GH{"gh available?"}
    GH -- "yes" --> FULL["tier 1 — full CRUD via gh"]
    GH -- "no" --> PR["tier 2 — prompt: install gh?"]
    PR -- "yes" --> INS["gh-cli-setup-skill → install + auth → tier 1"]
    PR -- "no" --> GF["tier 3 — git-only fallback:<br/>create = paste-ready body + web URL<br/>label / comment = skip with note<br/>close = Closes #N keyword on merge<br/>plumbing = full"]

    J --> JM{"atlassian MCP enabled?<br/>§MCP Availability Guard"}
    JM -- "yes" --> MM["MCP tools (discovery → create → transition)"]
    JM -- "no" --> MR["REST fallback — API token + curl,<br/>or report skipped (never block)"]
```

## What stays outside

| Concern | Owner |
|---|---|
| Branches, PLANs, execution, PR pipeline | `worktree-pipeline-skill` |
| Oversized-work planning as decision tickets | `wayfinder-skill` |
| Batch dev→uat promotion | `dev-uat-promotion-skill` — moved to the betekk org catalog in #667: `npx github:betekk/betekk-skills add dev-uat-promotion-skill` |
| Semver definitions, version bump, tagging, releases | `semantic-release-convention-skill` + release tooling |

This skill labels; it never versions. PRs get exactly one semver label
(`major`/`minor`/`patch`) derived from the PR title's Conventional Commit
prefix; issues get type + priority.

## Extending to another platform

Copy a side file's skeleton to `references/<platform>.md` — values only
(commands, vocabularies, key formats, endpoints), no method content. The
main skill routes unknown platforms through detect-and-ask.
