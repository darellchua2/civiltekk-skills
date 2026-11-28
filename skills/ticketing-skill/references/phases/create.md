# Phase: Create — intake mechanics for ticketing-skill

> **Load rule:** read when the lifecycle op is **create** (SKILL.md
> §Lifecycle). This file carries the stage mechanics and the multi-ticket
> handoff. The field spec, rendering schema, and epic rule are SKILL.md
> §Create — the contract, pinned to the shipped templates; platform values
> are `references/github.md` / `references/jira.md`.

## Rendering schema (parity contract — mirrors the SKILL.md field spec)

One canonical schema, two renderings; variant selects sections; sections
mirror the form headings. GitHub bug body: `### Problem description` /
`### Steps to reproduce` / `### Expected vs Actual` / `### Environment` /
`### Logs / screenshots` / `### References`. GitHub feature body:
`### Problem / use case` / `### Proposed solution` / `### Alternatives
considered` (omit if none) / `### Acceptance criteria` (checklist) /
`### References`. JIRA description mapping per `references/jira.md`
§Description templates.

## Stage 1 — Classify

Variant from content: `bug` (broken, reproducible → bug template, repo form
`.github/ISSUE_TEMPLATE/bug_report.yml`) or `feature`/`task` (new capability
or contained work → feature template). Final type/label resolution happens
at classify/label (SKILL.md §Classify/Label); the variant here only selects
the template.

## Stage 2 — Intake

Batch one question round for every required field missing from the request.
Field labels are canonical — they match `templates/` verbatim (field spec:
SKILL.md §Create) so agent-created and human-created tickets are structurally
identical.

## Stage 3 — Validate

Required fields non-empty. Missing required → ask, not guess. Each sub-item
in a multi-ticket run gets its own intake round; a sub-item without
acceptance criteria fails validation.

## Stage 4 — Preview

Render title + body per the rendering schema (SKILL.md §Create), show the
user for confirmation or edits before any creation call.

## Stage 5 — Submit

After confirmation, create per the platform side file (gh commands / MCP-REST
flow). Prefix titles with the form's `title` prefix (`[Bug]: ` /
`[Feature]: `) so agent- and form-created tickets match triage filters.

## Sequence handoff (multi-ticket runs only)

End with the executable tickets in suggested order for
`/run-worktree-pipeline`, one-line rationale per position; order derivation
= user-stated dependencies > user-given order > content inference (always
labeled "inferred"); omit the umbrella parent.

When the user states dependencies, write `blocked-by: <ref>` as a plain body
line under a `### Dependencies` heading in the DEPENDENT ticket (bare refs:
`#458`, `PROJ-123`, `owner/repo#458`) so the pipeline's skip-guard enforces
the order.

## Editing an existing body

Fetch, append, write back — body edits REPLACE, never blindly append.
