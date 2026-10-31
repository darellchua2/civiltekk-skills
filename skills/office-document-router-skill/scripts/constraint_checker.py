"""Over-limit constraint checker for Capability B (pptx-template-modifier-skill).

Compares a slide's content needs against the template contract's
``content_area_in2`` and yields an over-limit verdict (issue #46). Reusable by
P4's layout cloning (#47).
"""
from __future__ import annotations

import logging
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict

# Per-skill vendored engine (#437): shared contract layer in scripts/_common.
_COMMON_SCRIPTS = Path(__file__).resolve().parent / "_common"
if str(_COMMON_SCRIPTS) not in sys.path:
    sys.path.insert(0, str(_COMMON_SCRIPTS))

from layout_contract import servable_slide_types  # noqa: E402

logger = logging.getLogger(__name__)

# Default text density: words per square inch of content placeholder. Calibrated
# from the standard density budget (~30-50 words in ~44 in² ⇒ ~0.8-1.1 w/in²).
DEFAULT_WORDS_PER_IN2 = 0.9

_MARKDOWN_RE = re.compile(r"\*\*|__|`")
_WORD_FIELDS = ("title", "subtitle", "body", "body_left", "body_right")


@dataclass
class Verdict:
    """Result of checking one slide against the template's capacity.

    ``cause`` classifies the outcome so the state machine can apply a clone
    policy (issue #47 / option A): ``"fits"`` | ``"missing"`` (no matching
    layout) | ``"over_limit"`` (content area exceeded) | ``"unknown"``.
    """

    fits: bool
    reason: str
    slide_type: str = ""
    needed_area_in2: float = 0.0
    available_area_in2: float = 0.0
    cause: str = "fits"

    @property
    def delta_in2(self) -> float:
        """Available minus needed (negative ⇒ over-limit)."""
        return round(self.available_area_in2 - self.needed_area_in2, 2)


def check_content_area(needed_in2: float, available_in2: float) -> Verdict:
    """Core comparison: does ``available`` content area satisfy ``needed``?"""
    fits = needed_in2 <= available_in2 + 1e-9
    reason = (
        "fits"
        if fits
        else f"over-limit: needs {needed_in2:.1f} in², available {available_in2:.1f} in²"
    )
    return Verdict(
        fits=fits,
        reason=reason,
        needed_area_in2=round(needed_in2, 2),
        available_area_in2=round(available_in2, 2),
        cause="fits" if fits else "over_limit",
    )


def estimate_needed_area(word_count: int, words_per_in2: float = DEFAULT_WORDS_PER_IN2) -> float:
    """Heuristic: convert a body word count to a needed content area (in²)."""
    if word_count <= 0:
        return 0.0
    return round(word_count / max(words_per_in2, 1e-6), 2)


def count_slide_words(slide_data: Dict[str, Any]) -> int:
    """Count visible-text words across a slide's on-slide text fields."""
    total = 0
    for field in _WORD_FIELDS:
        value = slide_data.get(field)
        if isinstance(value, str) and value.strip():
            total += len(_MARKDOWN_RE.sub("", value).split())
    return total


def evaluate_slide(
    slide_type: str,
    slide_data: Dict[str, Any],
    contract: Dict[str, Any],
    words_per_in2: float = DEFAULT_WORDS_PER_IN2,
) -> Verdict:
    """Full verdict for one slide: missing-layout check + content-area check.

    * Unknown / unservable ``slide_type`` ⇒ over-limit (layout missing).
    * Content types ⇒ compare an estimated needed area vs the layout's
      ``content_area_in2``.
    * Title / section / closing / chart (no body area) ⇒ always fit.
    """
    report = servable_slide_types(contract)
    info = report.get(slide_type)
    if info is None:
        return Verdict(
            False, f"unknown slide_type '{slide_type}'", slide_type=slide_type, cause="unknown"
        )
    if not info.get("available"):
        return Verdict(
            False,
            f"layout missing: {info.get('reason', 'unservable')}",
            slide_type=slide_type,
            cause="missing",
        )

    available = float(info.get("content_area_in2", 0))
    # Slides with no body/content placeholder (title, chart, …) always fit.
    if available <= 0:
        return Verdict(True, "no content-area constraint", slide_type=slide_type, cause="fits")

    needed = estimate_needed_area(count_slide_words(slide_data), words_per_in2)
    verdict = check_content_area(needed, available)
    verdict.slide_type = slide_type
    return verdict
