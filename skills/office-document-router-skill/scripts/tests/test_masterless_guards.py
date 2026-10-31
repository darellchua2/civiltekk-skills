"""US-4.8 Phase 0 tests — masterless guard hardening + TemplateError relocation.

Tests that ``_clone_layout_into`` and ``_verify_layouts`` raise
``TemplateError`` (from the vendored ``scripts/_common/errors.py``) instead of
raw ``IndexError`` when the presentation has no slide master.
"""
import sys
from pathlib import Path

import pytest

_HERE = Path(__file__).resolve().parent
_MODIFIER_SCRIPTS = _HERE.parent
_COMMON_SCRIPTS = _MODIFIER_SCRIPTS / "_common"
for _p in (str(_MODIFIER_SCRIPTS), str(_COMMON_SCRIPTS)):
    if _p not in sys.path:
        sys.path.insert(0, _p)

from errors import TemplateError  # noqa: E402
from layout_creator import _clone_layout_into, _verify_layouts  # noqa: E402


class _FakeMasterlessPrs:
    """Minimal stand-in: empty slide_masters + sized slide_layouts."""

    def __init__(self):
        self.slide_masters = []
        self.slide_layouts = ["x"]


class TestCloneLayoutIntoMasterless:
    def test_raises_template_error_not_index_error(self):
        prs = _FakeMasterlessPrs()
        with pytest.raises(TemplateError, match="no slide master"):
            _clone_layout_into(prs, donor_index=0, new_name="test")

    def test_does_not_raise_index_error(self):
        prs = _FakeMasterlessPrs()
        with pytest.raises(TemplateError):
            _clone_layout_into(prs, donor_index=0, new_name="test")
        # The key assertion: the exception is TemplateError, NOT IndexError.
        # pytest.raises(TemplateError) would not catch IndexError, so reaching
        # this line proves the guard works.

    def test_error_message_mentions_master(self):
        prs = _FakeMasterlessPrs()
        with pytest.raises(TemplateError) as exc_info:
            _clone_layout_into(prs, donor_index=0, new_name="test")
        assert "slide master" in str(exc_info.value).lower()


class TestVerifyLayoutsMasterless:
    def test_raises_template_error_on_masterless_file(self, tmp_path):
        # Create a dummy file (content doesn't matter — the fake prs mocks
        # the reload). We patch Presentation to return a masterless prs.
        dummy = tmp_path / "dummy.pptx"
        dummy.write_bytes(b"dummy")

        import layout_creator as lc_mod
        original_presentation = lc_mod.Presentation

        class _MasterlessReload:
            slide_masters = []

        try:
            lc_mod.Presentation = lambda _: _MasterlessReload()
            with pytest.raises(TemplateError, match="no slide master"):
                _verify_layouts(str(dummy), ["expected_layout"])
        finally:
            lc_mod.Presentation = original_presentation


class TestTemplateErrorSource:
    def test_imports_from_common_errors(self):
        from errors import TemplateError as CommonTemplateError
        from layout_creator import TemplateError as ImportedTemplateError
        assert CommonTemplateError is ImportedTemplateError

    def test_ppt_builder_re_exports_same_class(self):
        import ppt_builder
        from errors import TemplateError as CommonTemplateError
        assert ppt_builder.TemplateError is CommonTemplateError
