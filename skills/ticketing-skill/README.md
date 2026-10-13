# ticketing-skill

One skill for the whole ticket lifecycle on **GitHub Issues** or **JIRA** —
create, start (in-progress), classify/label, update from commits, close
post-merge, and the ticket-key ↔ branch ↔ commit plumbing that ties tickets
to git.

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
    P -- "explicit key / request" --> G["github → references/github.md"]
    P -- "PROJ-123 / explicit / MCP present" --> J["jira → references/jira.md"]
    P -- "ambiguous" --> A["ask once, then proceed"]

    L -->|create| C["§Create — intake · classify · validate · preview · submit"]
    L -->|classify / label| CL["§Classify/Label — type + priority; PRs: exactly one semver label"]
    L -->|start| S["§Start — execution begins; check-first idempotent"]
    L -->|update| U["§Update — commit → progress comment, idempotent"]
    L -->|close| X["§Close — post-merge transition, exactly once"]
    L -->|plumbing| K["§Git plumbing — key ↔ branch ↔ commit footers"]

    G --> GH{"gh available?"}
    GH -- "yes" --> FULL["tier 1 — full CRUD via gh"]
    GH -- "no" --> PR["tier 2 — prompt: install gh?"]
    PR -- "yes" --> INS["gh-cli-setup-skill → install + auth → tier 1"]
    PR -- "no" --> GF["tier 3 — git-only fallback:<br/>create = paste-ready body + web URL<br/>label / comment = skip with note<br/>close = Closes #N keyword on merge<br/>plumbing = full"]

    J --> JM{"atlassian MCP enabled?<br/>§MCP Availability Guard"}
    JM -- "yes" --> MM["MCP tools (discovery → create → transition)"]
    JM -- "no" --> MR["REST fallback — API token + curl,<br/>or report skipped (never block)"]

    C --> HAND["multi-ticket? sequence handoff + blocked-by: refs<br/>→ /run-worktree-pipeline"]
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
