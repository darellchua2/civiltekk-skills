"""
pipeline.py
===========
Orchestrates all resource resolvers over an entire ``slide_data_list``.

    resolve_slide_data_list(slide_data_list, config) -> slide_data_list

Order: chart_data only. The resolver is non-fatal; a failure is skipped so the
deck still resolves and renders.

Config loading
--------------
``load_config(path=None)`` reads ``resolver.config.json`` next to the scripts
directory (or an explicit path). Missing file -> empty config (all resolvers
then degrade gracefully).
"""

from __future__ import annotations

import json
import logging
from pathlib import Path
from typing import Any, Dict, List

from . import chart_data_resolver

logger = logging.getLogger(__name__)

_SCRIPTS_DIR = Path(__file__).resolve().parent.parent
_DEFAULT_CONFIG = _SCRIPTS_DIR / "resolver.config.json"

# Resolver pass order.
_RESOLVERS = (
    ("chart_data", chart_data_resolver.resolve),
)


def load_config(path: str | None = None) -> Dict[str, Any]:
    """Load resolver config; missing/invalid file yields an empty dict."""
    config_path = Path(path) if path else _DEFAULT_CONFIG
    if not config_path.exists():
        logger.warning(
            "Resolver config not found (%s) — resource placeholders "
            "(data_query) will be skipped. Copy "
            "resolver.config.example.json to resolver.config.json to enable.",
            config_path,
        )
        return {}
    try:
        with open(config_path, "r", encoding="utf-8") as f:
            data = json.load(f)
        return data if isinstance(data, dict) else {}
    except Exception as exc:
        logger.warning("Failed to load resolver config %s: %s", config_path, exc)
        return {}


def resolve_slide(slide_data: Dict[str, Any], config: Dict[str, Any]) -> Dict[str, Any]:
    """Run every resolver on one slide (non-fatal per resolver)."""
    if not isinstance(slide_data, dict):
        return slide_data  # type: ignore[return-value]
    resolved = dict(slide_data)
    for name, resolver in _RESOLVERS:
        try:
            resolved = resolver(resolved, config)
        except Exception as exc:
            # Each resolver is supposed to be non-fatal, but defend anyway.
            logger.warning("Resolver '%s' raised on slide: %s", name, exc)
    return resolved


def resolve_slide_data_list(
    slide_data_list: List[Dict[str, Any]],
    config: Dict[str, Any] | None = None,
) -> List[Dict[str, Any]]:
    """Resolve placeholders across the whole deck (returns a new list)."""
    cfg = config if config is not None else load_config()
    if not isinstance(slide_data_list, list):
        return slide_data_list  # type: ignore[return-value]
    return [resolve_slide(slide, cfg) for slide in slide_data_list]
