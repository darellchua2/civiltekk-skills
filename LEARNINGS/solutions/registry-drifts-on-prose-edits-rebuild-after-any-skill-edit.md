# Registry regeneration triggers on SKILL.md prose edits, not just frontmatter

`installer/registry.json` drifted when #684 edited four SKILL.md bodies with
zero frontmatter changes — the AGENTS.md rule ("after ANY frontmatter change:
run `node installer/build-registry.mjs`") understates the trigger. The
registry embeds per-skill rosters/counts/parent mappings, so ANY skill-tree
or SKILL.md content change drifts it.

**Worse**: the #679/#680 consolidation merge (586e626) landed with a stale
registry (`skills: 113` vs 103 on disk — deleted docx/xlsx/rendering skills
still listed, `office-document-router-skill` missing), so main's own Release
CI failed the drift guard after merge. The guard catches it only at CI; a
local `node installer/build-registry.mjs --check` before push catches it
earlier.

**Rule**: run `build-registry.mjs` after ANY edit under `skills/` or
`agents/` — not just frontmatter — and treat `--check` as part of the local
gate for any PR touching those trees.

- **Confidence**: 1.0
- **Scope**: project
- **Summary**: registry.json embeds skill rosters/counts — prose edits drift it without touching frontmatter; #679/#680 merged with a stale registry and main's Release CI went red post-merge (586e626); run build-registry.mjs --check locally whenever skills/ or agents/ change (#684 red-fix round 1)
- **Date**: 2026-10-31
