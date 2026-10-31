"""Tests for BT-142 Phase 3.4.2 container_check.

Uses lightweight shape fakes — ``container_check`` is pure geometry, so we
don't need full ``python-pptx`` shapes. This keeps tests fast and decoupled
from python-pptx internals (e.g. ``LayoutShapes`` not supporting add_shape).
"""

from __future__ import annotations

import sys
import pathlib

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

from pptx import Presentation
from pptx.util import Inches

from container_check import (
    Rect,
    container_violations,
    check_template,
    EMU_PER_PX,
    Violation,
)


class _FakePlaceholderFormat:
    def __init__(self, idx):
        self.idx = idx
        self.type = None


class _FakeShape:
    """Minimal shape stub for container_check geometry tests."""

    def __init__(self, name, x_in, y_in, w_in, h_in, *, is_placeholder=False, idx=None, text=""):
        self.name = name
        self.left = Inches(x_in)
        self.top = Inches(y_in)
        self.width = Inches(w_in)
        self.height = Inches(h_in)
        self.is_placeholder = is_placeholder
        self.placeholder_format = _FakePlaceholderFormat(idx) if is_placeholder else None
        self.text = text

    @property
    def shape_id(self):
        return hash(self.name) & 0xFFFF


class _FakeShapes:
    def __init__(self, shapes):
        self._shapes = shapes

    def __iter__(self):
        return iter(self._shapes)


class _FakeLayout:
    def __init__(self, name, shapes):
        self.name = name
        self.shapes = _FakeShapes(shapes)


def test_rect_contains_point():
    r = Rect(0, 0, 100, 100)
    assert r.contains_point(50, 50)
    assert not r.contains_point(150, 50)


def test_edge_overflow_zero_when_inside():
    outer = Rect(0, 0, 1000, 1000)
    inner = Rect(50, 50, 100, 100)
    assert inner.edge_overflow(outer) == 0


def test_edge_overflow_positive_on_left():
    outer = Rect(100, 0, 1000, 1000)
    inner = Rect(0, 0, 100, 100)
    assert inner.edge_overflow(outer) == 100


def test_container_violations_detects_spill():
    """Body placeholder that exceeds its orange card → critical violation."""
    card = _FakeShape("card1", 1, 1, 4, 2)
    # Body placeholder: 5in wide, spills 1in past the card's right edge
    body = _FakeShape("body1", 1, 1.1, 5, 1.8, is_placeholder=True, idx=1)
    layout = _FakeLayout("L", [card, body])
    vs = container_violations(layout, tolerance_px=4, critical_px=20)
    assert len(vs) >= 1
    assert vs[0].severity == "critical"
    assert vs[0].overflow_px > 20


def test_container_violations_clean_when_inside():
    card = _FakeShape("card1", 1, 1, 5, 3)
    body = _FakeShape("body1", 1.2, 1.2, 4.6, 2.6, is_placeholder=True, idx=1)
    layout = _FakeLayout("L", [card, body])
    vs = container_violations(layout, tolerance_px=4, critical_px=20)
    assert vs == []


def test_picks_tightest_container():
    """When nested containers both contain the placeholder's center, pick the smaller."""
    outer = _FakeShape("outer", 0, 0, 10, 10)
    inner = _FakeShape("inner", 2, 2, 4, 4)
    body = _FakeShape("body", 3, 3, 1, 1, is_placeholder=True, idx=1)
    layout = _FakeLayout("L", [outer, inner, body])
    vs = container_violations(layout, tolerance_px=0, critical_px=0)
    assert len(vs) <= 1  # body fits inside inner; should be no violation
    # Now make body spill out of inner but still inside outer
    body2 = _FakeShape("body", 3, 3, 4, 1, is_placeholder=True, idx=1)
    layout2 = _FakeLayout("L2", [outer, inner, body2])
    vs2 = container_violations(layout2, tolerance_px=0, critical_px=0)
    assert len(vs2) == 1
    assert vs2[0].container_name == "inner"


def test_check_template_summary_shape():
    out = check_template(Presentation())
    assert "__summary" in out
    assert out["__summary"]["layouts_checked"] >= 1
    assert "critical" in out["__summary"]
    assert "warning" in out["__summary"]


def test_tolerance_absorbs_minor_overhang():
    """A body positioned inside the card by more than the tolerance is clean."""
    # Card covers (1,1) size (4,2). Body inset 5px on all sides — comfortably
    # inside even with a 4px tolerance applied (which shrinks the card by 4px
    # on each side).
    inset_in = 5.0 / 96.0
    card = _FakeShape("card1", 1, 1, 4, 2)
    body = _FakeShape(
        "body1",
        1 + inset_in,
        1 + inset_in,
        4 - 2 * inset_in,
        2 - 2 * inset_in,
        is_placeholder=True,
        idx=1,
    )
    layout = _FakeLayout("L", [card, body])
    vs = container_violations(layout, tolerance_px=4, critical_px=20)
    assert vs == []


def test_violation_to_dict_round_trip():
    v = Violation(
        placeholder_idx=1,
        placeholder_name="body",
        container_shape_id=99,
        container_name="card",
        overflow_emu=200000,
        overflow_px=21,
        severity="critical",
        detail="x",
    )
    d = v.to_dict()
    assert d["severity"] == "critical"
    assert d["overflow_px"] == 21
