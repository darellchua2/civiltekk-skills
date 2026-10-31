"""Tests for contract_adapter.py (US-4.1 source-swap adapter).

Covers the architecture-review M3 surface:
  - canonical map (incl. M3-A: chart/ORG_CHART -> OBJECT)
  - denormalize_polygon (inverse of schema_extractor.normalize_polygon)
  - fingerprint / content_area / placeholder derivation on synthetic components
  - PARITY: adapter output vs template_introspector.get_contract on the bundled
    template (fingerprint exact [multiset], content_area within sub-1%, name/
    index exact) — the Phase-1 gate.
"""
import pytest

from contract_adapter import (
    _CANONICAL_MAP,
    _to_canonical,
    denormalize_polygon,
    _derive_fingerprint,
    _derive_content_area,
    _build_placeholders,
    embedded_schema_to_contract,
)
from schema_extractor import extract_schema
from template_introspector import get_contract


# ---------------------------------------------------------------------------
# (1) Canonical map — M3-A (chart/ORG_CHART -> OBJECT)
# ---------------------------------------------------------------------------
class TestCanonicalMap:
    def test_body_maps_to_object(self):
        assert _to_canonical("body") == "OBJECT"

    def test_title_subtitle_picture_table_media(self):
        assert _to_canonical("title") == "TITLE"
        assert _to_canonical("subtitle") == "SUBTITLE"
        assert _to_canonical("picture") == "PICTURE"
        assert _to_canonical("table") == "TABLE"
        assert _to_canonical("media") == "MEDIA"

    def test_chart_maps_to_object_m3a(self):
        # M3-A: embedded "chart" (covers both CHART and ORG_CHART) -> OBJECT,
        # matching the sidecar's ORG_CHART -> OBJECT so it contributes to
        # content_area.
        assert _to_canonical("chart") == "OBJECT"

    def test_none_or_unknown_defaults_to_object(self):
        assert _to_canonical(None) == "OBJECT"
        assert _to_canonical("nonsense") == "OBJECT"

    def test_chrome_types_not_in_canonical_map(self):
        # chrome placeholder_types have no canonical mapping (dropped, not OBJECT)
        for chrome in ("date", "slide_number", "footer", "header"):
            assert chrome not in _CANONICAL_MAP


# ---------------------------------------------------------------------------
# (2) denormalize_polygon — inverse of normalize_polygon
# ---------------------------------------------------------------------------
class TestDenormalizePolygon:
    def test_round_trip(self):
        # 10in x 10in slide; placeholder at (1,1) size 4x3 -> normalized polygon
        dims = {"width_emu": 9144000, "height_emu": 9144000}  # 10in x 10in
        # TL, TR, BR, BL (anti-clockwise), normalized
        poly = [
            {"x": 0.1, "y": 0.1},   # left=1, top=1
            {"x": 0.5, "y": 0.1},   # left+width=5
            {"x": 0.5, "y": 0.4},   # +height=4
            {"x": 0.1, "y": 0.4},
        ]
        left, top, w, h = denormalize_polygon(poly, dims)
        assert (left, top, w, h) == (1.0, 1.0, 4.0, 3.0)

    def test_zero_dims_or_short_polygon(self):
        assert denormalize_polygon([], {"width_emu": 9144000, "height_emu": 9144000}) == (0.0, 0.0, 0.0, 0.0)
        assert denormalize_polygon([{"x": 0.1, "y": 0.1}], {"width_emu": 0, "height_emu": 0}) == (0.0, 0.0, 0.0, 0.0)


# ---------------------------------------------------------------------------
# (3) Derivation on synthetic component dicts
# ---------------------------------------------------------------------------
def _ph(placeholder_type, polygon, name="ph"):
    return {"type": "placeholder", "placeholder_type": placeholder_type, "polygon": polygon, "name": name}


def _shape(polygon, name="shape"):
    return {"type": "shape", "polygon": polygon, "name": name}


_DIMS = {"width_emu": 9144000, "height_emu": 9144000}  # 10in x 10in
_FULL_POLY = [{"x": 0.1, "y": 0.1}, {"x": 0.5, "y": 0.1}, {"x": 0.5, "y": 0.4}, {"x": 0.1, "y": 0.4}]


class TestDerivation:
    def test_fingerprint_drops_chrome_and_non_placeholders(self):
        comps = [
            _ph("title", _FULL_POLY),
            _ph("body", _FULL_POLY),
            _ph("footer", _FULL_POLY),   # chrome -> dropped
            _shape(_FULL_POLY),           # non-placeholder -> dropped
            _ph("date", _FULL_POLY),      # chrome -> dropped
        ]
        assert sorted(_derive_fingerprint(comps)) == ["OBJECT", "TITLE"]

    def test_fingerprint_org_chart_becomes_object(self):
        # M3-A: an ORG_CHART placeholder extracts as placeholder_type "chart"
        comps = [_ph("chart", _FULL_POLY)]
        assert _derive_fingerprint(comps) == ["OBJECT"]

    def test_content_area_only_object_canonical(self):
        comps = [
            _ph("title", _FULL_POLY),                              # TITLE -> not counted
            _ph("body", _FULL_POLY),                               # OBJECT -> 4x3 = 12 in^2
            _ph("picture", _FULL_POLY),                            # PICTURE -> not counted
            _ph("body", _FULL_POLY),                               # OBJECT -> +12 = 24 in^2
        ]
        assert _derive_content_area(comps, _DIMS) == pytest.approx(24.0, abs=0.01)

    def test_build_placeholders_excludes_chrome(self):
        comps = [
            _ph("title", _FULL_POLY, name="t"),
            _ph("slide_number", _FULL_POLY, name="sn"),  # chrome -> excluded
        ]
        recs = _build_placeholders(comps, _DIMS)
        assert len(recs) == 1
        assert recs[0]["type"] == "TITLE"
        assert recs[0]["left_in"] == 1.0
        assert recs[0]["width_in"] == 4.0


# ---------------------------------------------------------------------------
# (4) PARITY — adapter vs sidecar on the bundled template (Phase-1 gate)
# ---------------------------------------------------------------------------
class TestAdapterParity:
    @pytest.fixture
    def adapter_contract(self, template_path):
        schema = extract_schema(template_path)
        return embedded_schema_to_contract(schema)

    @pytest.fixture
    def sidecar_contract(self, template_path):
        return get_contract(template_path)

    def test_layout_count_matches(self, adapter_contract, sidecar_contract):
        assert len(adapter_contract["layouts"]) == len(sidecar_contract["layouts"])

    def test_every_layout_fingerprint_matches_as_multiset(self, adapter_contract, sidecar_contract):
        # _composition_diff is multiset-based, so compare sorted fingerprints.
        mismatches = []
        for a, s in zip(adapter_contract["layouts"], sidecar_contract["layouts"]):
            if sorted(a["fingerprint"]) != sorted(s["fingerprint"]):
                mismatches.append((a.get("name"), sorted(a["fingerprint"]), sorted(s["fingerprint"])))
        assert not mismatches, f"fingerprint mismatches: {mismatches[:3]}"

    def test_every_layout_name_and_index_match(self, adapter_contract, sidecar_contract):
        for a, s in zip(adapter_contract["layouts"], sidecar_contract["layouts"]):
            assert a["name"] == s["name"], (a.get("name"), s["name"])
            assert a["index"] == s["index"], (a.get("name"), a["index"], s["index"])

    def test_content_area_within_tolerance(self, adapter_contract, sidecar_contract):
        # Sub-1% drift is expected (polygon clamp/round); flag anything larger.
        drifts = []
        for a, s in zip(adapter_contract["layouts"], sidecar_contract["layouts"]):
            sa, ss = a["content_area_in2"], s["content_area_in2"]
            denom = max(abs(ss), 1.0)
            if abs(sa - ss) / denom > 0.01:
                drifts.append((a.get("name"), sa, ss))
        assert not drifts, f"content_area drift >1%: {drifts[:5]}"

    def test_slide_size_shape(self, adapter_contract):
        sz = adapter_contract["slide_size"]
        for k in ("width_emu", "height_emu", "width_in", "height_in", "ratio"):
            assert k in sz
        assert sz["width_emu"] > sz["height_emu"] > 0  # 16:9 landscape


# ---------------------------------------------------------------------------
# (5) Full-contract shape sanity
# ---------------------------------------------------------------------------
class TestContractShape:
    def test_contract_has_required_top_level_keys(self, template_path):
        schema = extract_schema(template_path)
        contract = embedded_schema_to_contract(schema)
        for k in ("slide_size", "theme", "layouts"):
            assert k in contract
        assert contract["theme"]["fonts"].keys()  # non-empty font palette
