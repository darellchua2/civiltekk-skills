"""Tests for the template_new.pptx resolution lifecycle (issue #46)."""
import shutil
from pathlib import Path

import pytest

from state_machine import (
    ResolutionPlan,
    SlideRequirement,
    build_notification,
    delete_leftover,
    plan_resolution,
    template_new_path_for,
)
from constraint_checker import Verdict


class TestTemplateNewPath:
    def test_derived_name(self):
        p = template_new_path_for("template/default.pptx")
        assert p.name == "default_new.pptx"
        assert p.parent.name == "template"


class TestDeleteLeftover:
    def test_removes_existing_file(self, template_path, tmp_path):
        base = shutil.copy2(template_path, tmp_path / "template.pptx")
        new = template_new_path_for(str(base))
        Path(new).write_bytes(b"leftover")
        assert Path(new).exists()
        assert delete_leftover(str(base)) is True
        assert not Path(new).exists()

    def test_noop_when_absent(self, template_path, tmp_path):
        base = shutil.copy2(template_path, tmp_path / "template.pptx")
        assert delete_leftover(str(base)) is False


class TestBuildNotification:
    def test_names_template_and_reason(self):
        over = [
            SlideRequirement(page=3, slide_type="content_slide",
                             verdict=Verdict(False, "over-limit: needs 100.0 in², available 44.6 in²")),
            SlideRequirement(page=5, slide_type="comparison_slide",
                             verdict=Verdict(False, "layout missing: unservable")),
        ]
        msg = build_notification(over)
        assert "template_new.pptx" in msg
        assert "template.pptx could not fit" in msg
        assert "Page 3" in msg and "content_slide" in msg
        assert "Page 5" in msg and "comparison_slide" in msg
        assert "over-limit" in msg and "missing" in msg


class TestPlanResolution:
    def test_normal_deck_needs_no_cloning(self, template_path, tmp_path):
        base = shutil.copy2(template_path, tmp_path / "template.pptx")
        deck = [
            {"slide_type": "title_slide", "title": "Deck", "subtitle": "2026"},
            {"slide_type": "content_slide", "title": "Overview",
             "body": "**A** - x\n**B** - y"},
            {"slide_type": "closing_slide", "title": "Thank You"},
        ]
        plan = plan_resolution(str(base), deck)
        assert isinstance(plan, ResolutionPlan)
        assert plan.needs_cloning is False
        assert plan.over_limit_slides == []
        assert plan.notification is None
        assert plan.active_template == str(base)

    def test_text_heavy_deck_not_cloned_under_missing_policy(self, template_path, tmp_path):
        """Option A: over-limit content does NOT clone (handled by density)."""
        base = shutil.copy2(template_path, tmp_path / "template.pptx")
        long_body = "\n".join(f"**Point {i}** - lorem ipsum dolor sit amet" for i in range(30))
        deck = [{"slide_type": "content_slide", "title": "Wall of text", "body": long_body}]
        plan = plan_resolution(str(base), deck)  # default clone_on="missing"
        assert plan.needs_cloning is False
        assert plan.over_limit_slides == []
        assert plan.notification is None

    def test_text_heavy_deck_cloned_under_any_policy(self, template_path, tmp_path):
        """clone_on='any' preserves the original over-limit → clone behaviour."""
        base = shutil.copy2(template_path, tmp_path / "template.pptx")
        long_body = "\n".join(f"**Point {i}** - lorem ipsum dolor sit amet" for i in range(30))
        deck = [{"slide_type": "content_slide", "title": "Wall of text", "body": long_body}]
        plan = plan_resolution(str(base), deck, clone_on="any")
        assert plan.needs_cloning is True
        assert len(plan.over_limit_slides) == 1
        assert plan.over_limit_slides[0].page == 1
        assert plan.notification is not None
        assert "template_new.pptx" in plan.notification

    def test_plan_deletes_leftover_first(self, template_path, tmp_path):
        """State machine ①: a pre-existing template_new is removed at request start."""
        base = shutil.copy2(template_path, tmp_path / "template.pptx")
        new = template_new_path_for(str(base))
        Path(new).write_bytes(b"stale")
        plan_resolution(str(base), [{"slide_type": "title_slide", "title": "X"}])
        assert not Path(new).exists()

    def test_unknown_slide_type_flagged(self, template_path, tmp_path):
        base = shutil.copy2(template_path, tmp_path / "template.pptx")
        deck = [{"slide_type": "totally_unknown", "title": "X"}]
        plan = plan_resolution(str(base), deck)
        assert plan.needs_cloning is True
        assert "unknown" in plan.over_limit_slides[0].verdict.reason
