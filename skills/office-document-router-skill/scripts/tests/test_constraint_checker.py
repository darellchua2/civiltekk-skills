"""Tests for the over-limit constraint checker (issue #46)."""
import pytest

from constraint_checker import (
    Verdict,
    check_content_area,
    count_slide_words,
    estimate_needed_area,
    evaluate_slide,
)
from template_introspector import introspect


class TestCheckContentArea:
    def test_fits_when_needed_within_available(self):
        v = check_content_area(40.0, 44.57)
        assert v.fits is True
        assert v.delta_in2 == pytest.approx(4.57, abs=0.01)

    def test_over_limit_when_needed_exceeds_available(self):
        v = check_content_area(100.0, 44.57)
        assert v.fits is False
        assert "over-limit" in v.reason
        assert v.delta_in2 < 0

    def test_boundary_included_as_fit(self):
        v = check_content_area(44.57, 44.57)
        assert v.fits is True


class TestEstimateNeededArea:
    def test_zero_words_needs_zero_area(self):
        assert estimate_needed_area(0) == 0.0

    def test_scales_with_word_count(self):
        a40 = estimate_needed_area(40)
        a80 = estimate_needed_area(80)
        assert a80 == pytest.approx(2 * a40, rel=0.01)

    def test_custom_density(self):
        # higher density ⇒ less area needed for the same words
        loose = estimate_needed_area(90, words_per_in2=0.5)
        tight = estimate_needed_area(90, words_per_in2=1.5)
        assert loose > tight


class TestCountSlideWords:
    def test_counts_body_and_title(self):
        n = count_slide_words({"title": "Hello world", "body": "**A** - one two"})
        # "Hello world" (2) + "A - one two" (4, "-" counts as a token) = 6
        assert n == 6

    def test_ignores_notes(self):
        assert count_slide_words({"title": "Hi", "notes": "a b c d e"}) == 1


class TestEvaluateSlide:
    def test_content_slide_within_budget_fits(self, template_path):
        contract = introspect(template_path)
        sd = {"slide_type": "content_slide", "title": "Overview",
              "body": "**A** - x\n**B** - y\n**C** - z"}  # ~6 words
        v = evaluate_slide("content_slide", sd, contract)
        assert v.fits is True
        assert v.slide_type == "content_slide"

    def test_text_heavy_content_slide_over_limit(self, template_path):
        contract = introspect(template_path)
        # ~120 words at 0.9 w/in² ⇒ ~133 in² needed ≫ ~44 available.
        long_body = "\n".join(f"**Point {i}** - lorem ipsum dolor sit amet" for i in range(30))
        sd = {"slide_type": "content_slide", "title": "Wall of text", "body": long_body}
        v = evaluate_slide("content_slide", sd, contract)
        assert v.fits is False
        assert v.cause == "over_limit"
        assert "over-limit" in v.reason

    def test_title_slide_always_fits(self, template_path):
        contract = introspect(template_path)
        v = evaluate_slide("title_slide", {"title": "X", "subtitle": "Y"}, contract)
        assert v.fits is True
        assert v.cause == "fits"
        assert v.reason == "no content-area constraint"

    def test_chart_slide_always_fits(self, template_path):
        contract = introspect(template_path)
        sd = {"slide_type": "chart_slide", "title": "Chart",
              "categories": ["A"], "series": [{"name": "S", "values": [1]}]}
        v = evaluate_slide("chart_slide", sd, contract)
        assert v.fits is True
        assert v.cause == "fits"

    def test_missing_layout_cause(self):
        # A title-only contract cannot serve content_slide.
        contract = {"layouts": [
            {"index": 0, "name": "Title", "fingerprint": ["TITLE", "SUBTITLE"], "content_area_in2": 0},
        ]}
        v = evaluate_slide("content_slide", {"body": "x"}, contract)
        assert v.fits is False
        assert v.cause == "missing"
        assert "missing" in v.reason

    def test_unknown_slide_type_cause(self):
        contract = {"layouts": [
            {"index": 0, "name": "Title", "fingerprint": ["TITLE", "SUBTITLE"], "content_area_in2": 0},
        ]}
        v = evaluate_slide("no_such_type", {}, contract)
        assert v.fits is False
        assert v.cause == "unknown"
