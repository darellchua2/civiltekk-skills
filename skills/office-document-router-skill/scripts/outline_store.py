"""
outline_store.py
================
Persist / load the multi-stage generation **outline artifact** (Phase 1 Track C,
#21 / #24).

The outline (Stage 1 output, plain text) is saved to the OS temp dir so it can
be surfaced to the user and edited in the interactive-checkpoint flow (#24),
without polluting the repository. An optional ``deck_id`` disambiguates
concurrent runs.

An optional **density mode** (``concise`` / ``standard`` / ``text-heavy``) is
recorded as an HTML-comment header at the top of the artifact for
traceability — the agent re-saves the outline with the mode after the Stage 2
checkpoint confirms it, and ``load_outline_mode`` reads it back so Stage 3 can
pass the mode to the validator.

Public API::

    save_outline(outline_text, deck_id=None, mode=None) -> Path
    load_outline(path) -> str
    load_outline_mode(path) -> Optional[str]
    latest_outline() -> Optional[Path]
    cleanup_all() -> int
"""

from __future__ import annotations

import logging
import re
import tempfile
import time
from pathlib import Path
from typing import Optional

logger = logging.getLogger(__name__)

# Namespaced system temp dir for ALL pipeline temp artifacts (outline
# checkpoints + any agent-written temp JSON). Kept OUT of the repo so it never
# pollutes git; cleared automatically after each successful render via
# ``cleanup_all()`` (invoked by ``ppt_builder.generate_ppt_from_data``).
_TEMP_DIR = Path(tempfile.gettempdir()) / "opencode" / "pptx_pipeline"
_PREFIX = "pptx_outline"

# Header line format recording the chosen density mode in the artifact.
# Plain HTML comment so it stays invisible when the markdown is rendered.
_MODE_HEADER_RE = re.compile(r"^<!--\s*mode:\s*([a-z\-]+)\s*-->\s*$", re.MULTILINE)


def _render_with_mode(outline_text: str, mode: Optional[str]) -> str:
    """Prepend the mode header line when a mode is supplied."""
    if not mode:
        return outline_text or ""
    return f"<!-- mode: {mode} -->\n{outline_text or ''}"


def _ensure_dir() -> Path:
    _TEMP_DIR.mkdir(parents=True, exist_ok=True)
    return _TEMP_DIR


def save_outline(
    outline_text: str,
    deck_id: Optional[str] = None,
    *,
    mode: Optional[str] = None,
) -> Path:
    """Persist ``outline_text`` and return its path.

    When ``mode`` is given (a density mode key), it is recorded as a header
    comment at the top of the artifact for traceability and later retrieval
    via :func:`load_outline_mode`.
    """
    stem = deck_id or f"{int(time.time() * 1000)}"
    path = _ensure_dir() / f"{_PREFIX}_{stem}.md"
    path.write_text(_render_with_mode(outline_text, mode), encoding="utf-8")
    logger.info("Outline artifact saved: %s (mode=%s)", path, mode or "none")
    return path


def load_outline(path) -> str:
    """Read a previously saved outline artifact (including any mode header)."""
    p = Path(path)
    if not p.exists():
        raise FileNotFoundError(f"Outline artifact not found: {p}")
    return p.read_text(encoding="utf-8")


def load_outline_mode(path) -> Optional[str]:
    """Extract the recorded density mode from an outline artifact, if any.

    Returns ``None`` for artifacts saved without a mode (backward compatible).
    """
    try:
        text = load_outline(path)
    except FileNotFoundError:
        return None
    match = _MODE_HEADER_RE.search(text)
    return match.group(1) if match else None


def latest_outline() -> Optional[Path]:
    """Return the most recently saved outline artifact, if any."""
    if not _TEMP_DIR.exists():
        return None
    candidates = sorted(_TEMP_DIR.glob(f"{_PREFIX}_*.md"))
    return candidates[-1] if candidates else None


def cleanup_all() -> int:
    """Delete every file in the pipeline temp dir.

    Called automatically by ``ppt_builder.generate_ppt_from_data`` after a
    successful render so transient artifacts (outline checkpoints, agent-written
    temp JSON) do not accumulate on disk. Returns the number of files removed.
    Safe to call when the dir is empty or absent.
    """
    if not _TEMP_DIR.exists():
        return 0
    removed = 0
    for p in _TEMP_DIR.iterdir():
        if p.is_file() or p.is_symlink():
            try:
                p.unlink()
                removed += 1
            except OSError as exc:
                logger.warning("Could not remove %s: %s", p, exc)
    return removed
