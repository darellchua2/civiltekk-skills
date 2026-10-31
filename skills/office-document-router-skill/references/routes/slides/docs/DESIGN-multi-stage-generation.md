# Design Rationale: Multi-Stage Generation Pipeline

> **Issues #21 / #24** (Phase 1, Track C) + density-mode enhancement.
>
> This document captures the **design rationale** — *why* generation is split
> into stages. The **current, authoritative pipeline spec** lives in
> `pptx-subagent.md` (Stages 0–5). This doc is kept for the reasoning that isn't
> obvious from reading the prompt alone.

---

## 1. Why multi-stage

Generating the **entire** `slide_data_list` JSON in a single LLM pass degrades as
slide count grows: titles drift, flow breaks, topics overlap, and notes thin out.
Splitting generation into stages lets each stage focus on one concern, and gives
a human (or self-critique) a cheap checkpoint **before** expensive detail work.

---

## 2. Current pipeline (6 stages)

The pipeline has evolved beyond the original 3-stage design. The authoritative
spec is in `pptx-subagent.md`:

```
Stage 0  Understand + calibrate to house note style
Stage 1  Outline        (plain text, one entry per slide)
Stage 2  Density Mode + Critique / Interactive Checkpoint
Stage 3  Detail + JSON  (full slide_data_list, schema-validated, density-aware)
Stage 4  Resolve + Render (resolvers fill placeholders, then generate_ppt_from_data)
Stage 5  Return result
```

**What was added since the original 3-stage design (#21/#24):**
- **Stage 0** — note-style calibration (reads 2–3 real template notes to match the house presenter-script style).
- **Stage 2 density modes** — the interactive checkpoint now does **two things in one `question` call**: picks a deck-wide density mode (`concise` / `standard` / `text-heavy`) AND approves/edits the outline. The mode fixes a per-slide visible-text word budget (`density_mode.py`); the validator emits non-fatal warnings on out-of-budget slides. See `pptx-subagent.md` Stage 2 + `SKILL.md` "Density Modes".
- **Stage 4 / Stage 5 split** — resource resolution is now an explicit, separate pre-render pass (`resolve_slide_data_list()`).

---

## 3. Autonomous vs interactive (the core design tension)

OpenCode **subagents run headless**: a single prompt → an autonomous run → a
single result. They **cannot pause mid-run** to ask the user a question.

| Mode         | When                                          | Behaviour                                                                 |
|--------------|-----------------------------------------------|---------------------------------------------------------------------------|
| Autonomous   | default; any subagent invocation              | Stage 2 = LLM self-critique + default `standard` density. No human pause. |
| Interactive  | only when `pptx-subagent` is the **primary** conversation agent | After Stage 1, the outline + density mode are surfaced in a single `question` call; Stage 3 proceeds only after both answers. |

The agent detects its context: if it is the primary agent with a live user
turn-loop, it offers the checkpoint; otherwise it uses autonomous mode. When in
doubt, it falls back to autonomous — **never hangs** waiting for input.

### Two-call fallback for subagent context
If an orchestrating agent wants a human checkpoint while invoking `pptx-subagent`
as a subagent, it can use a **two-call** pattern:
1. First call → agent returns the **outline artifact only** (Stage 1).
2. Orchestrator surfaces the outline to the user, collects edits + a density mode.
3. Second call → agent resumes from the edited outline through Stages 3–5.

---

## 4. Outline artifact

The outline is persisted to a namespaced temp dir so it can be surfaced/edited
later (the foundation for the interactive checkpoint). `outline_store.py`
provides:

```python
save_outline(outline_text, deck_id=None, *, mode=None) -> Path  # persists, returns path
load_outline(path) -> str                                       # reads it back (incl. mode header)
load_outline_mode(path) -> Optional[str]                        # extracts recorded density mode
latest_outline() -> Optional[Path]                              # most recent artifact
cleanup_all() -> int                                            # clears the temp dir (auto-called after render)
```

The optional `mode` kwarg records the Stage 2 density choice as an HTML-comment
header (`<!-- mode: standard -->`) at the top of the artifact for traceability.
Artifacts live under `<tempdir>/opencode/pptx_pipeline/pptx_outline_<id>.md`
and are **auto-cleaned** after every successful render (`generate_ppt_from_data`
default `cleanup_temp=True`).

---

## 5. Critique rubric (Stage 2, autonomous branch)

The self-critique re-reads the outline against five lenses:
- **Consistency** — do titles tell one coherent story?
- **Flow** — does each slide set up the next?
- **Coverage gaps** — obvious missing context.
- **Redundancy** — slides that repeat each other.
- **Length** — right slide count for the ask.

The agent does **not** proceed to JSON until the revised outline is non-empty and
internally consistent.
