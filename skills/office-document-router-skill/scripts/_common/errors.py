"""Shared error types for template-related failures.

US-4.8 / PLAN-GIT-78 Rev 2 (MINOR-2): ``TemplateError`` was previously defined
only in ``ppt_builder.py``. Importing it from there into
``pptx-template-modifier-skill`` would reintroduce the cross-skill production
coupling that PLAN-GIT-72 eliminated. This module is the neutral home in
``_common/scripts/`` — both skills import from here, keeping the dependency
direction inward (skills → _common, never skill → skill).
"""
from __future__ import annotations


class TemplateError(Exception):
    """Severe template problems that make generation impossible (US-4.7).

    Raised by the template pre-flight when the chosen template is structurally
    unusable: not a readable PPTX, has no slide master, has zero layouts, or
    cannot serve any of the 8 slide types. Minor issues (missing fonts, no
    header/footer, small content area, no embedded schema) stay non-fatal.
    """
