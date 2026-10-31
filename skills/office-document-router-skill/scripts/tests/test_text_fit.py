"""Pure unit tests for the text-fit estimator (US-4.2, Phase 1).

No PPTX dependency — ``text_fit`` is a pure module. These tests pin the
estimate model (char-width → lines → height → fit) and the shrink loop
(−2pt steps, 8pt floor) without touching the rendering engine.
"""
import math

import pytest

from text_fit import (
    DEFAULT_PARA_SPACING_FACTOR,
    LINE_SPACING_DEFAULT,
    MIN_FONT_SIZE_PT,
    ROLE_BASE_PT,
    TEXT_PADDING_IN,
    FontFit,
    estimate_height_in,
    estimate_lines,
    fits_at_size,
    fit_font_size,
)


# ============================================================
# estimate_lines
# ============================================================
class TestEstimateLines:
    def test_empty_is_zero(self):
        assert estimate_lines("", 18, 9.0) == 0

    def test_short_fits_one_line(self):
        # 11 chars * 0.5em = 5.5em * 18pt = 99pt; cap = (9-0.2)*72 = 633.6pt → 1 line
        assert estimate_lines("hello world", 18, 9.0) == 1

    def test_long_wraps_to_many_lines(self):
        # 400 chars * 0.5em = 200em * 18pt = 3600pt / 633.6 → ceil(5.68) = 6
        assert estimate_lines("x" * 400, 18, 9.0) == 6

    def test_cjk_uses_full_em_width(self):
        # 40 CJK chars = 40em*18 = 720pt / 633.6 → ceil(1.136) = 2
        assert estimate_lines("字" * 40, 18, 9.0) == 2

    def test_cjk_more_lines_than_latin_at_same_size(self):
        # same char count, CJK occupies twice the width → at least as many lines
        assert estimate_lines("字" * 40, 18, 9.0) >= estimate_lines("x" * 40, 18, 9.0)

    def test_explicit_newlines_each_take_a_line(self):
        assert estimate_lines("a\nb\nc", 18, 9.0) == 3

    def test_blank_line_counts_as_one(self):
        assert estimate_lines("a\n\nb", 18, 9.0) == 3

    def test_minimum_one_line_for_nonempty(self):
        assert estimate_lines("x", 18, 9.0) >= 1

    def test_narrow_box_wraps_more(self):
        wide = estimate_lines("x" * 100, 18, 9.0)
        narrow = estimate_lines("x" * 100, 18, 2.0)
        assert narrow > wide


# ============================================================
# estimate_height_in (incl. M2 paragraph-spacing reserve)
# ============================================================
class TestEstimateHeightIn:
    def test_single_line_single_paragraph(self):
        # BT-142 Phase 2.4a: LINE_SPACING_DEFAULT raised 1.2 → 1.3
        # 1 line * 18 * 1.3 / 72 = 0.325in, no inter-para gap
        assert estimate_height_in(1, 18, 1.3, 1) == pytest.approx(0.325)

    def test_scales_with_lines(self):
        assert estimate_height_in(2, 18, 1.3, 1) == pytest.approx(0.65)

    def test_paragraph_spacing_reserve_added(self):
        # M2: multiple paragraphs add inter-para gaps
        # BT-142 Phase 2.4a: DEFAULT_PARA_SPACING_FACTOR raised 0.4 → 0.7
        single = estimate_height_in(5, 18, 1.3, 1)
        multi = estimate_height_in(5, 18, 1.3, 5)
        assert multi > single
        # 4 gaps * 0.7 * 18 / 72 = 0.7in of reserve
        assert multi - single == pytest.approx(0.7)

    def test_zero_paragraph_gap_when_single_paragraph(self):
        assert estimate_height_in(3, 14, 1.3, 1) == pytest.approx(
            3 * 14 * 1.3 / 72
        )


# ============================================================
# fits_at_size
# ============================================================
class TestFitsAtSize:
    def test_empty_text_always_fits(self):
        assert fits_at_size("", 18, 9.0, 0.5) is True
        assert fits_at_size("   ", 18, 9.0, 0.5) is True

    def test_short_text_fits(self):
        # est ~0.3in <= (1.0 - 0.2)
        assert fits_at_size("hello world", 18, 9.0, 1.0) is True

    def test_long_text_does_not_fit_small_box(self):
        assert fits_at_size("x" * 400, 18, 9.0, 1.0) is False

    def test_taller_box_fits_more(self):
        assert fits_at_size("x" * 400, 18, 9.0, 4.0) is True


# ============================================================
# fit_font_size
# ============================================================
class TestFitFontSize:
    def test_fits_at_base_no_adjustment(self):
        fit = fit_font_size("hello world", 18, 9.0, 1.0)
        assert fit.applied_size_pt == 18
        assert fit.adjusted is False
        assert fit.fits is True
        assert fit.base_source == "role_ceiling"

    def test_empty_text_keeps_base(self):
        fit = fit_font_size("", 18, 9.0, 1.0)
        assert fit.applied_size_pt == 18
        assert fit.adjusted is False
        assert fit.fits is True

    def test_degenerate_box_keeps_base(self):
        for bad in [(0.0, 1.0), (9.0, 0.0), (0.1, 0.1)]:
            fit = fit_font_size("x" * 400, 18, bad[0], bad[1])
            assert fit.applied_size_pt == 18
            assert fit.adjusted is False

    def test_shrink_stepping_until_fit(self):
        # base 24, long text in a 1in-tall box → shrinks in -2pt steps
        fit = fit_font_size("x" * 400, 24, 9.0, 1.0)
        assert fit.applied_size_pt < 24
        assert fit.applied_size_pt >= MIN_FONT_SIZE_PT
        assert fit.adjusted is True
        assert fit.fits is True
        # applied must be one of the stepped values (24 - 2k), even
        assert (24 - fit.applied_size_pt) % 2 == pytest.approx(0.0)

    def test_floor_clamp_when_unfittable(self):
        # so much text it cannot fit even at the 8pt floor
        fit = fit_font_size("x" * 4000, 24, 9.0, 1.0)
        assert fit.applied_size_pt == MIN_FONT_SIZE_PT
        assert fit.fits is False  # honest: still overflowing at the floor
        assert fit.adjusted is True

    def test_never_below_floor(self):
        fit = fit_font_size("x" * 10000, 40, 3.0, 1.0)
        assert fit.applied_size_pt >= MIN_FONT_SIZE_PT

    def test_applied_never_exceeds_base(self):
        # AC2 invariant: only ever reduced
        for text, base in [("x" * 50, 14), ("x" * 400, 28), ("字" * 80, 18)]:
            fit = fit_font_size(text, base, 9.0, 2.0)
            assert fit.applied_size_pt <= base + 1e-9

    def test_floor_wins_over_sub_floor_base(self):
        # Pathological base < min (e.g. a 6pt layout sample run): the
        # readability floor wins — applied stays at min, not the sub-floor base.
        fit = fit_font_size("hello world", 6, 9.0, 4.0)
        assert fit.applied_size_pt == MIN_FONT_SIZE_PT
        assert fit.applied_size_pt >= MIN_FONT_SIZE_PT

    def test_cjk_triggers_shrink(self):
        # 100 CJK chars in a short box cannot fit at 18 → shrinks
        fit = fit_font_size("字" * 100, 18, 9.0, 0.8)
        assert fit.adjusted is True
        assert fit.applied_size_pt < 18

    def test_base_source_propagated(self):
        fit = fit_font_size("hello", 18, 9.0, 1.0, base_source="schema")
        assert fit.base_source == "schema"
        assert fit.base_size_pt == 18

    def test_lines_estimated_positive_when_text_present(self):
        fit = fit_font_size("x" * 100, 18, 9.0, 4.0)
        assert fit.lines_estimated >= 1


# ============================================================
# Calibration sanity check (PLAN-GIT-60 decision 2)
# ============================================================
class TestCalibration:
    def _words(self, n):
        return ("word " * n).strip()

    def test_150_words_fit_at_18_in_9x4(self):
        # calibration self-check: ~150 words @ 18pt in a 9x4 body box fits
        assert fits_at_size(self._words(150), 18, 9.0, 4.0) is True

    def test_300_words_do_not_fit_at_18_in_9x4(self):
        # overflow beyond the text-heavy budget → triggers shrink
        assert fits_at_size(self._words(300), 18, 9.0, 4.0) is False

    def test_role_ceilings_are_conservative(self):
        # M1: ceilings never exceed a typical template body size
        assert ROLE_BASE_PT["body"] == 14
        assert ROLE_BASE_PT["title"] == 28
        assert ROLE_BASE_PT["subtitle"] == 18
