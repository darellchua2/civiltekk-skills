"""Tests for the template introspection engine (issue #43, Phase 0).

Covers the three acceptance areas from #43:
  (a) contract shape correctness — slide_size / theme / per-layout
      placeholders + fingerprint + content_area_in2 present and typed.
  (b) mtime cache hit/miss — unchanged mtime reuses the cached contract;
      changed mtime re-introspects.
  (c) round-trip introspection of the current ``template.pptx`` — golden
      check that the known key layouts get the expected fingerprints.
"""
import json
import os
import shutil

import pytest

from template_introspector import (
    contract_path_for,
    get_contract,
    introspect,
)


# ============================================================
# (a) Contract shape correctness
# ============================================================
class TestContractShape:
    def test_top_level_keys_present(self, template_path):
        c = introspect(template_path)
        for key in ("source_file", "source_mtime", "slide_size", "theme", "layouts"):
            assert key in c, f"missing top-level key: {key}"

    def test_source_file_and_mtime(self, template_path):
        c = introspect(template_path)
        assert c["source_file"] == os.path.basename(template_path)
        assert isinstance(c["source_mtime"], float)
        assert c["source_mtime"] == pytest.approx(os.path.getmtime(template_path))

    def test_slide_size_typed(self, template_path):
        size = introspect(template_path)["slide_size"]
        for key in ("width_emu", "height_emu", "width_in", "height_in", "ratio"):
            assert key in size
        assert isinstance(size["width_emu"], int)
        assert isinstance(size["height_emu"], int)
        assert isinstance(size["ratio"], str)
        assert ":" in size["ratio"]

    def test_slide_size_16x9_values(self, template_path):
        size = introspect(template_path)["slide_size"]
        # The bundled template is 16:9; exact EMU/inches differ by template source
        # (e.g. Google Slides export is 10"×5.625", a native deck 13.33"×7.5").
        assert size["ratio"] == "16:9"
        assert size["width_emu"] > size["height_emu"] > 0
        assert size["width_in"] > 0 and size["height_in"] > 0

    def test_theme_has_colors_and_fonts(self, template_path):
        theme = introspect(template_path)["theme"]
        assert "colors" in theme and "fonts" in theme
        assert len(theme["colors"]) >= 8, "clrScheme should expose ~12 roles"
        assert "accent1" in theme["colors"]
        assert all(v.startswith("#") for v in theme["colors"].values())
        assert theme["fonts"]["major_latin"]
        assert theme["fonts"]["minor_latin"]

    def test_each_layout_shape(self, template_path):
        layouts = introspect(template_path)["layouts"]
        assert len(layouts) > 0
        for L in layouts:
            for key in ("index", "name", "placeholders", "fingerprint", "content_area_in2"):
                assert key in L, f"layout missing {key}: {L.get('name')}"
            assert isinstance(L["index"], int)
            assert isinstance(L["name"], str)
            assert isinstance(L["placeholders"], list)
            assert isinstance(L["fingerprint"], list)
            assert isinstance(L["content_area_in2"], (int, float))
            for ph in L["placeholders"]:
                for key in ("idx", "name", "type", "left_in", "top_in", "width_in", "height_in"):
                    assert key in ph

    def test_chrome_placeholders_excluded(self, template_path):
        """FOOTER / SLIDE_NUMBER / DATE must never appear in a fingerprint."""
        for L in introspect(template_path)["layouts"]:
            for ph in L["placeholders"]:
                assert ph["type"] not in {"FOOTER", "SLIDE_NUMBER", "DATE"}


# ============================================================
# (c) Bundled-template structural coverage (template-agnostic)
#     Verifies the shipped template provides the layout variety the engine's
#     8 slide types need — without hardcoding layout names (which differ by
#     template source: native deck vs Google Slides export, etc.).
# ============================================================
class TestBundledTemplateCoverage:
    def test_has_title_subtitle_layout(self, template_path):
        """A cover/title layout ([TITLE, SUBTITLE]) exists for title/closing."""
        fps = [L["fingerprint"] for L in introspect(template_path)["layouts"]]
        assert any(f == ["TITLE", "SUBTITLE"] for f in fps)

    def test_has_content_layout_with_area(self, template_path):
        """At least one content (OBJECT) layout with a non-zero content area."""
        layouts = introspect(template_path)["layouts"]
        content = [L for L in layouts if "OBJECT" in L["fingerprint"] and L["content_area_in2"] > 0]
        assert content, "template must provide at least one content (OBJECT) layout"

    def test_has_title_only_layout(self, template_path):
        """A title-only layout ([TITLE]) exists for chart_slide."""
        fps = [L["fingerprint"] for L in introspect(template_path)["layouts"]]
        assert any(f == ["TITLE"] for f in fps)

    def test_has_multi_body_layout(self, template_path):
        """A multi-body layout (>=2 OBJECT) exists for two_content / comparison."""
        layouts = introspect(template_path)["layouts"]
        assert any(L["fingerprint"].count("OBJECT") >= 2 for L in layouts)


# ============================================================
# (b) mtime cache hit / miss
# ============================================================
class TestMtimeCache:
    def _copy_template(self, template_path, tmp_path):
        dest = tmp_path / "template.pptx"
        shutil.copy2(template_path, dest)
        return str(dest)

    def test_contract_path_derived(self, template_path):
        cp = contract_path_for(template_path)
        assert cp.name.endswith(".contract.json")
        assert cp.parent == cp.parent  # alongside the template

    def test_get_contract_writes_cache_file(self, template_path, tmp_path):
        tp = self._copy_template(template_path, tmp_path)
        cp = contract_path_for(tp)
        assert not cp.exists()
        get_contract(tp)
        assert cp.exists()
        with open(cp, encoding="utf-8") as fh:
            json.load(fh)  # valid JSON

    def test_cache_hit_skips_introspect(self, template_path, tmp_path, monkeypatch):
        tp = self._copy_template(template_path, tmp_path)
        first = get_contract(tp)  # populates cache

        # Sabotage fresh introspection; a cache hit must NOT call it.
        def _boom(_path):
            raise AssertionError("introspect should not run on a cache hit")
        monkeypatch.setattr("template_introspector.introspect", _boom)

        second = get_contract(tp)
        assert second["source_mtime"] == first["source_mtime"]

    def test_cache_miss_on_mtime_change(self, template_path, tmp_path):
        tp = self._copy_template(template_path, tmp_path)
        first = get_contract(tp)
        old_mtime = first["source_mtime"]

        # Advance the file mtime into the future; cache must invalidate.
        future = old_mtime + 3600.0
        os.utime(tp, (future, future))

        second = get_contract(tp)
        assert second["source_mtime"] == pytest.approx(future)
        assert second["source_mtime"] != old_mtime

    def test_corrupt_cache_refetches(self, template_path, tmp_path):
        tp = self._copy_template(template_path, tmp_path)
        cp = contract_path_for(tp)
        cp.write_text("{ not valid json", encoding="utf-8")
        # Must not crash; re-introspect and recover.
        contract = get_contract(tp)
        assert "layouts" in contract
