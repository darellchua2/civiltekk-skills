# Generic content rewrites must run after anchor-specific edits (or use disjoint anchors)

- **Category**: anti-pattern
- **Confidence**: 0.9
- **Scope**: project
- **Date**: 2026-10-31
- **Ticket**: #680 (also hit in #679)

## Symptom

A scripted transform applies broad string swaps (e.g. old skill ID → new route
name) BEFORE anchor-specific rewrites whose anchor text contains the swapped
substring. The generic pass mutates the anchors; the specific pass then
assert-fails or silently no-ops. #680: `modifier.md`'s SLIDE_SKILL_DIR block
contained `pptx-generate-slide-skill`; the generic swap turned it into
`Route: SLIDES`, so the specific rewrite's exact anchor missed and the
mangled text (`export SKILL_DIR=...skills/Route: MODIFIER`) shipped until the
residual grep caught it. Same class in #679's srdf moveit2 reword.

**Cross-step form (#688):** the interference also happens ACROSS steps — a Phase-N blanket `sed` over a file list mutated anchor text that Phase-M (later) exact-match deletions depended on, silently defeating them (discovered 2 gate cycles later via a stacked duplicate var). A blanket sweep's file list must EXCLUDE files whose later steps carry exact-match anchors — or later steps must re-derive anchors from the post-sweep file state.

## Fix / Rule

In any multi-pass text transform: run ANCHOR-SPECIFIC rewrites first, generic
sweeps last — or make the generic patterns provably disjoint from the
specific anchors. Always finish with a residual grep for BOTH the generic
pattern's side effects (`skills/Route:`, mangled tokens) and the specific
anchors' expected replacements.
