"""contract_adapter.py — US-4.1 source-swap adapter.

Converts the embedded proposed-schema JSON (``schema_extractor`` output, stored
at ``ppt/template_schema.json``) into the **sidecar fingerprint-contract shape**
that ``ppt_builder``'s layout-resolution code already consumes
(``_resolve_layout_by_fingerprint``, ``servable_slide_types``,
``_content_placeholders_stacked``).

This is a **bridge** (architecture review M6): it intentionally *reduces* the
embedded schema to the sidecar shape, dropping the rich polygon/font/runs
fields. The v2 intake that exposes those (coordinate placement) is US-4.6.

Derivation rules mirror ``template_introspector`` exactly (architecture review
M3), so adapter output is byte-equivalent to ``get_contract`` on the
layout-selection fields — ``fingerprint`` exact, ``content_area_in2`` within
sub-1% (polygon clamp/round noise), ``name``/``index`` exact. ``slide_size`` and
``theme`` are best-effort; ``theme`` is NOT load-bearing (charts use a hardcoded
palette + the live master theme via ``add_slide``).

Public API
----------
    embedded_schema_to_contract(schema_dict) -> contract_dict
"""
from __future__ import annotations

from typing import Any, Dict, List

# US-4.6 (m2): the polygon/EMU primitives now live in the shared pure
# ``geometry`` module. Imported here (and re-exported) so this module's public
# surface and internal call sites are unchanged (parity-preserving relocation).
from geometry import _EMU_PER_INCH, denormalize_polygon  # noqa: F401 (re-exported)

# Embedded ``placeholder_type`` -> sidecar canonical type (architecture review
# M3). Mirrors ``template_introspector._TYPE_CANONICAL`` via the embedded enum.
#
# M3-A: ``ORG_CHART`` collapses to embedded ``"chart"`` alongside true ``CHART``
# (schema_extractor._PLACEHOLDER_TYPE_MAP). We map ``"chart" -> "OBJECT"`` to
# match the sidecar's ``ORG_CHART -> "OBJECT"`` (ORG_CHART contributes to
# content_area). True-CHART placeholders are rare in templates and absent from
# the bundled one, so parity holds there.
_CANONICAL_MAP: Dict[str, str] = {
    "title": "TITLE",
    "subtitle": "SUBTITLE",
    "body": "OBJECT",      # BODY/OBJECT/VERTICAL_* unify to OBJECT (sidecar parity)
    "picture": "PICTURE",  # PICTURE + BITMAP
    "chart": "OBJECT",     # M3-A: match sidecar ORG_CHART -> OBJECT
    "table": "TABLE",
    "media": "MEDIA",
}

# Embedded ``placeholder_type`` values that are template "chrome" — dropped from
# the fingerprint (mirrors ``template_introspector._CHROME_TYPES``).
_CHROME_TYPES = {"date", "slide_number", "footer", "header"}

# Canonical types that count toward the content body area
# (mirrors ``template_introspector._CONTENT_AREA_TYPES``).
_CONTENT_AREA_TYPES = {"OBJECT"}


def _to_canonical(placeholder_type: Any) -> str:
    """Map an embedded ``placeholder_type`` to the sidecar canonical name.

    An unknown/``None`` placeholder_type -> ``"OBJECT"`` (generic content),
    mirroring the sidecar's ``None -> OBJECT`` convention.
    """
    if placeholder_type is None:
        return "OBJECT"
    return _CANONICAL_MAP.get(placeholder_type, "OBJECT")


def _placeholder_components(components: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """Return the placeholder components used to build the contract.

    Mirrors the sidecar's ``layout.placeholders`` view as closely as the
    embedded data allows. NOTE (architecture review M3): the embedded extractor
    flattens group children into the component list, and the component dict
    carries no group-nesting marker, so a placeholder nested in a group cannot
    be distinguished from a top-level one here (the sidecar's
    ``layout.placeholders`` excludes group-nested ones). This is a known
    best-effort limitation; the bundled template has no grouped placeholders, so
    parity holds, and the synthetic-fixture parity test characterizes any drift.
    """
    return [c for c in components if c.get("type") == "placeholder"]


def _derive_fingerprint(components: List[Dict[str, Any]]) -> List[str]:
    """Build the sidecar-style fingerprint (canonical types, chrome dropped)."""
    fp: List[str] = []
    for c in _placeholder_components(components):
        pt = c.get("placeholder_type")
        if pt in _CHROME_TYPES:
            continue
        fp.append(_to_canonical(pt))
    return fp


def _build_placeholders(
    components: List[Dict[str, Any]], dims: Dict[str, Any]
) -> List[Dict[str, Any]]:
    """Build sidecar-style placeholder records (non-chrome only).

    ``idx`` is omitted (the renderer does not consume it; the sidecar carries it
    only for Capability B reuse, which reads the live master, not this record).
    """
    records: List[Dict[str, Any]] = []
    for c in _placeholder_components(components):
        pt = c.get("placeholder_type")
        if pt in _CHROME_TYPES:
            continue
        left_in, top_in, width_in, height_in = denormalize_polygon(c.get("polygon") or [], dims)
        records.append({
            "name": c.get("name"),
            "type": _to_canonical(pt),
            "left_in": left_in,
            "top_in": top_in,
            "width_in": width_in,
            "height_in": height_in,
        })
    return records


def _derive_content_area(
    components: List[Dict[str, Any]], dims: Dict[str, Any]
) -> float:
    """Sum the area (inches^2) of OBJECT-canonical placeholders."""
    area = 0.0
    for c in _placeholder_components(components):
        pt = c.get("placeholder_type")
        if pt in _CHROME_TYPES:
            continue
        if _to_canonical(pt) in _CONTENT_AREA_TYPES:
            _, _, w, h = denormalize_polygon(c.get("polygon") or [], dims)
            if w and h:
                area += w * h
    return area


def _build_slide_size(dims: Dict[str, Any]) -> Dict[str, Any]:
    """Map embedded ``slide_dimensions`` -> sidecar ``slide_size`` shape.

    ``width_in``/``height_in`` are recomputed from EMU with the introspector's
    2-dp rounding (the embedded schema stores them at 4 dp) so the adapter's
    ``slide_size`` is byte-identical to ``template_introspector`` — keeping
    parity assertions exact. ``ratio`` reuses the embedded ``aspect_ratio``
    (both sides compute it via the same gcd-based ``_compute_ratio``).
    """
    w_emu = dims.get("width_emu") or 0
    h_emu = dims.get("height_emu") or 0
    return {
        "width_emu": w_emu,
        "height_emu": h_emu,
        "width_in": round(w_emu / _EMU_PER_INCH, 2),
        "height_in": round(h_emu / _EMU_PER_INCH, 2),
        "ratio": dims.get("aspect_ratio"),
    }


def _build_theme(schema: Dict[str, Any]) -> Dict[str, Any]:
    """Best-effort sidecar-shape theme.

    NOT load-bearing: the render path applies chart colors from a hardcoded
    palette (``_CHART_COLORS``) and inherits all other styling from the live
    slide master via ``add_slide``. Provided only for contract-shape completeness.
    """
    theme = schema.get("theme") or {}
    palette = theme.get("font_palette") or {}
    colors = {
        k: v for k, v in {
            "primary": theme.get("primary_color"),
            "secondary": theme.get("secondary_color"),
            "accent": theme.get("accent_color"),
            "background": theme.get("background_color"),
            "text": theme.get("text_color"),
        }.items() if v
    }
    return {
        "colors": colors,
        "fonts": {
            "major_latin": palette.get("heading"),
            "minor_latin": palette.get("body"),
        },
    }


def embedded_schema_to_contract(schema: Dict[str, Any]) -> Dict[str, Any]:
    """Convert an embedded proposed-schema dict to the sidecar contract shape.

    Pure (no I/O). Consumed by ``ppt_builder.get_render_contract`` (US-4.1). The
    layout-selection fields (``fingerprint`` / ``content_area_in2`` / ``name`` /
    ``index``) match ``template_introspector.get_contract``; ``slide_size`` and
    ``theme`` are best-effort.

    ``source_file`` / ``source_mtime`` are intentionally omitted — the renderer
    does not consume them, and ``get_render_contract`` does not cache (it reads
    the embedded JSON directly each call).
    """
    meta = schema.get("template_metadata") or {}
    dims = meta.get("slide_dimensions") or {}
    layouts: List[Dict[str, Any]] = []
    for layout in schema.get("slide_layouts") or []:
        comps = layout.get("components") or []
        layouts.append({
            "index": layout.get("layout_index"),
            "name": layout.get("layout_name"),
            "placeholders": _build_placeholders(comps, dims),
            "fingerprint": _derive_fingerprint(comps),
            "content_area_in2": round(_derive_content_area(comps, dims), 2),
        })
    return {
        "slide_size": _build_slide_size(dims),
        "theme": _build_theme(schema),
        "layouts": layouts,
    }
