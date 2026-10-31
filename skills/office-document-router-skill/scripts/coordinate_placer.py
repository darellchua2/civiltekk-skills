"""coordinate_placer.py — US-4.6 pure coordinate-placement planner.

NOTE (architecture pivot, code-review M1): this module is **reserved for the
future freeform-rebuild render path** (denormalize polygons → create OOXML
elements at exact EMU positions). The *current* US-4.6 implementation does NOT
consume it — it uses the geometry-mutation prep step
(:func:`ppt_builder._apply_target_resize`), which resizes the canvas + scales
master/layout shape geometry, then reuses the native ``add_slide`` loop. The
functions here are kept (and unit-tested in ``test_coordinate_placer.py``) as
the foundation for a future path that rebuilds shapes from scratch (e.g. for a
non-mutable source or a from-scratch layout). Do not assume the current render
path calls into this module.

The placement math is the resolution-independent inverse of
``geometry.normalize_polygon``; AC3 ("within 1%") is mechanical: a normalized
polygon round-trips losslessly when re-normalized against the target dims.

Public API
----------
    denormalize_to_emu(polygon, w_emu, h_emu) -> (left, top, width, height) EMU
    find_layout_components(schema, layout_index) -> [component, ...]   (m9 join)
    build_placement_plan(components, target_w_emu, target_h_emu) -> [plan_item]
"""
from __future__ import annotations

from typing import Any, Dict, List, Tuple


def denormalize_to_emu(
    polygon: List[Dict[str, float]], w_emu: int, h_emu: int
) -> Tuple[int, int, int, int]:
    """Denormalize a 4-point [0,1] polygon (TL, TR, BR, BL) to integer EMU.

    Returns ``(left, top, width, height)`` in EMU against the given target
    dimensions. The inverse placement counterpart to
    :func:`geometry.normalize_polygon`. Degenerate/short input -> ``(0,0,0,0)``.
    """
    if len(polygon) < 4 or not w_emu or not h_emu:
        return 0, 0, 0, 0
    tl_x, tl_y = polygon[0]["x"], polygon[0]["y"]
    br_x, br_y = polygon[2]["x"], polygon[2]["y"]
    left = int(round(tl_x * w_emu))
    top = int(round(tl_y * h_emu))
    width = int(round((br_x - tl_x) * w_emu))
    height = int(round((br_y - tl_y) * h_emu))
    return left, top, width, height


def find_layout_components(
    schema: Dict[str, Any], layout_index: int
) -> List[Dict[str, Any]]:
    """Return the rich component list for the layout matching ``layout_index``.

    Implements the architecture-review m9 join: after layout selection returns
    a layout object, the executor reads its ``layout_index`` and looks up the
    rich components here. Returns ``[]`` when no layout matches (caller degrades).
    """
    for layout in schema.get("slide_layouts") or []:
        if layout.get("layout_index") == layout_index:
            return layout.get("components") or []
    return []


def build_placement_plan(
    components: List[Dict[str, Any]], target_w_emu: int, target_h_emu: int
) -> List[Dict[str, Any]]:
    """Emit a z_order-sorted placement plan: per-component target EMU box.

    Each plan item carries the source ``component`` dict plus its denormalized
    ``left_emu``/``top_emu``/``width_emu``/``height_emu`` on the target canvas.
    Stable-sorted by ``z_order`` (python-pptx z-order == insertion order), so
    the executor inserts items in plan order to reconstruct stacking
    (architecture-review m6).
    """
    plan: List[Dict[str, Any]] = []
    for comp in components:
        left, top, w, h = denormalize_to_emu(
            comp.get("polygon") or [], target_w_emu, target_h_emu
        )
        plan.append({
            "component": comp,
            "left_emu": left,
            "top_emu": top,
            "width_emu": w,
            "height_emu": h,
            "z_order": comp.get("z_order", 0) or 0,
        })
    # Stable sort preserves source order for equal z_order (background/master
    # shapes authored earlier stay behind later content).
    plan.sort(key=lambda item: item["z_order"])
    return plan


def placement_categories(plan: List[Dict[str, Any]]) -> Dict[str, List[Dict[str, Any]]]:
    """Group a placement plan by render-relevant categories for the executor.

    Returns ``{"background": [...], "content": [...], "degraded": [...]}``:
      - background: master/layout non-placeholder shapes/images (placed first,
        behind content).
      - content: text/image/chart/table components the executor can re-create.
      - degraded: group/smartart/audio/video/multi-point shapes (warning + skip).
    """
    _DEGRADED_TYPES = {"group", "smartart", "audio", "video"}
    out: Dict[str, List[Dict[str, Any]]] = {
        "background": [], "content": [], "degraded": [],
    }
    for item in plan:
        comp = item["component"]
        ctype = comp.get("type")
        is_placeholder = comp.get("type") == "placeholder"
        # Non-placeholder shapes/images are background chrome; placeholders are
        # content slots; freeform textboxes are content too.
        if ctype in _DEGRADED_TYPES:
            out["degraded"].append(item)
        elif ctype in ("shape", "image") and not is_placeholder:
            out["background"].append(item)
        else:
            out["content"].append(item)
    return out
