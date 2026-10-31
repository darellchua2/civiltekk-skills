"""Tests for slide_data_list schema validation + two-layer retry (#20)."""
import pytest

from ppt_builder import generate_ppt_from_data
from schema_validator import (
    ValidationError,
    ValidationResult,
    parse_and_validate,
    validate_slide,
    validate_slide_data_list,
)


# ============================================================
# Per-slide-type acceptance / rejection
# ============================================================
class TestSchemaAcceptance:
    @pytest.mark.parametrize("slide_type", [
        "title_slide", "closing_slide", "section_header_slide",
        "content_slide", "content_image_slide", "two_content_slide",
        "comparison_slide",
    ])
    def test_minimal_valid_slide_passes(self, slide_type):
        data = {"slide_type": slide_type, "title": "T", "notes": "n"}
        assert validate_slide_data_list([data]).is_valid

    def test_valid_chart_slide_passes(self):
        data = {
            "slide_type": "chart_slide", "title": "T", "notes": "n",
            "chart_type": "bar", "categories": ["a", "b"],
            "series": [{"name": "S", "values": [1, 2]}],
        }
        assert validate_slide_data_list([data]).is_valid

    def test_all_chart_type_enums_accepted(self):
        for ct in ["bar", "bar_stacked", "bar_horizontal", "bar_horizontal_stacked",
                   "pie", "pie_exploded", "doughnut", "line", "line_markers"]:
            data = {
                "slide_type": "chart_slide", "title": "T", "notes": "n",
                "chart_type": ct, "categories": ["a"],
                "series": [{"name": "S", "values": [1]}],
            }
            assert validate_slide_data_list([data]).is_valid, ct


class TestSchemaRejection:
    def test_missing_title_is_error(self):
        r = validate_slide_data_list([{"slide_type": "content_slide", "notes": "n"}])
        assert not r.is_valid
        assert any("title" in e.field_path for e in r.errors)

    def test_wrong_type_is_error(self):
        r = validate_slide_data_list([{"slide_type": "content_slide", "title": 123, "notes": "n"}])
        assert not r.is_valid
        assert any("expected string" in e.reason for e in r.errors)

    def test_bad_chart_type_enum_is_error(self):
        data = {"slide_type": "chart_slide", "title": "T", "notes": "n",
                "chart_type": "banana", "categories": ["a"], "series": [{"name": "S", "values": [1]}]}
        r = validate_slide_data_list([data])
        assert not r.is_valid
        assert any("chart_type" in e.field_path and "not one of" in e.reason for e in r.errors)

    def test_chart_missing_series_is_error(self):
        data = {"slide_type": "chart_slide", "title": "T", "notes": "n",
                "chart_type": "bar", "categories": ["a"]}
        r = validate_slide_data_list([data])
        assert not r.is_valid
        assert any("series" in e.field_path for e in r.errors)

    def test_chart_empty_series_rejected(self):
        data = {"slide_type": "chart_slide", "title": "T", "notes": "n",
                "chart_type": "bar", "categories": ["a"], "series": []}
        r = validate_slide_data_list([data])
        assert not r.is_valid

    def test_series_item_missing_values_rejected(self):
        data = {"slide_type": "chart_slide", "title": "T", "notes": "n",
                "chart_type": "bar", "categories": ["a"], "series": [{"name": "S"}]}
        r = validate_slide_data_list([data])
        assert not r.is_valid

    def test_non_dict_slide_is_error(self):
        r = validate_slide_data_list(["not a slide"])
        assert not r.is_valid


# ============================================================
# Structured error reporting (slide index + field path)
# ============================================================
class TestErrorReporting:
    def test_error_carries_slide_index(self):
        r = validate_slide_data_list([
            {"slide_type": "title_slide", "title": "ok", "notes": "n"},
            {"slide_type": "content_slide", "notes": "n"},  # missing title
        ])
        err = r.errors[0]
        assert err.slide_index == 1
        assert err.field_path == "title"

    def test_error_message_is_human_readable(self):
        r = validate_slide_data_list([{"slide_type": "content_slide"}])
        msg = r.errors[0].format()
        assert "slide[0]" in msg
        assert "title" in msg

    def test_unknown_slide_type_is_warning_not_error(self):
        # Backward-compat: engine skips unknown types gracefully.
        r = validate_slide_data_list([{"slide_type": "mystery", "title": "T"}])
        assert r.is_valid  # no errors
        assert any("mystery" in w.reason for w in r.warnings)

    def test_missing_notes_is_warning(self):
        r = validate_slide_data_list([{"slide_type": "title_slide", "title": "T"}])
        assert r.is_valid
        assert any("notes" in w.field_path for w in r.warnings)

    def test_empty_list_is_warning(self):
        r = validate_slide_data_list([])
        assert r.is_valid
        assert len(r.warnings) >= 1

    def test_non_list_is_fatal(self):
        r = validate_slide_data_list({"slide_type": "title_slide"})
        assert not r.is_valid


# ============================================================
# Strict mode
# ============================================================
class TestStrictMode:
    def test_strict_promotes_missing_notes_to_error(self):
        r = validate_slide_data_list(
            [{"slide_type": "title_slide", "title": "T"}], strict=True,
        )
        assert not r.is_valid
        assert any("notes" in e.field_path for e in r.errors)

    def test_non_strict_keeps_notes_as_warning(self):
        r = validate_slide_data_list([{"slide_type": "title_slide", "title": "T"}])
        assert r.is_valid


# ============================================================
# Two-layer retry (inner JSON repair + outer schema validation)
# ============================================================
class TestParseAndValidate:
    def test_strips_code_fence(self):
        raw = '```json\n[{"slide_type": "title_slide", "title": "T", "notes": "n"}]\n```'
        res, data = parse_and_validate(raw)
        assert res.is_valid
        assert len(data) == 1

    def test_repairs_trailing_comma(self):
        raw = '[{"slide_type": "title_slide", "title": "T", "notes": "n",},]'
        res, data = parse_and_validate(raw)
        assert res.is_valid
        assert data is not None

    def test_repairs_single_quotes(self):
        raw = "[{'slide_type': 'title_slide', 'title': 'T', 'notes': 'n'}]"
        res, data = parse_and_validate(raw)
        assert res.is_valid
        assert data is not None

    def test_strips_variable_assignment(self):
        raw = 'slide_data = [{"slide_type": "title_slide", "title": "T", "notes": "n"}]'
        res, data = parse_and_validate(raw)
        assert res.is_valid

    def test_empty_output_returns_error(self):
        res, data = parse_and_validate("")
        assert not res.is_valid
        assert data is None

    def test_unparseable_returns_clear_error(self):
        res, data = parse_and_validate("this is not json at all }}}")
        assert not res.is_valid
        assert data is None
        assert "parse" in res.errors[0].reason.lower()

    def test_outer_layer_catches_schema_error(self):
        # Valid JSON but bad schema (bad chart_type).
        raw = '[{"slide_type": "chart_slide", "title": "T", "notes": "n", "chart_type": "nope", "categories": ["a"], "series": [{"name": "S", "values": [1]}]}]'
        res, data = parse_and_validate(raw)
        assert not res.is_valid
        assert data is not None  # inner layer succeeded


# ============================================================
# Engine defensive validation
# ============================================================
class TestEngineDefensiveValidation:
    def test_non_list_raises_validation_error(self, template_path, output_path):
        with pytest.raises(ValidationError):
            generate_ppt_from_data({"slide_type": "title_slide"}, template_path=template_path, output_path=output_path)

    def test_strict_raises_on_bad_chart_type(self, template_path, output_path):
        data = [{"slide_type": "chart_slide", "title": "T", "notes": "n",
                 "chart_type": "banana", "categories": ["a"],
                 "series": [{"name": "S", "values": [1]}]}]
        with pytest.raises(ValidationError):
            generate_ppt_from_data(data, template_path=template_path, output_path=output_path, strict=True)

    def test_non_strict_degrades_on_bad_chart_type(self, template_path, output_path):
        # Non-strict: engine degrades gracefully (defaults chart) instead of aborting.
        data = [{"slide_type": "chart_slide", "title": "T", "notes": "n",
                 "chart_type": "banana", "categories": ["a"],
                 "series": [{"name": "S", "values": [1]}]}]
        # Should NOT raise.
        generate_ppt_from_data(data, template_path=template_path, output_path=output_path)

    def test_validate_false_skips_validation(self, template_path, output_path):
        # With validation disabled, valid data renders without any ValidationError.
        from pptx import Presentation
        data = [{"slide_type": "title_slide", "title": "T", "subtitle": "S"}]
        generate_ppt_from_data(data, template_path=template_path, output_path=output_path, validate=False)
        prs = Presentation(output_path)
        assert len(prs.slides) == 1


# ============================================================
# validate_slide unit + ValidationResult API
# ============================================================
class TestValidateSlideUnit:
    def test_valid_slide_returns_empty_errors(self):
        r = validate_slide({"slide_type": "title_slide", "title": "T", "notes": "n"}, 0)
        assert r.is_valid

    def test_result_api(self):
        r = validate_slide_data_list([{"slide_type": "title_slide", "title": "T"}])
        assert isinstance(r, ValidationResult)
        assert r.is_valid is True
        assert len(r.warnings) >= 1
        assert isinstance(r.warning_messages(), list)
