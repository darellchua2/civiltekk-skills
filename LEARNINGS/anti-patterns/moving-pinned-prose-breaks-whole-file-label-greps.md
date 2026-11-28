# A whole-file label pin is satisfied by any line: moving pinned prose breaks it silently

- **Category**: anti-pattern
- **Confidence**: 0.9
- **Scope**: project
- **Date**: 2026-11-28

`tests/test_issue_template_byte_identity.bats` greps SKILL.md for the issue-form labels — any line of the file satisfies it, and two spaced forms ("Problem / use case", "Logs / screenshots") lived only in the rendering schema while the field spec carried drifted compact forms ("Problem/use case"). Moving the schema to a phase file failed the pin and surfaced the drift. Rule: before moving prose out of a pinned file, grep every pinned string against what remains and fix the source to the canonical form — never loosen or relocate the pin to fit the drift.
