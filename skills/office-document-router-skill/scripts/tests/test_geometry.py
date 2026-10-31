"""Tests for geometry.py (US-4.6 — pure polygon/EMU primitives + Phase 0 T2).

Covers:
  - normalize_polygon / denormalize_polygon inverse pair (post-relocation from
    schema_extractor + contract_adapter; m2). Round-trip within 1% (AC3).
  - edge polygons: zero-area (degenerate) + clamped (off-slide) round-trip
    without error (architecture-review m7).
  - resolve_target_size — presets (16:9/4:3/1:1), explicit inch/EMU override,
    unknown-preset / malformed / non-positive errors.
  - aspect_ratios_match — the AC5 ratio no-op gate (m1): same ratio + diff
    absolute size -> True; different ratio -> False.
"""
from types import SimpleNamespace

import pytest

from geometry import (
    _EMU_PER_INCH,
    aspect_ratios_match,
    compute_ratio,
    denormalize_polygon,
    normalize_polygon,
    preset_keys,
    resolve_target_size,
)


def _shape(left, top, width, height):
    """A minimal fake shape exposing the 4 geometry attrs normalize_polygon reads."""
    return SimpleNamespace(left=left, top=top, width=width, height=height)


# ---------------------------------------------------------------------------
# normalize / denormalize inverse pair (AC3 round-trip)
# ---------------------------------------------------------------------------
class TestNormalizeDenormalize:
    def test_round_trip_target_dims_within_1pct(self):
        # Template-native 16:9 (10x5.625in); a placeholder at (1in,0.5in) 4x3in.
        native_w = int(10 * _EMU_PER_INCH)
        native_h = int(5.625 * _EMU_PER_INCH)
        shape = _shape(
            int(1 * _EMU_PER_INCH), int(0.5 * _EMU_PER_INCH),
            int(4 * _EMU_PER_INCH), int(3 * _EMU_PER_INCH),
        )
        poly = normalize_polygon(shape, native_w, native_h)

        # Denormalize against a DIFFERENT target size (4:3 = 10x7.5in) and
        # re-normalize against that target -> must match the original polygon.
        target_w = int(10 * _EMU_PER_INCH)
        target_h = int(7.5 * _EMU_PER_INCH)
        dims = {"width_emu": target_w, "height_emu": target_h}
        left_in, top_in, w_in, h_in = denormalize_polygon(poly, dims)

        placed = _shape(
            int(left_in * _EMU_PER_INCH), int(top_in * _EMU_PER_INCH),
            int(w_in * _EMU_PER_INCH), int(h_in * _EMU_PER_INCH),
        )
        renorm = normalize_polygon(placed, target_w, target_h)
        for orig, back in zip(poly, renorm):
            assert abs(orig["x"] - back["x"]) <= 0.01
            assert abs(orig["y"] - back["y"]) <= 0.01

    def test_denormalize_short_or_zero_dims_is_zero(self):
        assert denormalize_polygon([], {"width_emu": 9144000, "height_emu": 9144000}) == (0.0, 0.0, 0.0, 0.0)
        assert denormalize_polygon([{"x": 0.1, "y": 0.1}], {"width_emu": 0, "height_emu": 0}) == (0.0, 0.0, 0.0, 0.0)

    def test_zero_slide_dims_yields_degenerate_polygon(self):
        poly = normalize_polygon(_shape(100, 100, 100, 100), 0, 0)
        assert poly == [{"x": 0.0, "y": 0.0}] * 4

    def test_clamped_off_slide_polygon_round_trips(self):
        # A shape that overflows the slide: normalized coords clamp to [0,1].
        native_w = int(10 * _EMU_PER_INCH)
        native_h = int(5.625 * _EMU_PER_INCH)
        shape = _shape(
            int(-1 * _EMU_PER_INCH), int(-1 * _EMU_PER_INCH),  # off the top-left
            int(20 * _EMU_PER_INCH), int(20 * _EMU_PER_INCH),  # larger than slide
        )
        poly = normalize_polygon(shape, native_w, native_h)
        # Clamped to the unit square.
        assert all(0.0 <= pt["x"] <= 1.0 and 0.0 <= pt["y"] <= 1.0 for pt in poly)
        # Denormalize/re-normalize is stable (clamped rectangle round-trips).
        dims = {"width_emu": native_w, "height_emu": native_h}
        left_in, top_in, w_in, h_in = denormalize_polygon(poly, dims)
        renorm = normalize_polygon(
            _shape(int(left_in * _EMU_PER_INCH), int(top_in * _EMU_PER_INCH),
                   int(w_in * _EMU_PER_INCH), int(h_in * _EMU_PER_INCH)),
            native_w, native_h,
        )
        for orig, back in zip(poly, renorm):
            assert abs(orig["x"] - back["x"]) <= 0.01
            assert abs(orig["y"] - back["y"]) <= 0.01


# ---------------------------------------------------------------------------
# compute_ratio (relocated)
# ---------------------------------------------------------------------------
class TestComputeRatio:
    def test_16by9(self):
        assert compute_ratio(12192000, 6858000) == "16:9"

    def test_4by3(self):
        assert compute_ratio(9144000, 6858000) == "4:3"

    def test_square(self):
        assert compute_ratio(6858000, 6858000) == "1:1"

    def test_zero_height(self):
        assert compute_ratio(9144000, 0) == "9144000:0"


# ---------------------------------------------------------------------------
# resolve_target_size (T2)
# ---------------------------------------------------------------------------
class TestResolveTargetSize:
    def test_presets_present(self):
        keys = preset_keys()
        assert set(keys) == {"16:9", "4:3", "1:1"}

    @pytest.mark.parametrize("preset", ["16:9", "4:3", "1:1"])
    def test_preset_returns_canonical_emu(self, preset):
        w, h = resolve_target_size(preset)
        # Each preset matches its canonical EMU + has the advertised ratio.
        assert (w, h) == {
            "16:9": (12192000, 6858000),
            "4:3": (9144000, 6858000),
            "1:1": (6858000, 6858000),
        }[preset]
        assert compute_ratio(w, h) == preset

    def test_preset_is_case_insensitive_and_trimmed(self):
        assert resolve_target_size(" 16:9 ") == resolve_target_size("16:9")
        assert resolve_target_size("4:3".upper()) == resolve_target_size("4:3")

    def test_explicit_inches_override(self):
        w, h = resolve_target_size({"width_in": 10, "height_in": 7.5})
        assert w == int(10 * _EMU_PER_INCH)
        assert h == int(7.5 * _EMU_PER_INCH)

    def test_explicit_emu_override(self):
        assert resolve_target_size({"width_emu": 9144000, "height_emu": 6858000}) == (9144000, 6858000)

    def test_emu_takes_precedence_over_inches_when_both(self):
        assert resolve_target_size(
            {"width_emu": 100, "height_emu": 100, "width_in": 10, "height_in": 10}
        ) == (100, 100)

    def test_unknown_preset_raises(self):
        with pytest.raises(ValueError, match="Unknown target_size preset"):
            resolve_target_size("3:2")

    def test_malformed_dict_raises(self):
        with pytest.raises(ValueError, match="width_emu/height_emu or"):
            resolve_target_size({"foo": 1})

    def test_non_positive_dims_raise(self):
        with pytest.raises(ValueError, match="positive"):
            resolve_target_size({"width_in": 0, "height_in": 7.5})

    def test_wrong_type_raises(self):
        with pytest.raises(ValueError, match="preset string or a dims dict"):
            resolve_target_size(42)


# ---------------------------------------------------------------------------
# aspect_ratios_match — AC5 ratio no-op gate (m1)
# ---------------------------------------------------------------------------
class TestAspectRatiosMatch:
    def test_same_ratio_different_absolute_size_matches(self):
        # 10x5.625in 16:9 deck vs 13.333x7.5in 16:9 preset -> same ratio.
        assert aspect_ratios_match(9144000, 5143500, 12192000, 6858000) is True

    def test_different_ratio_does_not_match(self):
        # 16:9 vs 4:3 -> different.
        assert aspect_ratios_match(12192000, 6858000, 9144000, 6858000) is False

    def test_identical_sizes_match(self):
        assert aspect_ratios_match(9144000, 6858000, 9144000, 6858000) is True

    def test_near_ratio_within_tolerance(self):
        # 16:9 = 1.7778; 1.78 ratio within 0.5% -> match.
        assert aspect_ratios_match(17800, 10000, 16, 9) is True

    def test_zero_height_only_matches_other_zero_height(self):
        assert aspect_ratios_match(100, 0, 200, 0) is True
        assert aspect_ratios_match(100, 0, 200, 100) is False
