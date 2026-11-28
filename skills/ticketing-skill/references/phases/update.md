# Phase: Update — progress-comment mechanics for ticketing-skill

> **Load rule:** read when the lifecycle op is **update** (SKILL.md
> §Lifecycle). This file carries the ref-to-artifact mechanics, the
> idempotency check, and the house comment template. The ref-detection
> order and the never-block rule are SKILL.md §Update (contract); platform
> commands/endpoints are `references/github.md` / `references/jira.md`.

## Mechanics

1. **Latest commit**: `git log -1 --format='%H %an %aI %s'`; files via
   `git diff-tree --no-commit-id --name-only -r HEAD`.
2. Post **one** progress comment on the ticket — GitHub via `gh issue
   comment <num> --body-file <file>`; JIRA per `references/jira.md`
   (§MCP Availability Guard / REST fallback endpoints).
3. **Idempotency**: one comment per commit push — skip if a comment matching
   that commit hash already exists.

## House comment template

Same shape every update so progress is diffable:

```markdown
## Progress Update - <YYYY-MM-DD at HH:mm (UTC offset)>

### Changes Made
- <subject-line bullets from commits>

### Statistics
- **Commits**: <n> · **Files changed**: <n> (+<adds>/−<dels>)

### Commit Link
- [<short-hash>]($REPO_URL/commit/<sha>) — <subject>

### Files Changed
- <paths>
```

Rules: real user + timestamp from `git log`, never invented; no
editorializing.
