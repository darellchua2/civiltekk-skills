---
name: horseshoe-paper-writing-skill
description: "Submission-ready engineering papers via the Horseshoe Diagram Method — mirrored Intro/Conclusion, Methods/Results bridge, journal conventions. Triggers: horseshoe paper, journal paper draft."
license: Apache-2.0
compatibility: opencode
category: Academic & Research Writing
---

## What I do

Write submission-ready engineering papers via the **Horseshoe Diagram Method**: a paper is an inverted-U whose two open arms (Introduction, Conclusion) must mirror each other, joined by the evidence bridge (Methods → Results → Discussion).

## When to use me

"horseshoe paper", "journal paper draft" — any engineering/ML journal submission draft, revision, or review under this method.

## 1. The method (core)

Left arm (Intro) funnels INWARD: broad context → specific problem → literature gap → contributions/RQs. Bridge is the ONLY evidence: Methods, Results, Discussion. Right arm (Conclusion) flares OUTWARD: findings → implications → limitations → future work → broader context.

**The Mirror Principle (the one rule):** every claim/question/contribution in the Introduction MUST have a mirrored partner in the Conclusion — no new content in the Conclusion, only answers to Intro promises. Contributions answered in the SAME ORDER; RQ1..RQn answered in order. A reviewer must be able to fold the paper along the bridge and have each intro paragraph line up with its conclusion partner. (vs "hourglass": the horseshoe makes intro/conclusion drift visible and fixable.)

## 2. The seven-step workflow

1. Draft the LEFT ARM (promises, contributions, RQs) → 2. Draft the RIGHT ARM (answers, point-by-point mirror) → 3. Build the PAIRING TABLE (intro ¶ ↔ conclusion ¶) → 4. Draft the BRIDGE to connect each pair → 5. Abstract (compress the whole horseshoe, ~250 words) → 6. Front/back-matter (Practical Applications/Highlights, Data Availability, Author Contributions, Acknowledgments) → 7. MIRROR AUDIT.

**Never write the bridge first** — the arms define the contract; the bridge fulfills it.

## 3. Journal-submission section order (stable across ASCE/Elsevier/IEEE/Springer/MDPI; names vary by venue)

Abstract → Introduction → (Literature Review) → Methods → Results → Discussion → Conclusions → Practical Applications/Highlights (venue-dependent) → back-matter. Methods before Results; Discussion separate from Results unless venue merges them.

## 4. Mirror audit (mandatory before done)

Two-column pairing table (`section-templates/pairing-table.md`): Intro element ↔ Conclusion partner ↔ Bridge evidence § ↔ ✓. Rules: (1) every numbered contribution has a Conclusion partner — add one or delete the contribution; (2) no orphan RQs; (3) NO new content in Conclusion (new claim/dataset/citation = violation — move to bridge); (4) Abstract mentions every contribution; (5) Practical Applications cites the single best headline number. Run before submission, after EVERY revision, and during review-response (new analysis → bridge AND the relevant arm).

## 5. Evidence rules (condensed)

ML results report per-class metrics (precision/recall/F1), never accuracy-only. Implications quantify ("reduces X by 17%") or are cut. Limitations subsection always present. Generalization hedged to demonstrated scope.

## 6. Anti-patterns to reject (review checklist)

Methods-first writing · unmirrored contributions · orphan RQs · new content in Conclusion · missing Practical Applications/Highlights when required · accuracy-only reporting · no limitations subsection · vague implications · overstated generalization.

**Related:** `research-paper-generation-skill` (generation pipeline from codebases) · the `docx` route of `office-document-router-skill` (DOCX conversion) · `civiltekk-diagram-skill` (mermaid route).

> Removed 2026-09: the §3 section-by-section writing guide (per-section prose templates), §4 multi-venue reference-style catalogs, §6 diagramming conventions detail, §7 formula/equation typography rules, §8 table formatting walkthroughs, §9 folder layout, §13 example invocation transcript, ASCII reference figure — venue-specific mechanics the model knows; the method, workflow, audit, and anti-patterns above are the durable contract.
