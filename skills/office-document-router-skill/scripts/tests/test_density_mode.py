"""Tests for deck-wide density mode governance (per-slide word budgets).

Covers:
* ``count_slide_words`` — markdown stripping, multi-field sum, CJK, missing
  fields.
* ``validate_density`` — budget boundaries, finding shape, unknown-mode raise.
* Schema-validator integration — backward compatibility, strict-mode non-promotion,
  ``parse_and_validate`` forwarding, unknown-mode graceful warning.
* Slide-type semantics — ``chart_slide`` counts only ``title`` (not
  ``categories`` / ``series``); ``concise`` permits image-only / text-less slides.
"""
import pytest

from density_mode import (
    DEFAULT_DENSITY_MODE,
    DENSITY_BUDGETS,
    DensityFinding,
    VALID_DENSITY_MODES,
    WORD_COUNT_FIELDS,
    count_slide_words,
    validate_density,
)
from schema_validator import parse_and_validate, validate_slide_data_list


# ============================================================
# count_slide_words
# ============================================================
class TestCountSlideWords:
    def test_plain_title_only(self):
        assert count_slide_words({"title": "Hello world demo"}) == 3

    def test_strips_markdown_bold(self):
        # ``**Bold Title** — Description here`` → "Bold Title — Description here"
        # The em-dash is not a word; expect 4 words.
        body = "**Bold Title** — Description here"
        assert count_slide_words({"body": body}) == 4

    def test_strips_italic_and_code(self):
        body = "_italic_ and `code` mix"
        assert count_slide_words({"body": body}) == 4

    def test_sums_all_visible_fields(self):
        slide = {
            "title": "Two words",
            "subtitle": "Three word sub",
            "body": "**A** - one\n**B** - two here",
        }
        # title=2 + subtitle=3 + body=5 (A, one, B, two, here — the two hyphens
        # are punctuation-only and dropped) = 10
        assert count_slide_words(slide) == 10

    def test_multiline_body_counts_all_paragraphs(self):
        body = "line one here\nline two here\nline three here"
        assert count_slide_words({"body": body}) == 9

    def test_cjk_chars_counted_individually(self):
        # 7 CJK chars (数/字/化/转/型/报/告) + 0 Latin words = 7
        assert count_slide_words({"title": "数字化转型报告"}) == 7

    def test_cjk_mixed_with_latin(self):
        # "AI" is one whitespace token (2 chars, 1 word) + 4 CJK chars = 5
        assert count_slide_words({"title": "AI 赋能会计"}) == 5

    def test_missing_all_counted_fields_is_zero(self):
        assert count_slide_words({"slide_type": "title_slide"}) == 0

    def test_empty_and_non_string_fields_ignored(self):
        slide = {"title": "", "subtitle": None, "body": 123, "notes": "x y z"}
        # notes is NOT in WORD_COUNT_FIELDS, so total is 0.
        assert count_slide_words(slide) == 0

    def test_notes_excluded_from_count(self):
        slide = {"title": "Hi", "notes": "one two three four five six seven"}
        assert count_slide_words(slide) == 1


# ============================================================
# validate_density
# ============================================================
class TestValidateDensity:
    def test_budgets_table_has_three_modes(self):
        assert set(DENSITY_BUDGETS) == {"concise", "standard", "text-heavy"}
        assert DENSITY_BUDGETS["standard"] == (30, 50)
        assert DENSITY_BUDGETS["text-heavy"] == (75, 150)
        assert DENSITY_BUDGETS["concise"] == (0, 10)

    def test_default_mode_is_standard(self):
        assert DEFAULT_DENSITY_MODE == "standard"

    def test_valid_modes_match_budgets(self):
        assert VALID_DENSITY_MODES == tuple(DENSITY_BUDGETS.keys())

    def test_word_count_fields_excludes_notes_and_chart_labels(self):
        assert "notes" not in WORD_COUNT_FIELDS
        assert "categories" not in WORD_COUNT_FIELDS
        assert "series" not in WORD_COUNT_FIELDS
        for f in ("title", "subtitle", "body", "body_left", "body_right"):
            assert f in WORD_COUNT_FIELDS

    def test_in_budget_returns_no_findings(self):
        # 3-word title — fits concise (0-10) exactly.
        data = [{"slide_type": "title_slide", "title": "One two three"}]
        assert validate_density(data, "concise") == []

    def test_at_min_and_max_boundaries_in_budget(self):
        # min boundary of standard = 30 words
        title_30 = " ".join(["w"] * 30)
        assert validate_density([{"title": title_30}], "standard") == []
        # max boundary of standard = 50 words
        title_50 = " ".join(["w"] * 50)
        assert validate_density([{"title": title_50}], "standard") == []

    def test_over_budget_returns_finding(self):
        title_51 = " ".join(["w"] * 51)  # one over standard max
        findings = validate_density([{"title": title_51}], "standard")
        assert len(findings) == 1
        f = findings[0]
        assert f.slide_index == 0
        assert f.words == 51
        assert f.is_over() and not f.is_under()
        assert f.mode == "standard"

    def test_under_budget_returns_finding(self):
        # 3 words in text-heavy (75-150) → under
        findings = validate_density([{"title": "one two three"}], "text-heavy")
        assert len(findings) == 1
        f = findings[0]
        assert f.is_under() and not f.is_over()
        assert f.budget_min == 75 and f.budget_max == 150

    def test_concise_zero_words_is_in_budget(self):
        # An image-only / text-less slide is valid in concise mode.
        data = [{"slide_type": "content_image_slide", "title": ""}]
        assert validate_density(data, "concise") == []

    def test_finding_index_matches_slide_position(self):
        # Slide 0 in budget, slide 1 over budget, slide 2 in budget.
        in_b = " ".join(["w"] * 40)  # standard OK
        over = " ".join(["w"] * 60)  # standard over
        data = [{"title": in_b}, {"title": over}, {"title": in_b}]
        findings = validate_density(data, "standard")
        assert len(findings) == 1
        assert findings[0].slide_index == 1

    def test_unknown_mode_raises_value_error(self):
        with pytest.raises(ValueError, match="unknown density_mode"):
            validate_density([{"title": "x"}], "verbose")

    def test_non_dict_slide_skipped_silently(self):
        # Structural breakage is the schema validator's concern, not density's.
        data = [{"title": "ok"}, "not a slide", {"title": "ok"}]
        # No crash, no finding from the bad entry.
        findings = validate_density(data, "concise")
        assert all(isinstance(f, DensityFinding) for f in findings)


# ============================================================
# schema_validator integration
# ============================================================
class TestSchemaValidatorIntegration:
    def test_density_mode_none_is_backward_compatible(self):
        # Default call: no density_mode → identical to old behavior.
        data = [{"slide_type": "title_slide", "title": "Tiny", "notes": "n"}]
        r_old_style = validate_slide_data_list(data)
        r_explicit_none = validate_slide_data_list(data, density_mode=None)
        assert len(r_old_style.warnings) == len(r_explicit_none.warnings)
        assert not any("density" in w.reason for w in r_explicit_none.warnings)

    def test_valid_density_emits_no_extra_warnings(self):
        body = " ".join(["w"] * 40)  # fits standard exactly
        data = [{"slide_type": "content_slide", "title": "T", "body": body, "notes": "n"}]
        r = validate_slide_data_list(data, density_mode="standard")
        assert not any("density" in w.reason for w in r.warnings)

    def test_over_budget_emits_density_warning(self):
        body = " ".join(["w"] * 80)  # well over standard max of 50
        data = [{"slide_type": "content_slide", "title": "T", "body": body, "notes": "n"}]
        r = validate_slide_data_list(data, density_mode="standard")
        density_warnings = [w for w in r.warnings if "density" in w.reason]
        assert len(density_warnings) == 1
        assert "over budget" in density_warnings[0].reason
        assert density_warnings[0].slide_index == 0
        # Still valid — density never blocks.
        assert r.is_valid

    def test_strict_mode_does_not_promote_density_to_error(self):
        body = " ".join(["w"] * 80)  # over standard
        data = [{"slide_type": "content_slide", "title": "T", "body": body, "notes": "n"}]
        r = validate_slide_data_list(data, strict=True, density_mode="standard")
        # No errors at all — notes present, density stays a warning.
        assert r.is_valid
        assert any("density" in w.reason and "over budget" in w.reason for w in r.warnings)

    def test_unknown_density_mode_is_graceful_warning(self):
        data = [{"slide_type": "title_slide", "title": "T", "notes": "n"}]
        r = validate_slide_data_list(data, density_mode="verbose")
        # Should NOT raise; should surface a deck-level warning.
        assert r.is_valid
        assert any("unknown density_mode" in w.reason for w in r.warnings)

    def test_parse_and_validate_forwards_density_mode(self):
        body = " ".join(["w"] * 80)
        raw = (
            '[{"slide_type": "content_slide", "title": "T", '
            f'"body": "{body}", "notes": "n"}}]'
        )
        res, data = parse_and_validate(raw, density_mode="standard")
        assert res.is_valid
        assert any("density" in w.reason and "over budget" in w.reason for w in res.warnings)
        assert data is not None and len(data) == 1

    def test_parse_and_validate_default_unchanged(self):
        raw = '[{"slide_type": "title_slide", "title": "T", "notes": "n"}]'
        res, data = parse_and_validate(raw)
        assert res.is_valid
        assert not any("density" in w.reason for w in res.warnings)


# ============================================================
# Slide-type semantics
# ============================================================
class TestSlideTypeSemantics:
    def test_chart_slide_counts_only_title_not_categories_or_series(self):
        # title=2 words, categories have 7 single-word labels, series name=2 words
        # If categories/series were counted, total would be 11+ and over concise.
        # Only title counted → 2 words, within concise (0-10).
        data = [{
            "slide_type": "chart_slide",
            "title": "Market Growth",
            "chart_type": "bar",
            "categories": ["2020", "2021", "2022", "2023", "2024", "2025", "2026"],
            "series": [{"name": "Market Size", "values": [8.5, 11.2, 14.8, 19.5, 25.1, 31.7, 39.4]}],
            "notes": "n",
        }]
        findings = validate_density(data, "concise")
        assert findings == [], "chart_slide must count only title, not chart labels"

    def test_concise_image_only_slide_no_body_no_warning(self):
        # An image-only slide (no body text) is valid in concise mode
        # even though it has zero on-slide words.
        data = [{
            "slide_type": "content_image_slide",
            "title": "Drone",
            "image_path": "assets/drone.png",
            "notes": "n",
        }]
        # title=1 word, within concise (0-10).
        findings = validate_density(data, "concise")
        assert findings == []

    def test_concise_image_only_with_no_title_text(self):
        # Even a fully text-less slide is allowed in concise mode.
        data = [{
            "slide_type": "content_image_slide",
            "title": "",
            "image_path": "assets/sunset.png",
            "notes": "n",
        }]
        findings = validate_density(data, "concise")
        assert findings == []

    def test_two_content_slide_sums_both_columns(self):
        # Each column 20 words → total 40, within standard (30-50).
        col = " ".join(["w"] * 20)
        data = [{
            "slide_type": "two_content_slide",
            "title": "T",
            "body_left": col,
            "body_right": col,
            "notes": "n",
        }]
        findings = validate_density(data, "standard")
        assert findings == []
