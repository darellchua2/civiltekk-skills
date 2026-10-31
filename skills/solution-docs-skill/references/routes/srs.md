# Route: SRS

**Load when:** the task creates or reviews the SRS — IEEE 830 internal "what" (functional requirements, acceptance criteria, NFRs, traceability). Legacy PRD language routes here.
**Skip when:** sponsor-level scope (Route: BRD), customer-facing Vision (Route: VISION), engineering design (Route: TECHNICAL-DESIGN).
**Values file:** this route IS the values file — the METHOD (route detection, discovery interview, confirm-before-write, rendering) lives in the router SKILL.md.

# SRS route (values)

Software Requirements Specification knowledge — the IEEE 830 internal "what" document. The router SKILL.md carries the METHOD (detect → route → interview → write → render); this file carries the VALUES for the `srs` route.

**Authority:** this route owns the IEEE 830 template, the `docs/srs/` naming convention, and the xlsx peer-artifact contract; the sibling `brd.md` route file owns the BABOK sponsor-level "why" (the two were formerly peer skills — the boundary is internal now).

**Back-compat:** the legacy triggers "create prd", "product requirement", "product requirement document", "product doc", "PRD" route to **this** `srs` route. PRD was the wrong label for BA→dev handoff; SRS (IEEE 830) is the proper-software-house standard.

## Audience

The SRS is **internal — for the development team**. It encodes tradeoffs, non-goals, MoSCoW priorities, build-vs-buy rationale, performance targets, and traceability that you would NOT put in front of a customer. The customer-facing equivalent is the Vision Document (Route: VISION).

## Interview part sequence (route `srs`)

Introduction → Overall Description → Specific Requirements → Supporting Information. The interview itself (title → iterate parts → confirm-before-write) is the host's shared method.

## SRS Template (IEEE 830)

Every SRS follows the IEEE 830 four-part structure. The header links to the PLAN file (filled when a ticket is created). Valuable content from the prior PRD template is preserved by mapping into the IEEE structure.

### Header

```markdown
# SRS: {Feature Name}

**Status**: Draft | In Review | Approved
**Author**: {name}
**Date**: {YYYY-MM-DD}
**Vision**: docs/vision/VISION-{slug}.md _(upstream customer-facing doc, if one exists)_
**PLAN**: PLANS/PLAN-{key}.md _(filled when ticket is created)_
```

---

## Part 1. Introduction

### 1.1 Purpose

Describe the problem this feature solves and why it matters now.

```markdown
## 1.1 Purpose

{What problem exists today? Who is affected? What is the cost of not solving it?}

**Example**: Users cannot reset their password if they lose access to their
registered email. Support receives ~50 tickets/month for manual password resets,
averaging 2 business days to resolve.
```

### 1.2 Scope

Define what is in and out of scope — explicit non-goals prevent scope creep.

```markdown
## 1.2 Scope

### In scope
- {Deliverable 1}
- {Deliverable 2}

### Out of scope (non-goals)
- {Explicitly excluded — may be future work}
- {What this feature deliberately does NOT do}
```

### 1.3 Definitions & Acronyms

```markdown
## 1.3 Definitions & Acronyms

| Term | Meaning |
|---|---|
| {term} | {definition} |
```

### 1.4 References

```markdown
## 1.4 References

- {Link/title — related Vision doc, design doc, research, competitor analysis}
- {Issue/ticket link}
```

### 1.5 Overview

One paragraph outlining how the rest of the SRS is organized.

---

## Part 2. Overall Description

### 2.1 Product Perspective (Background / Context)

```markdown
## 2.1 Product Perspective

{What led to this problem? What existing systems or decisions are relevant?
What prior attempts (if any) were made?}
```

### 2.2 Product Functions (Goals)

```markdown
## 2.2 Product Functions

### Goals
- {Goal 1 — what this feature must achieve}
- {Goal 2}

### Non-Goals
- {Explicitly out of scope}
```

### 2.3 User Characteristics (Personas & User Stories)

Identify who benefits and express requirements from their perspective.

```markdown
## 2.3 User Characteristics

### Personas
#### Persona 1: {Name} — {Role}
- **Context**: {When/where do they interact?}
- **Needs**: {What do they need to accomplish?}
- **Pain Points**: {What frustrates them today?}

### User Stories / Jobs-to-be-Done
- As a {persona}, I want to {action}, so that I can {outcome}.
- When {situation}, I want to {motivation}, so I can {expected outcome}.
```

### 2.4 Constraints

```markdown
## 2.4 Constraints

- {Regulatory, budgetary, timeline, or integration constraints}
```

### 2.5 Assumptions & Dependencies

```markdown
## 2.5 Assumptions & Dependencies

### Assumptions
- {something believed to be true}

### Dependencies
- {team, service, or external factor this depends on}
```

---

## Part 3. Specific Requirements

> This is the core of the SRS. Functional requirements carry **MoSCoW** priorities (Must/Should/Could/Won't) and per-requirement acceptance criteria.

### 3.1 External Interfaces

```markdown
## 3.1 External Interfaces

- {User interfaces, hardware, software, communication interfaces}
```

### 3.2 Functional Requirements

```markdown
## 3.2 Functional Requirements

### FR-1: {Requirement Name}
- **Description**: {What the system must do}
- **Priority**: Must | Should | Could | Won't (MoSCoW)
- **Acceptance**: {How to verify this requirement is met}

**Example**:
### FR-1: Password Reset via SMS
- **Description**: Users with a verified phone number can request a password
  reset code via SMS. The code expires after 10 minutes.
- **Priority**: Must
- **Acceptance**: User enters phone → receives 6-digit code → enters code →
  sets new password → redirected to login.
```

### 3.3 Performance Requirements

```markdown
## 3.3 Performance Requirements

- {Metric}: {Target} (e.g. "Password reset page loads < 2s on 3G")
```

### 3.4 Design Constraints

```markdown
## 3.4 Design Constraints

- {Architecture, technology, or standards the design must respect}

### Make vs Buy
- {Build internally vs use third-party — rationale}
```

### 3.5 Software System Attributes (Quality / NFRs)

```markdown
## 3.5 Software System Attributes

### Security
- {Constraint} (e.g. "Reset codes are single-use and hashed at rest")

### Reliability / Availability
- {Target}

### Accessibility
- {Standard} (e.g. "WCAG 2.1 AA compliant")

### Maintainability / Portability
- {Target}
```

### 3.6 Acceptance Criteria (feature-level)

"Done" at the SRS level — complements per-requirement acceptance in 3.2.

```markdown
## 3.6 Acceptance Criteria

- [ ] {Criterion 1 — high-level, testable}
- [ ] All functional requirements with priority "Must" are implemented
- [ ] All NFRs (3.3–3.5) are validated
```

---

## Part 4. Supporting Information

### 4.1 Success Metrics (KPIs)

```markdown
## 4.1 Success Metrics

| Metric | Baseline | Target | Measurement Method |
|--------|----------|--------|-------------------|
| {Metric name} | {Current value} | {Goal} | {How measured} |
```

### 4.2 Risks

```markdown
## 4.2 Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| {Risk} | High/Med/Low | High/Med/Low | {How to mitigate} |
```

### 4.3 Open Questions

```markdown
## 4.3 Open Questions

- [ ] {Question} — **Owner**: {who decides} — **Needed by**: {phase/date}
```

### 4.4 Timeline / Milestones

```markdown
## 4.4 Timeline / Milestones

| Milestone | Target Date | Dependencies |
|-----------|-------------|--------------|
| {Milestone} | {Date} | {Dependency} |
| Implementation complete | {Date} | Design approved |
```

### 4.5 Requirements Traceability Matrix (RTM)

> **Large tabular artifact — export as .xlsx.** When the RTM exceeds ~15 rows (requirement  test  stakeholder), produce it as `docs/srs/{slug}/SRS-{key}-rtm.xlsx` via `xlsx-specialist` and link it here; keep only the summary inline.

```markdown
## 4.5 Requirements Traceability Matrix

_See docs/srs/{slug}/SRS-{key}-rtm.xlsx for the full matrix._
```

---

## docs/srs/ Naming Convention

### Draft (during planning, before ticket exists)

```
docs/srs/SRS-draft-{kebab-slug}.md
```

- Slug derived from SRS title (e.g. "User Authentication" → `user-authentication`)
- Created by `requirements-specialist-subagent` during the discovery interview
- The `**PLAN**:` field in the header is `_(filled when ticket is created)_`

### Final (after ticket creation)

```
docs/srs/SRS-{ticket-key}.md
```

- Renamed via `git mv` by `worktree-pipeline-skill` §6b during PLAN authoring (preserves git history)
- If the draft was never committed (untracked on the new branch), a plain `mv` + `git add` is used instead

### Bidirectional Linkage

| Direction | Field | Location |
|-----------|-------|----------|
| SRS → PLAN | `**PLAN**: PLANS/PLAN-{key}.md` | SRS header (filled at rename time) |
| PLAN → SRS | `**SRS**: docs/srs/SRS-{key}.md` | PLAN header (injected by worktree-pipeline-skill) |

---

## Tabular Artifacts (peer deliverables)

Large tabular deliverables are exported as `.xlsx` via the `xlsx` route of `office-document-router-skill` / `xlsx-specialist-subagent`, **not** inlined:

| Artifact | Path | When |
|---|---|---|
| Requirements Traceability Matrix | `docs/srs/{slug}/SRS-{key}-rtm.xlsx` | >15 requirement rows |
| Data Dictionary | `docs/srs/{slug}/SRS-{key}-data-dictionary.xlsx` | entity/attribute tables |
| Requirement Register | `docs/srs/{slug}/SRS-{key}-register.xlsx` | large requirement lists |

Small tables stay inline in the Markdown. The `.xlsx` files are **peer deliverables linked from the SRS**, never embedded — this keeps a single editable source of truth per artifact.

---

## Rendering (route `srs`)

**Render dual outputs per the `rendering` route of `office-document-router-skill` (snapshot for SRS):**
- **Interactive HTML** — rendered once at wrap (`docs/srs/{slug}/SRS-{slug}.interactive.html`), snapshot (not living)
- **Word .docx** — formal deliverable for review/sign-off (`docs/srs/SRS-{slug}.docx`), auto-TOC + hyperlinked headers + section page-breaks

---

## Return Contract (route `srs`)

```
**Status:** [success | partial | failed]
**Output:** docs/srs/SRS-draft-{slug}.md
**Summary:** SRS created (IEEE 830) across 4 parts; written to docs/srs/
**Issues:** [blockers or "None"]
```
