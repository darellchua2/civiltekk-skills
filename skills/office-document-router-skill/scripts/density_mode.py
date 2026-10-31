"""
density_mode.py
===============
Deck-wide content density governance.

Each density mode fixes a per-slide visible-text word budget. The agent **defaults
to ``standard`` for the first generation** (auto-downshifted to ``concise`` for
small content areas; a user-stated density intent from the first message is
honored) and may adjust the mode **post-generation** per the user's refinement
choice (see ``pptx-subagent`` Stage 5); the schema validator then emits
*warnings* on any slide whose visible text falls outside the budget.

Severity model
--------------
Density findings are **always non-fatal warnings** — even in ``strict=True``
mode. The agent sees the warning and self-tightens the prose; the validator
never blocks a render over a word-count budget. (Structural schema errors
remain fatal in strict mode as before.)

Counting semantics
------------------
Only on-slide visible text is counted: ``title``, ``subtitle``, ``body``,
``body_left``, ``body_right``. Explicitly **not** counted:

* ``notes`` — lives in the Notes pane, never renders on the slide.
* ``categories`` / ``series`` labels on ``chart_slide`` — numeric or temporal,
  not meaningfully constraining.

Markdown emphasis markers (``*`` / ``_`` / backticks) are stripped before
counting, since the rendered run does not carry them. Each CJK character
counts as one "word" (no inter-word whitespace in CJK scripts).

Public API
----------
    DENSITY_BUDGETS         — {mode: (min_words, max_words)}
    VALID_DENSITY_MODES     — tuple of valid mode keys
    DEFAULT_DENSITY_MODE    — "standard"
    WORD_COUNT_FIELDS       — fields summed into a slide's word total
    count_slide_words(slide_data) -> int
    validate_density(data, density_mode) -> list[DensityFinding]
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Any, Dict, List, Tuple

# Per-mode per-slide word budgets (min, max), inclusive on both ends.
DENSITY_BUDGETS: Dict[str, Tuple[int, int]] = {
    "concise":    (0, 10),
    "standard":   (30, 50),
    "text-heavy": (75, 150),
}
VALID_DENSITY_MODES: Tuple[str, ...] = tuple(DENSITY_BUDGETS.keys())
DEFAULT_DENSITY_MODE: str = "standard"

# Slide fields summed into the visible-text word total.
WORD_COUNT_FIELDS: Tuple[str, ...] = (
    "title", "subtitle", "body", "body_left", "body_right",
)

# Markdown emphasis/code markers stripped before counting — the rendered run
# does not carry them, so they shouldn't inflate the count.
_MARKDOWN_RE = re.compile(r"[*_`]+")

# CJK / Japanese kana / Hangul ranges — each character counts as one "word"
# because there is no whitespace separator between CJK "words".
_CJK_RE = re.compile(r"[\u4e00-\u9fff\u3040-\u30ff\uac00-\ud7af]")


@dataclass(frozen=True)
class DensityFinding:
    """A single out-of-budget slide finding.

    The schema validator wraps each finding into a non-fatal warning
    ``ValidationIssue``. Kept as a plain dataclass here so this module stays
    free of any dependency on ``schema_validator`` (no circular import).
    """

    slide_index: int
    words: int
    budget_min: int
    budget_max: int
    mode: str

    def is_over(self) -> bool:
        return self.words > self.budget_max

    def is_under(self) -> bool:
        return self.words < self.budget_min


def count_slide_words(slide_data: Dict[str, Any]) -> int:
    """Count visible-text words in a single slide dict.

    Markdown markers are stripped, then non-CJK text is whitespace-split and
    each CJK character is counted individually. Tokens that contain no
    alphanumeric character (em-dashes, hyphens, colons, bullets) are dropped so
    the body-text delimiter ``**Title** — Description`` does not inflate the
    count. Returns ``0`` when none of the counted fields carry a non-empty
    string.
    """
    total = 0
    for field in WORD_COUNT_FIELDS:
        value = slide_data.get(field)
        if not isinstance(value, str) or not value:
            continue
        cleaned = _MARKDOWN_RE.sub("", value)
        cjk_chars = len(_CJK_RE.findall(cleaned))
        # Replace CJK runs with spaces so they don't merge into one Latin
        # "word" when split on whitespace.
        non_cjk_text = _CJK_RE.sub(" ", cleaned)
        # Drop punctuation-only tokens (the body format uses ` — ` / ` - ` /
        # `: ` as bold-title/description delimiters; they are not words).
        latin_words = [
            tok for tok in non_cjk_text.split()
            if any(ch.isalnum() for ch in tok)
        ]
        total += cjk_chars + len(latin_words)
    return total


def validate_density(
    data: List[Dict[str, Any]],
    density_mode: str,
) -> List[DensityFinding]:
    """Return one finding per out-of-budget slide, or ``[]`` when all fit.

    Raises ``ValueError`` if ``density_mode`` is not a known mode key. Slides
    that are not dicts (structural breakage) are skipped — those are the
    schema validator's concern, not density's.
    """
    if density_mode not in DENSITY_BUDGETS:
        raise ValueError(
            f"unknown density_mode '{density_mode}' "
            f"(valid: {list(DENSITY_BUDGETS)})"
        )
    budget_min, budget_max = DENSITY_BUDGETS[density_mode]
    findings: List[DensityFinding] = []
    for index, slide_data in enumerate(data):
        if not isinstance(slide_data, dict):
            continue
        words = count_slide_words(slide_data)
        if words < budget_min or words > budget_max:
            findings.append(DensityFinding(
                slide_index=index,
                words=words,
                budget_min=budget_min,
                budget_max=budget_max,
                mode=density_mode,
            ))
    return findings
