---
name: civiltekk-requirements-specs-skill
description: >-
  Create and review requirements documents — BRD (BABOK/IIBA, the
  sponsor-level 'why') and SRS (IEEE 830, the internal 'what'). Triggers:
  create brd, business requirements, stakeholder requirements, business
  need, business requirements document, write a brd, create srs, software
  requirements, functional spec, feature spec, specification, write srs,
  srs doc, legacy 'create prd', product requirement, product requirement
  document, product doc, PRD.
license: Apache-2.0
compatibility: opencode
category: Framework
---

Consolidates brd-creation-skill + srs-creation-skill (#604). Alias: formerly
brd-creation-skill / srs-creation-skill.

## What I do

Turn an agreed direction (typically a signed Vision Document) into a
sponsor-level **BRD** (BABOK/IIBA) or a developer-ready **SRS** (IEEE 830)
via a prompt-first discovery interview:

1. **Detect the route** (§Routes) — explicit > inferred > ask-once.
   Explicit: the request names the document ("create brd", "business
   requirements", "stakeholder requirements" → `brd`; "create srs",
   "software requirements", "functional spec", "specification" → `srs`).
   Inferred: the concern shape (sponsor-level why, objectives, business
   value, transition requirements → `brd`; internal functional/technical
   scope, acceptance criteria, NFRs, traceability → `srs`). Ambiguous
   ("requirements doc") → ask once — one ask per run, then proceed on the
   answer.
2. **Load the route's values file** (`references/brd.md` /
   `references/srs.md`) and apply its template, naming convention, and
   paths.
3. **Run the shared pipeline** (§Discovery interview → §Draft naming &
   PLAN back-linkage → §Rendering) and return the §Return Contract.

## Document ladder

**Vision** (customer-facing, `vision-creation-skill`) → **BRD**
(sponsor/stakeholder scope, route `brd`) → **SRS** (internal
functional/technical scope, route `srs`) → **PLAN**. The BRD's Solution
Requirements Summary feeds INTO the SRS's detailed functional requirements.
If the user wants both, produce the BRD first — its §3 becomes the SRS
input.

## Side files (load rules)

| Read | When | Use |
|------|------|-----|
| `references/brd.md` | route `brd` | BABOK/IIBA 4-part template (Business Requirements / Stakeholder Requirements / Solution Requirements Summary / Transition Requirements), docs/brd/ naming + PLAN linkage, rendering paths, Return Contract |
| `references/srs.md` | route `srs` | IEEE 830 4-part template (Introduction / Overall Description / Specific Requirements / Supporting Information — prior PRD content mapped in), docs/srs/ naming + PLAN linkage, xlsx peer artifacts, rendering paths, Return Contract |

Side files carry VALUES only; this file carries the METHOD. A requirements
concern outside the BRD/SRS pair (customer-facing vision, technical design,
tickets/branches/PLANs) is not this skill's space — see §Boundaries.

## Routes

| Situation | Route |
|-----------|-------|
| "create brd", "business requirements", "stakeholder requirements", "business need", "business requirements document", "write a brd"; sponsor-level scope, success criteria/business value, transition requirements (migration/training) | `brd` |
| "create srs", "write srs", "srs doc", "software requirements", "functional spec", "feature spec", "specification"; detailed functional requirements, acceptance criteria, NFRs, traceability matrix | `srs` |
| Legacy "create prd", "product requirement", "product requirement document", "product doc", "PRD" | `srs` (PRD was the wrong label for BA→dev handoff; SRS (IEEE 830) is the proper-software-house standard — there is no prd→brd alias) |
| Ambiguous ("requirements doc") | ask once (§What I do step 1), then route |

## Discovery interview

Prompt-first, identical shape for both routes; only the part list differs
(the route's values file lists its sequence):

1. **Title & overview** — "What is the title and brief overview of the
   {business initiative | feature}?" (or read the upstream Vision if
   provided); derive a kebab-case slug from the title; confirm: "I'll use
   Title: '{title}', Slug: '{slug}'. Proceed?"
2. **Iterate parts** — for each part/section of the route's template:
   "Next: {Section} (e.g. 1.2 Business Objectives & Success Criteria |
   3.2 Functional Requirements). {Purpose}. What content?" Summarize what
   will be written ("Got it. Here's what I'll write: {summary}. Correct?")
   and confirm before moving on; "skip" keeps the section heading.
3. **Confirm-before-write** — present the summary (title, parts 1–4 with
   content, draft file path, optional xlsx artifacts) and ask "Proceed to
   write?"; write the draft only on confirmation — no → revise.

## Draft naming & PLAN back-linkage

- Drafts live at the route's draft path (`docs/brd/BRD-draft-{slug}.md` /
  `docs/srs/SRS-draft-{slug}.md`), created by
  `requirements-specialist-subagent` during the discovery interview, with
  the header `**PLAN**: PLANS/PLAN-{key}.md _(filled when ticket is
  created)_`.
- After ticket creation, `worktree-pipeline-skill` §6b (PLAN authoring)
  auto-detects the draft, prompts to link it, renames it to the
  ticket-keyed file (`BRD-{key}.md` / `SRS-{key}.md`) — `git mv` if the
  draft was committed, plain `mv` + `git add` if untracked — and injects
  the document path into the PLAN header: bidirectional linkage.

## Rendering

Render dual outputs per the `rendering` route of `office-document-router-skill` —
**snapshot** for both routes: interactive HTML rendered once at wrap +
Word .docx as the formal review/sign-off deliverable (exact paths in the
route's values file).

**Image routing:** if a referenced diagram/screenshot must be interpreted,
delegate to `image-analyzer-subagent` (do not interpret inline).

## Boundaries

- The two routes were formerly peer skills that cross-referenced each
  other as upstream/downstream ("detailed functional requirements → the
  SRS skill"; "the BRD feeds the SRS") — that boundary is internal now;
  the route table above is the boundary logic.
- Customer-facing vision → `vision-creation-skill`; technical design (TDD)
  → `technical-design-creation-skill`; tickets/branches/PLAN files →
  `ticketing-skill` / `worktree-pipeline-skill`.
- `requirements-specialist-subagent` is the agent that authors both
  documents (this skill is its template); it resolves the same route via
  its doc-type decision tree before loading this skill.

## Agent behavior rules

- Confirm before writing (§Discovery interview step 3); never emit a full
  draft unconfirmed; "skip" keeps the section heading.
- Large tabular artifacts (RTM >15 rows, data dictionary, requirement
  register) are `.xlsx` peer deliverables via the `xlsx` route of `office-document-router-skill` /
  `xlsx-specialist-subagent` — linked, never inlined (route `srs` only;
  see `references/srs.md`).
- Headless/CI: no asks — read the route from the delegation prompt, use a
  documented default, or return `Status: partial` with the gap.

## Return Contract

```
**Status:** [success | partial | failed]
**Output:** docs/{brd|srs}/{BRD|SRS}-draft-{slug}.md
**Summary:** {BRD (BABOK/IIBA) | SRS (IEEE 830)} created across 4 parts; written to docs/{brd|srs}/
**Issues:** [blockers or "None"]
```

> **Harness binding — interactive asks** (AGENTS.md §Portability contract):
> OpenCode — `question` tool. Claude Code — `AskUserQuestion`. Other/none —
> ask in a plain reply; headless/no-answer rule above applies.
