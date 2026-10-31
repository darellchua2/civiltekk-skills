# Skill-tree moves are roster changes — carry registry regen + count literals in the same commit

- **Category**: anti-pattern
- **Confidence**: 0.9
- **Scope**: project
- **Date**: 2026-10-31
- **Ticket**: #679

## Symptom

Phase 2 of #679 moved 10 skills' files into a new router dir. The full bats
gate went red ×9 with one root cause: the committed `installer/registry.json`
and the six README count literals still described the pre-move roster.
`installer/init.mjs add --all` and `deploy/setup.sh` deploy steps failed on
the first registry entry whose `skills/<id>/SKILL.md` no longer existed
(`skill not found: autodesk-aps-skill`). A second, sneakier variant: a
gate-time `git checkout installer/registry.json` habit silently reverted the
post-Phase-3 regen, so the committed registry kept the subagent's 15
`requiresSkills` (pointing at deleted dirs) until the exit-gate sweep caught
it.

## Fix / Rule

Any commit that adds/removes/moves skill or agent directories IS a roster
change: regenerate `installer/registry.json` and update the README count
literals (the `readme_count_assert` contexts) IN THE SAME COMMIT — the
count-drift tests enforce disk↔registry↔README agreement at every commit, so
a split commit cannot go green. Never `git checkout` a generated artifact to
"clean up" before a gate run: if a regen diff exists, either commit it or
prove it is timestamp-only first.
