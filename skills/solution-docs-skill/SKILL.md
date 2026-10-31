---
name: solution-docs-skill
description: >-
  Solution document ladder — one entry point for the Vision Document (IIBA),
  BRD (BABOK), SRS (IEEE 830, legacy PRD), and Technical Design Documents
  (architecture, ADRs). Routes each document task to the right specialist
  route and runs the shared discovery pipeline.
license: Apache-2.0
compatibility: opencode
category: Framework
---

# Solution Docs Router

One entry point for the solution document ladder. Identify the document, load
only the matched route's file, and follow it with the shared pipeline below.

Provenance: consolidated from civiltekk-requirements-specs-skill (itself
brd-creation + srs-creation, #604), technical-design-creation-skill, and
vision-creation-skill (#689). Per-route lineage notes live in route files.

## The document ladder (identity)

**Vision** (customer-facing) → **BRD** (sponsor/stakeholder scope) → **SRS**
(internal functional/technical scope) → **TDD** (engineering design) →
implementation. The BRD's Solution Requirements Summary feeds the SRS; the
SRS's functional requirements feed the TDD. If a user wants BRD + SRS,
produce the BRD first — its §3 becomes the SRS input.

## Routes (load exactly one)

| Task | Route | Read | Skip-when |
|------|-------|------|-----------|
| Customer-facing Vision Document (discovery output, sign-off) | `vision` | `references/routes/vision.md` | internal docs → srs/brd |
| Sponsor-level BRD (BABOK/IIBA "why") | `brd` | `references/routes/brd.md` | internal functional spec → srs |
| SRS (IEEE 830 "what"; legacy PRD routes here) | `srs` | `references/routes/srs.md` | sponsor scope → brd, engineering design → technical-design |
| Technical Design Document (architecture, ADRs) | `technical-design` | `references/routes/technical-design.md` | requirements → srs/brd |

Route detection: explicit > inferred (concern shape) > ask once. "Requirements
doc" ambiguous → ask once, then route. Route files carry the VALUES (templates,
naming, audience contracts); this router carries the METHOD.

## Shared pipeline (all routes)

1. **Discover/interview** — gather sections prompt-first; summarize and
   confirm before writing; "skip" keeps the section heading. Never emit a
   full draft unconfirmed. (Vision: capture client statements verbatim.)
2. **Draft naming + PLAN back-linkage** — brd/srs/technical-design drafts
   live at their route's draft path (`docs/brd/BRD-draft-{slug}.md`,
   `docs/srs/SRS-draft-{slug}.md`, `docs/technical-design/TDD-draft-{slug}.md`)
   with the header `**PLAN**: PLANS/PLAN-{key}.md _(filled when ticket is
   created)_`; `worktree-pipeline-skill` §6b links them after ticket
   creation. **Vision is exempt**: no draft/final rename, no ticket linkage —
   it keeps `docs/vision/VISION-{slug}.md` for life.
3. **Render dual outputs** per the `rendering` route of
   `office-document-router-skill` — **snapshot** HTML + .docx for
   brd/srs/technical-design; **living** HTML (regenerated per round) for
   vision. Image routing: delegate image interpretation to
   `image-analyzer-subagent`; never interpret inline.
4. **Return Contract** (all routes):

```
**Status:** [success | partial | failed]
**Output:** <draft path>
**Summary:** <document> created across N parts; written to <dir>
**Issues:** [blockers or "None"]
```

**Harness binding — interactive asks** (AGENTS.md §Portability contract):
OpenCode — `question` tool. Claude Code — `AskUserQuestion`. Other/none —
ask in a plain reply. Headless/CI: no asks — read the route from the
delegation prompt, use a documented default, or return `Status: partial`
with the gap.

## Hard rules

- Confirm before writing (pipeline step 1); the vision route additionally
  treats client-shared material as confidential and keeps tone non-technical.
- Large tabular artifacts (RTM >15 rows, data dictionary, requirement
  register) are `.xlsx` peer deliverables via the `xlsx` route of
  `office-document-router-skill` — linked, never inlined (srs route).
- Technical-design authoring is CodeGraph-grounded: validate architecture
  against the actual codebase before finalizing (the route owns the tool table).
- Each route file owns its template and audience contract; this router never
  restates them.

## Gates

- Zero-preload: only the matched route file enters context.
- Report shape complete before declaring done (Return Contract above).
- Peer deliverables (xlsx, wireframes, decks) are linked, never inlined.
