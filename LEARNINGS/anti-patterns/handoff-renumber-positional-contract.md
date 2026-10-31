# Retiring a HANDOFF pair renumbers positional args across three test files

- **Category**: anti-pattern
- **Confidence**: 0.85
- **Scope**: project
- **Date**: 2026-10-31
- **Ticket**: #680

## Symptom

Removing the HANDOFF1 pair (pptx-template-modifier → pptx-generate-slide,
#437) during #680 required renumbering HANDOFF2–6 → 1–5 in
`tests/test_skill_isolation.bats` — whose guard python unpacks the vars
POSITIONALLY (`sys.argv[1:11]`) — plus the mirror test
`test_requires_skills.bats` (TWO heredoc python blocks, one argv[14] config
index) and per-family tests that grep guards by NUMBER
(`test_code_review_inline_skill.bats` HANDOFF4, `test_requirements_inline_skill.bats`
HANDOFF6). First pass caught isolation + requires_skills but missed the two
per-family greps and one heredoc unpack; each surfaced as a separate red gate
cycle.

## Fix / Rule

Treat the HANDOFF guard vars as a positional contract: when adding/removing a
pair, grep `tests/` for `HANDOFF\d` and renumber EVERY occurrence (var
definitions, argv unpack arity, argv config-index offsets, and per-family
literal greps) in the same commit as the dependency-map edit. Prefer a
follow-up refactor to named args over positional to retire this class.
