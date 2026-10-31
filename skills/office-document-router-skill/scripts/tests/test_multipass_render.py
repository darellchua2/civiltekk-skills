"""Tests for GIT-93 Phase 5 — multipass_render single-pass wrapper.

The partition/pseudo-type machinery (``partition_slides`` /
``_batch_to_engine_slides``) was deleted: ``layout_name`` is native now
(Phase 2), so a single pass renders N distinct layouts. These tests verify
``multipass_render`` delegates to ``render_fn`` in a single pass and that the
deleted symbols are gone.
"""
from __future__ import annotations

import importlib
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))


def test_multipass_render_always_single_pass(tmp_path):
    """multipass_render calls render_fn exactly once, regardless of layout count."""
    calls = []

    def fake_render(slides, tpl, out, overrides):
        calls.append((len(slides), overrides))
        with open(out, "w") as f:
            f.write("ok")
        return out

    from multipass_render import multipass_render
    multipass_render(
        [{"slide_type": f"t{i}"} for i in range(12)],  # >8, but no batching now
        template_path="/dev/null",
        output_path=str(tmp_path / "out.pptx"),
        render_fn=fake_render,
    )
    assert len(calls) == 1  # single pass, even with >8 layouts
    assert calls[0][0] == 12  # all 12 slides in one pass
    assert calls[0][1] == {}  # no pseudo-type overrides


def test_deleted_functions_no_longer_importable():
    """partition_slides / _batch_to_engine_slides / cap were removed (Phase 5)."""
    mod = importlib.import_module("multipass_render")
    assert not hasattr(mod, "partition_slides")
    assert not hasattr(mod, "_batch_to_engine_slides")
    assert not hasattr(mod, "DEFAULT_MAX_LAYOUTS_PER_BATCH")


def test_merge_decks_still_importable():
    """merge_decks is retained (independently useful)."""
    from multipass_render import merge_decks
    assert callable(merge_decks)
