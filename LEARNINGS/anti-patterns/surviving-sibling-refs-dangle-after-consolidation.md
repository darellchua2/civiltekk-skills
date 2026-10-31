# Surviving-sibling references dangle after family consolidation

- **Category**: anti-pattern
- **Confidence**: 0.85
- **Scope**: project
- **Date**: 2026-10-31
- **Ticket**: #679

## Symptom

Consolidating a skill family into a router (or merging any catalog entries)
fixes the absorbed set but leaves PERSISTING neighbors that reference absorbed
IDs. #679: `skills/cad-generation-skill/SKILL.md:72` referenced
`cad-step-parts-skill` and `skills/cad-dxf-skill/SKILL.md:30` referenced
`cad-sendcutsend-skill` — both absorbed into `cad-specialist-skill`. Neither
file was in the merge set, so no merge step touched them; the dangling refs
surfaced only via an arch-review repo-wide ID grep (PLANS/PLAN-679.md step
3.3).

## Fix / Rule

Before finalizing any consolidation/merge, grep the SURVIVING files (not just
the merge set) for every removed ID and repoint hits at the surviving
artifact: `grep -rn "<removed-id>" skills/ agents/ installer/ README.md
deploy/` scoped to the files that will continue to exist. Add the survivor
rewire as an explicit plan step BEFORE the deletion step.
