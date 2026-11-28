# Phase: Close — post-merge transition mechanics for ticketing-skill

> **Load rule:** read when the lifecycle op is **close** (SKILL.md
> §Lifecycle). This file carries the transition mechanics, the merge-comment
> template, and failure isolation. The transition-once guard and ref
> detection are SKILL.md §Close (contract); platform transitions and
> endpoints are `references/github.md` / `references/jira.md`.

## Mechanics

1. Status check first (SKILL.md §Close): already done-category → skip the
   transition, still add/verify the merge comment.
2. **Transition** to the done-category target: GitHub = no-op (close-on-merge
   rides `Closes #N` in the merged commits); JIRA per
   `references/jira.md` §Transitions (pick target by priority:
   `Done` → `Closed` → any `statusCategory == "done"`).
3. **Merge comment** — template below; GitHub via `gh issue comment`, JIRA
   per the side file.
4. **Failure isolation**: a comment failure must not trigger a second
   transition attempt; log and continue where possible.

## Merge comment template

```markdown
## Pull Request Merged
### Status Update
- **Previous**: <from> → **New**: <to>
### Merge Details
- **PR**: #<num> — <title> (<merge SHA>)
### Files Changed
- <summary or count>
```
