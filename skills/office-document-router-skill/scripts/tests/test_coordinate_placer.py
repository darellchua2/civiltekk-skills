"""Tests for coordinate_placer.py (US-4.6 Phase 2 — pure placement planner).

Covers:
  - denormalize_to_emu: AC3 round-trip within 1% (incl. edge polygons); the
    placement counterpart of geometry.normalize_polygon.
  - find_layout_components: the m9 layout_index join.
  - build_placement_plan: per-component target EMU + z_order stable sort (m6).
  - placement_categories: background / content / degraded grouping.
"""
from coordinate_placer import (
    build_placement_plan,
    denormalize_to_emu,
    find_layout_components,
    placement_categories,
)
from geometry import _EMU_PER_INCH, normalize_polygon


def _shape(left, top, width, height):
    from types import SimpleNamespace
    return SimpleNamespace(left=left, top=top, width=width, height=height)


def _norm(shape, w, h):
    return normalize_polygon(shape, w, h)


# ---------------------------------------------------------------------------
# denormalize_to_emu (AC3 round-trip)
# ---------------------------------------------------------------------------
class TestDenormalizeToEmu:
    def test_round_trip_within_1pct_at_target_dims(self):
        # Native 16:9 (10x5.625in); a 4x3in placeholder at (1in,0.5in).
        nat_w = int(10 * _EMU_PER_INCH)
        nat_h = int(5.625 * _EMU_PER_INCH)
        poly = _norm(
            _shape(int(1 * _EMU_PER_INCH), int(0.5 * _EMU_PER_INCH),
                   int(4 * _EMU_PER_INCH), int(3 * _EMU_PER_INCH)),
            nat_w, nat_h,
        )
        # Denormalize against a 4:3 target (10x7.5in) and re-normalize.
        tgt_w = int(10 * _EMU_PER_INCH)
        tgt_h = int(7.5 * _EMU_PER_INCH)
        left, top, w, h = denormalize_to_emu(poly, tgt_w, tgt_h)
        back = _norm(_shape(left, top, w, h), tgt_w, tgt_h)
        for orig, b in zip(poly, back):
            assert abs(orig["x"] - b["x"]) <= 0.01
            assert abs(orig["y"] - b["y"]) <= 0.01

    def test_degenerate_or_short_input(self):
        assert denormalize_to_emu([], 9144000, 6858000) == (0, 0, 0, 0)
        assert denormalize_to_emu([{"x": 0.1, "y": 0.1}], 0, 0) == (0, 0, 0, 0)

    def test_emu_values_are_integers(self):
        poly = _norm(_shape(0, 0, int(5 * _EMU_PER_INCH), int(3 * _EMU_PER_INCH)),
                     int(10 * _EMU_PER_INCH), int(7.5 * _EMU_PER_INCH))
        left, top, w, h = denormalize_to_emu(poly, int(10 * _EMU_PER_INCH), int(7.5 * _EMU_PER_INCH))
        for v in (left, top, w, h):
            assert isinstance(v, int)


# ---------------------------------------------------------------------------
# find_layout_components (m9 join)
# ---------------------------------------------------------------------------
class TestFindLayoutComponents:
    def test_matches_by_layout_index(self):
        schema = {"slide_layouts": [
            {"layout_index": 0, "components": [{"id": "a"}]},
            {"layout_index": 5, "components": [{"id": "b"}, {"id": "c"}]},
        ]}
        assert find_layout_components(schema, 5) == [{"id": "b"}, {"id": "c"}]

    def test_missing_index_returns_empty(self):
        assert find_layout_components({"slide_layouts": []}, 9) == []
        assert find_layout_components({}, 0) == []


# ---------------------------------------------------------------------------
# build_placement_plan (m6 z_order stable sort)
# ---------------------------------------------------------------------------
def _comp(cid, ctype, polygon, z_order, **extra):
    d = {"id": cid, "type": ctype, "name": cid, "polygon": polygon, "z_order": z_order}
    d.update(extra)
    return d


class TestBuildPlacementPlan:
    def test_per_component_target_emu(self):
        nat = int(10 * _EMU_PER_INCH)
        # A component occupying the left half.
        poly = [{"x": 0.0, "y": 0.0}, {"x": 0.5, "y": 0.0},
                {"x": 0.5, "y": 1.0}, {"x": 0.0, "y": 1.0}]
        plan = build_placement_plan([_comp("c1", "placeholder", poly, 0)], nat, nat)
        assert len(plan) == 1
        item = plan[0]
        assert item["left_emu"] == 0
        assert item["width_emu"] == nat // 2 or abs(item["width_emu"] - nat // 2) <= 1
        assert item["height_emu"] == nat

    def test_z_order_stable_sort(self):
        nat = int(10 * _EMU_PER_INCH)
        poly = [{"x": 0.1, "y": 0.1}, {"x": 0.2, "y": 0.1},
                {"x": 0.2, "y": 0.2}, {"x": 0.1, "y": 0.2}]
        comps = [
            _comp("front", "placeholder", poly, 5),
            _comp("back", "shape", poly, 0),
            _comp("mid", "image", poly, 2),
        ]
        plan = build_placement_plan(comps, nat, nat)
        ids = [item["component"]["id"] for item in plan]
        assert ids == ["back", "mid", "front"]

    def test_equal_z_order_preserves_source_order(self):
        nat = int(10 * _EMU_PER_INCH)
        poly = [{"x": 0.1, "y": 0.1}, {"x": 0.2, "y": 0.1},
                {"x": 0.2, "y": 0.2}, {"x": 0.1, "y": 0.2}]
        comps = [_comp(f"c{i}", "shape", poly, 1) for i in range(4)]
        plan = build_placement_plan(comps, nat, nat)
        assert [item["component"]["id"] for item in plan] == ["c0", "c1", "c2", "c3"]


# ---------------------------------------------------------------------------
# placement_categories (background / content / degraded)
# ---------------------------------------------------------------------------
class TestPlacementCategories:
    def _plan(self, comps):
        nat = int(10 * _EMU_PER_INCH)
        return build_placement_plan(comps, nat, nat)

    def test_background_content_degraded_split(self):
        poly = [{"x": 0.1, "y": 0.1}, {"x": 0.2, "y": 0.1},
                {"x": 0.2, "y": 0.2}, {"x": 0.1, "y": 0.2}]
        comps = [
            _comp("bg_shape", "shape", poly, 0),
            _comp("bg_img", "image", poly, 0),
            _comp("title", "placeholder", poly, 1, placeholder_type="title"),
            _comp("body", "placeholder", poly, 1, placeholder_type="body"),
            _comp("grp", "group", poly, 1),
            _comp("sm", "smartart", poly, 1),
        ]
        cats = placement_categories(self._plan(comps))
        bg_ids = {i["component"]["id"] for i in cats["background"]}
        ct_ids = {i["component"]["id"] for i in cats["content"]}
        dg_ids = {i["component"]["id"] for i in cats["degraded"]}
        assert bg_ids == {"bg_shape", "bg_img"}
        assert ct_ids == {"title", "body"}
        assert dg_ids == {"grp", "sm"}
