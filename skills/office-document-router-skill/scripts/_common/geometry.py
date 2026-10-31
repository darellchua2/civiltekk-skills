"""geometry.py — shared, pure polygon/EMU primitives (US-4.6, rev 2 / m2).

Co-locates the inverse pair :func:`normalize_polygon` (shape EMU → normalized
[0,1]) and :func:`denormalize_polygon` (normalized [0,1] → inches) plus the
shared ``_EMU_PER_INCH`` constant and ``_compute_ratio`` helper. Previously
these lived split across :mod:`schema_extractor` (normalize + ratio) and
:mod:`contract_adapter` (denormalize); relocating them here gives a single
source of truth imported by :mod:`schema_extractor`, :mod:`contract_adapter`,
and :mod:`ppt_builder` (architecture-review m2).

Stdlib-only: no ``pptx`` import, so this module is trivially unit-testable.
Public-ish API (names re-exported by the original modules for back-compat):

    normalize_polygon(shape, slide_w_emu, slide_h_emu) -> [{x,y}, x4]
    denormalize_polygon(polygon, dims) -> (left_in, top_in, width_in, height_in)
    compute_ratio(width_emu, height_emu) -> "W:H"
"""
from __future__ import annotations

import math
from typing import Any, Dict, List, Tuple

# Physical constant (EMU per inch). Single source of truth (was duplicated in
# schema_extractor / contract_adapter / template_introspector).
_EMU_PER_INCH = 914400


def _clamp_unit(v: float) -> float:
    return min(max(v, 0.0), 1.0)


def normalize_polygon(
    shape: Any, slide_w_emu: int, slide_h_emu: int
) -> List[Dict[str, float]]:
    """Return 4 normalized ``{x, y}`` points (TL -> TR -> BR -> BL, 0.0-1.0).

    Derived from the shape's ``left/top/width/height`` (EMU) divided by slide
    dimensions. Rectangular only in US-1.1 (non-rectangular vertices deferred to
    US-1.2). Values are clamped to [0, 1] and rounded to 6 decimals.
    """
    left = shape.left or 0
    top = shape.top or 0
    width = shape.width or 0
    height = shape.height or 0
    if slide_w_emu <= 0 or slide_h_emu <= 0:
        return [{"x": 0.0, "y": 0.0}] * 4
    x0 = _clamp_unit(round(left / slide_w_emu, 6))
    y0 = _clamp_unit(round(top / slide_h_emu, 6))
    x1 = _clamp_unit(round((left + width) / slide_w_emu, 6))
    y1 = _clamp_unit(round((top + height) / slide_h_emu, 6))
    return [
        {"x": x0, "y": y0},  # top-left
        {"x": x1, "y": y0},  # top-right
        {"x": x1, "y": y1},  # bottom-right
        {"x": x0, "y": y1},  # bottom-left
    ]


def denormalize_polygon(
    polygon: List[Dict[str, float]], dims: Dict[str, Any]
) -> Tuple[float, float, float, float]:
    """Denormalize a 4-point [0,1] polygon (TL, TR, BR, BL) to inches.

    Returns ``(left_in, top_in, width_in, height_in)`` rounded to 4 dp (mirrors
    ``template_introspector._inches``). Inverse of :func:`normalize_polygon`.
    """
    width_emu = dims.get("width_emu") or 0
    height_emu = dims.get("height_emu") or 0
    if len(polygon) < 4 or not width_emu or not height_emu:
        return 0.0, 0.0, 0.0, 0.0
    tl_x, tl_y = polygon[0]["x"], polygon[0]["y"]
    br_x, br_y = polygon[2]["x"], polygon[2]["y"]
    left_in = round(tl_x * width_emu / _EMU_PER_INCH, 4)
    top_in = round(tl_y * height_emu / _EMU_PER_INCH, 4)
    width_in = round((br_x - tl_x) * width_emu / _EMU_PER_INCH, 4)
    height_in = round((br_y - tl_y) * height_emu / _EMU_PER_INCH, 4)
    return left_in, top_in, width_in, height_in


def compute_ratio(width_emu: int, height_emu: int) -> str:
    """Return the simplest ``W:H`` integer ratio for the given EMU dimensions."""
    if height_emu <= 0:
        return f"{width_emu}:0"
    g = math.gcd(width_emu, height_emu)
    return f"{width_emu // g}:{height_emu // g}"


# Back-compat alias: the original private name was ``_compute_ratio`` in both
# schema_extractor and template_introspector. Re-exported here so existing
# call sites / imports keep resolving (parity-unchanged, US-4.6 m2).
_compute_ratio = compute_ratio


# ---------------------------------------------------------------------------
# US-4.6 Phase 0 (T2): target-size presets + ratio gate
# ---------------------------------------------------------------------------
# Canonical preset slide sizes (US-4.6 Decision 4). The aspect RATIO is what
# the no-op gate compares (m1) — these absolute sizes are the canonical render
# targets for each named ratio.
_PRESET_SIZES: Dict[str, Tuple[int, int]] = {
    "16:9": (12192000, 6858000),  # 13.333in x 7.5in widescreen
    "4:3": (9144000, 6858000),    # 10in x 7.5in standard
    "1:1": (6858000, 6858000),    # 7.5in x 7.5in square
}

# Accepted preset keys, case-insensitive (whitespace-trimmed).
_PRESET_ALIASES: Dict[str, str] = {k.lower(): k for k in _PRESET_SIZES}


def preset_keys() -> List[str]:
    """Return the supported preset aspect-ratio keys (e.g. ``["16:9", "4:3", "1:1"]``)."""
    return list(_PRESET_SIZES)


def resolve_target_size(spec: Any) -> Tuple[int, int]:
    """Resolve a target-size spec to ``(width_emu, height_emu)`` (US-4.6 T2).

    Accepted forms:
      - preset string: ``"16:9"`` / ``"4:3"`` / ``"1:1"`` (case-insensitive).
      - explicit dict in inches: ``{"width_in": 10, "height_in": 7.5}``.
      - explicit dict in EMU: ``{"width_emu": 9144000, "height_emu": 6858000}``.

    Raises ``ValueError`` on an unknown preset or a malformed/explicit dict
    (non-positive dims / missing keys) so the caller surfaces a clear error
    instead of rendering at a wrong size.

    A ``None`` spec is intentionally NOT handled here — the caller treats
    ``target_size is None`` as "native path" before calling this helper.
    """
    if isinstance(spec, str):
        key = _PRESET_ALIASES.get(spec.strip().lower())
        if key is None:
            raise ValueError(
                f"Unknown target_size preset '{spec}'. "
                f"Expected one of {sorted(_PRESET_SIZES)} or an explicit "
                "{'width_in', 'height_in'} / {'width_emu', 'height_emu'} dict."
            )
        return _PRESET_SIZES[key]

    if isinstance(spec, dict):
        w_emu = spec.get("width_emu")
        h_emu = spec.get("height_emu")
        if w_emu is None or h_emu is None:
            w_in = spec.get("width_in")
            h_in = spec.get("height_in")
            if w_in is None or h_in is None:
                raise ValueError(
                    "target_size dict must specify width_emu/height_emu or "
                    "width_in/height_in."
                )
            w_emu = int(round(float(w_in) * _EMU_PER_INCH))
            h_emu = int(round(float(h_in) * _EMU_PER_INCH))
        w_emu, h_emu = int(w_emu), int(h_emu)
        if w_emu <= 0 or h_emu <= 0:
            raise ValueError(f"target_size dims must be positive, got {w_emu}x{h_emu}.")
        return w_emu, h_emu

    raise ValueError(
        f"target_size must be a preset string or a dims dict, got {type(spec).__name__}."
    )


def aspect_ratios_match(
    w1: int, h1: int, w2: int, h2: int, tol: float = 0.005
) -> bool:
    """True when two sizes share the same aspect ratio within relative ``tol``.

    Used by the US-4.6 AC5 no-op gate (Decision 4 / m1): same ratio → native
    path regardless of absolute size. Compares ratios (w/h) by relative
    difference so a 10x5.625in 16:9 deck matches the 13.333x7.5in preset.
    Degenerate (zero-height) sizes only match another zero-height size.
    """
    if h1 <= 0 or h2 <= 0:
        return (h1 <= 0) and (h2 <= 0)
    r1, r2 = w1 / h1, w2 / h2
    denom = max(abs(r1), abs(r2))
    if denom == 0:
        return True
    return abs(r1 - r2) / denom <= tol
