---
name: research-paper-generation-skill
description: >-
  Generate submission-ready research papers from codebase and verified
  experimental data — three framing strategies, reference validation, pandoc
  DOCX conversion. Triggers: research paper, academic paper, write paper, paper
  draft, journal submission, conference paper.
license: Apache-2.0
compatibility: opencode
category: Academic & Research Writing
---

## What I do

Generate submission-ready research papers from codebase + verified experimental data via an 8-step sequential pipeline. Steps feed each other — do not skip or reorder.

## When to use me

Turning a codebase/experiment results into a paper draft; regenerating a paper under a different venue framing.

## The 8-step pipeline

1. **Source data gathering** — extract verified facts from the codebase BEFORE writing: dataset metadata (counts, distribution, paths), model results (accuracy/recall/FAR/ECE/CIs) from eval outputs/JSON/`RESULTS-*.md`, code references with line numbers (`src/features.py:L42`), hyperparameters/thresholds. **NEVER fabricate numbers** — untraceable values become `[TODO: verify]` flagged to the user. Tools: `codegraph_explore`, `grep`, `read`, `explore` subagent for surveys.
2. **Framing decision** (below) — determines structure, tone, emphasis.
3. **Literature search** — delegate to `autoresearch-research-subagent` (web-only Tier 2) with contribution claims + framing + specific comparison needs; every reference needs authors/title/venue/year/DOI-or-URL. **Validate every reference via `webfetch`/`websearch`** before inclusion (common traps: plausible-but-nonexistent DOIs, wrong author lists, title drift from citation-chain paraphrasing).
4. **Draft** to `docs/research/papers/v<N>-<framing>/PAPER-<name>.md` — YAML metadata block + standard academic sections.
5. **B&W diagrams** — monochrome academic conventions: distinct line styles over color, labeled axes with units, vector output (SVG→PDF preferred).
6. **DOCX conversion** — `pypandoc.convert_file(...)` pipeline; OMML equations (never equation screenshots); tables as real tables.
7. **Verification checklist** (below) — mandatory.
8. **Report** — deliverables list + every `[TODO: verify]` flag.

## Framing decision tree (venue → framing)

| Venue family | Framing | Central contribution | Structure/emphasis |
|---|---|---|---|
| ML (NeurIPS/ICML/JMLR/PR) | `ml-methodology` | ML method comparison | RQ-driven; ablations + statistical rigor; application context ONE paragraph |
| Built environment/civil (NDT&E, Autom. in Constr.) | `framework-built-env` | Modular retraining framework | Problem→Framework→Protocol→Case Study; practical tone; field deployment |
| Application/system (IEEE Sensors, Applied Acoustics) | `application-system` | End-to-end system | System→Implementation→Deployment; product positioning OK |

Folder: `papers/v<N>-<framing>/`.

## Verification checklist (before declaring complete)

- Every quantitative claim traces to a codebase artifact (no fabrication)
- Every reference REAL + validated (DOI/stable URL resolves)
- Zero placeholders (`[TODO`, `[Author`, `[verify`, `TBD`, `XXX` all resolved)
- DOCX: real structure — paragraphs, tables, embedded images, OMML equations
- **Round-trip check**: DOCX → markdown via pypandoc; key percentages, headings, table contents match the source .md

**Related:** `horseshoe-paper-writing-skill` (the writing method this pipeline drafts under) · the `docx` route of `office-document-router-skill` (conversion engine detail) · `zai-media-subagent` (OCR/transcription of source material).
