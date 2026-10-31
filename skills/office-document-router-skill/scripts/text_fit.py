"""
text_fit.py
===========
Reactive per-textbox font auto-shrink (US-4.2).

python-pptx has **no text-layout / measurement engine** — it cannot tell how
tall a given string renders at a given font size inside a box. PowerPoint does
the real layout. This module therefore provides a **calibrated heuristic
estimator** that, given the raw text + a box geometry (inches) + a base font
size, decides whether the text fits and — if not — steps the font size down
(−2pt) until it does (down to an 8pt floor).

This module is deliberately **pure**: it imports only the standard library.
No ``pptx`` import, no I/O. This keeps the highest-risk logic (the estimate)
the most testable (``tests/test_text_fit.py`` runs with no PPTX fixture).

Model (see PLAN-GIT-60, decisions 2 + M2)
-----------------------------------------
* **Character width** — Latin char advance ≈ 0.5 × pt / 72 in; CJK ≈ 1.0 ×
  pt / 72 in. Widths are intentionally **over-estimated** (spaces counted at
  the full Latin ratio) so the estimate is conservative: when in doubt the
  estimator prefers to shrink, which is the safe side for overflow prevention.
* **Line count** — ``chars_per_line ≈ (width − 2×padding) × 72 / (ratio × pt)``;
  each ``\\n``-split segment wraps independently (≥1 line); blank lines count
  as one line.
* **Height** — ``est_height = lines × pt × line_spacing / 72
  + max(0, n_paragraphs − 1) × DEFAULT_PARA_SPACING_FACTOR × pt / 72`` (the
  inter-paragraph ``space_before``/``space_after`` reserve, arch-review M2).
* **Fit** — ``est_height ≤ height − 2×padding``.

Public API
----------
    FontFit                        — result dataclass
    ROLE_BASE_PT                   — conservative role ceilings (M1)
    estimate_lines(text, font_pt, width_in) -> int
    estimate_height_in(lines, font_pt, line_spacing, n_paragraphs) -> float
    fits_at_size(text, font_pt, box_w_in, box_h_in, line_spacing) -> bool
    fit_font_size(text, base_pt, box_w_in, box_h_in, ...) -> FontFit
"""

from __future__ import annotations

import math
import re
from dataclasses import dataclass
from typing import Tuple

# ---------------------------------------------------------------------------
# Tunable constants
# ---------------------------------------------------------------------------

MIN_FONT_SIZE_PT: float = 8.0
FONT_STEP_PT: float = 2.0
# BT-142 Phase 2.4a: raised from 1.2 → 1.3. PowerPoint body text typically
# renders at 1.25-1.45× em (ascent/descent leading); 1.2 systematically
# underestimated real rendered height (~70-85% per the review §3.3 root cause).
LINE_SPACING_DEFAULT: float = 1.3
TEXT_PADDING_IN: float = 0.1  # inner padding reserved on every side of a box

# Character advance ratios, in units of "em" (1 em = font_size_pt).
# Over-estimated on purpose (see module docstring) → conservative fit.
LATIN_RATIO: float = 0.5
CJK_RATIO: float = 1.0

# Inter-paragraph spacing reserve, as a fraction of 1 em per gap (arch-review
# M2). Replaced by the real value if/when ``schema_extractor`` captures
# space_before/space_after (currently out of scope).
# BT-142 Phase 2.4a: raised from 0.4 → 0.7. Real PowerPoint default
# ``spcBef``/``spcAft`` is typically 0.5-1.0 line (~0.5-1.0 em); 0.4 em
# systematically underestimated inter-paragraph gaps.
DEFAULT_PARA_SPACING_FACTOR: float = 0.7

# Conservative role ceilings (arch-review M1). Calibrated to the engine's
# historical shipping behaviour (the previous hardcode was Pt(14)/Pt(12)) so
# that when the schema/layout sources miss, the resolved base never exceeds a
# typical template's real size. Consumers map a placeholder role to a ceiling.
ROLE_BASE_PT = {
    "body": 14.0,
    "title": 28.0,
    "subtitle": 18.0,
}

# CJK / Japanese kana / Hangul ranges — mirrors density_mode._CJK_RE (kept
# local so this module stays import-free). Each CJK character occupies the
# full em width (twice a Latin char).
_CJK_RE = re.compile(r"[\u4e00-\u9fff\u3040-\u30ff\uac00-\ud7af]")


@dataclass(frozen=True)
class FontFit:
    """Outcome of a font-fit decision for a single textbox.

    ``base_source`` reports which tier of the resolution chain produced
    ``base_size_pt``: ``"schema"`` (embedded explicit size_pt), ``"layout_sample"``
    (the layout placeholder's sample-run size) or ``"role_ceiling"`` (the
    conservative default). ``adjusted`` is True only when the estimator actually
    shrank (``applied < base``); the caller writes an explicit run size only in
    that case (arch-review M3). ``fits`` is False when even the 8pt floor could
    not contain the text (the caller logs an overflow WARNING; it does not go
    below the floor).
    """

    applied_size_pt: float
    base_size_pt: float
    base_source: str
    adjusted: bool
    fits: bool
    lines_estimated: int


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

def _char_width_em(text: str) -> float:
    """Estimated rendered width of ``text`` in ``em`` units.

    CJK characters weigh ``CJK_RATIO``; every other character (incl. spaces —
    over-estimated on purpose) weighs ``LATIN_RATIO``. Returns 0 for empty
    text.
    """
    if not text:
        return 0.0
    cjk = len(_CJK_RE.findall(text))
    other = len(text) - cjk
    return cjk * CJK_RATIO + other * LATIN_RATIO


def _count_paragraphs(text: str) -> int:
    """Number of non-blank ``\\n``-split segments (≥1). Drives the M2 reserve."""
    if not text:
        return 1
    n = sum(1 for seg in text.split("\n") if seg.strip())
    return max(n, 1)


def _capacity_pt(width_in: float) -> float:
    """Wrapping capacity inside a box of ``width_in`` (pt), padded both sides."""
    return max((width_in - 2 * TEXT_PADDING_IN) * 72.0, 1.0)


# ---------------------------------------------------------------------------
# Public estimate primitives
# ---------------------------------------------------------------------------

def estimate_lines(
    text: str,
    font_pt: float,
    width_in: float,
    *,
    is_body_role: bool = False,
    bullet_indent_in: float = 0.3,
) -> int:
    """Estimate the wrapped line count of ``text`` at ``font_pt`` in ``width_in``.

    Each ``\\n``-delimited segment wraps independently (a segment always takes
    ≥1 line); a blank line counts as one line. Returns ≥1 for any non-empty
    text and 0 for empty text.

    BT-142 Phase 2.4a additions:
      - ``is_body_role`` (default ``False``): when ``True``, subtracts a
        ``bullet_indent_in`` allowance (default 0.3in) from the available
        width — bulleted body text has effective width reduced by the bullet
        char + indent (~0.25-0.5in). Without this, the estimator used the
        full placeholder width and underestimated wrap.
      - Longest-word overflow: a single long word (> available capacity)
        forces an extra break in reality. The previous model divided total
        string width by capacity, rounding up only by aggregate; now we also
        round per-segment up by the longest word's width when it exceeds cap.
    """
    if not text:
        return 0
    # Effective width after bullet indent (body role only).
    eff_width_in = max(0.5, width_in - (bullet_indent_in if is_body_role else 0.0))
    cap = _capacity_pt(eff_width_in)
    total = 0
    for seg in text.split("\n"):
        if seg == "":
            total += 1
            continue
        width_pt = _char_width_em(seg) * font_pt
        lines_for_seg = max(1, math.ceil(width_pt / cap))
        # Longest-word overflow: if the longest whitespace-delimited token
        # alone exceeds the line capacity, force at least one extra break.
        # (Conservative: real word-wrap may break mid-token, but PowerPoint
        # default is to keep tokens whole where possible.)
        tokens = seg.split()
        if tokens:
            longest_pt = max(_char_width_em(t) for t in tokens) * font_pt
            if longest_pt > cap:
                # The token forces at least ceil(longest/cap) lines on its own,
                # which the aggregate ceil may have undercounted.
                lines_for_seg = max(lines_for_seg, math.ceil(longest_pt / cap))
        total += lines_for_seg
    return max(total, 1)


def estimate_height_in(
    lines: int,
    font_pt: float,
    line_spacing: float,
    n_paragraphs: int = 1,
) -> float:
    """Estimated rendered height (inches) of ``lines`` at ``font_pt``.

    Adds an inter-paragraph spacing reserve (arch-review M2):
    ``max(0, n_paragraphs − 1) × DEFAULT_PARA_SPACING_FACTOR × font_pt / 72``.
    """
    text_height = lines * font_pt * line_spacing / 72.0
    gaps = max(0, n_paragraphs - 1)
    para_height = gaps * DEFAULT_PARA_SPACING_FACTOR * font_pt / 72.0
    return text_height + para_height


def fits_at_size(
    text: str,
    font_pt: float,
    box_width_in: float,
    box_height_in: float,
    line_spacing: float = LINE_SPACING_DEFAULT,
) -> bool:
    """True when ``text`` at ``font_pt`` fits inside the box (padded both axes)."""
    if not text or not text.strip():
        return True  # nothing to render → always fits
    lines = estimate_lines(text, font_pt, box_width_in)
    n_paras = _count_paragraphs(text)
    est_height = estimate_height_in(lines, font_pt, line_spacing, n_paras)
    return est_height <= box_height_in - 2 * TEXT_PADDING_IN


def fit_font_size(
    text: str,
    base_pt: float,
    box_width_in: float,
    box_height_in: float,
    *,
    line_spacing: float = LINE_SPACING_DEFAULT,
    min_pt: float = MIN_FONT_SIZE_PT,
    step_pt: float = FONT_STEP_PT,
    base_source: str = "role_ceiling",
) -> FontFit:
    """Resolve the font size at which ``text`` fits, stepping down from ``base_pt``.

    Starts at ``base_pt``; while it does not fit and the size is above
    ``min_pt``, steps down by ``step_pt`` (clamped to ``min_pt``). If it still
    does not fit at ``min_pt``, returns ``applied=min_pt`` with ``fits=False``
    (the caller logs an overflow WARNING and does not go below the floor).

    ``adjusted`` is True iff ``applied < base`` (the estimator actually shrank)
    — the caller writes an explicit run size only then (arch-review M3).

    Degenerate inputs (empty text, non-positive box) short-circuit to the base
    size unchanged with ``adjusted=False``.
    """
    if not text or not text.strip():
        return FontFit(base_pt, base_pt, base_source, False, True, 0)

    # Degenerate box geometry → cannot meaningfully fit-check; keep the base.
    if box_width_in <= 2 * TEXT_PADDING_IN or box_height_in <= 2 * TEXT_PADDING_IN:
        return FontFit(
            base_pt, base_pt, base_source, False, True,
            estimate_lines(text, base_pt, box_width_in),
        )

    size = base_pt
    while size > min_pt and not fits_at_size(
        text, size, box_width_in, box_height_in, line_spacing
    ):
        size = max(min_pt, round(size - step_pt, 2))

    # applied respects the readability floor (>= min_pt) above all. In the
    # normal case (base_pt >= min_pt — role ceilings are 14/28/18) ``size``
    # already stays within [min_pt, base_pt], so applied <= base (AC2). A
    # pathological sub-floor base (e.g. a 6pt layout sample run) yields
    # applied = min_pt > base: the floor wins over AC2's letter, since rendering
    # below the floor would defeat US-4.2's readability intent.
    applied = max(size, min_pt)
    final_fits = fits_at_size(text, applied, box_width_in, box_height_in, line_spacing)
    adjusted = applied < base_pt - 1e-9
    lines = estimate_lines(text, applied, box_width_in)
    return FontFit(applied, base_pt, base_source, adjusted, final_fits, lines)
