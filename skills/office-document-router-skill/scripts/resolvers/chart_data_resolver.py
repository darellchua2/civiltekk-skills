"""
chart_data_resolver.py
======================
Resolves a chart slide's ``data_query`` into **sourced** ``categories`` /
``series`` (real numbers + a citation) instead of LLM-fabricated figures.

A slide is resolved only when it carries a ``data_query`` AND does not already
provide concrete ``series`` (existing concrete data is never overwritten). The
citation is appended to the slide's ``notes`` when ``cite_in_notes`` is set.

Search is pluggable:
    * ``search_fn``  — injectable callable(query, config) -> dict | None
                       where dict has keys ``categories``, ``series``, ``source``.
                       Primary path for tests / custom providers.
    * No provider    -> graceful skip (real web search is best done by the
                       agent which has ``webfetch``; the resolver stays a thin,
                       testable shim).

Graceful by contract: any failure returns the slide unchanged.

Agent contract: ``data_query`` is resolved by the agent's ``webfetch``
pre-flight, NOT by this resolver (it never makes a network call). The agent
MUST fetch real numbers before writing concrete ``categories``/``series``;
fabricating numbers just to pass schema validation is forbidden.
"""

from __future__ import annotations

import logging
from typing import Any, Callable, Dict, Optional

logger = logging.getLogger(__name__)


def _series_is_concrete(slide_data: Dict[str, Any]) -> bool:
    series = slide_data.get("series")
    if isinstance(series, list) and series:
        # treat as concrete if at least one series has non-empty values
        for s in series:
            if isinstance(s, dict) and s.get("values"):
                return True
    return False


def _search(query: str, config: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    cd_cfg = config.get("chart_data", {})

    search_fn: Optional[Callable[[str, Dict[str, Any]], Optional[Dict[str, Any]]]] = cd_cfg.get("search_fn")
    if callable(search_fn):
        try:
            result = search_fn(query, config)
            if result:
                return result
        except Exception as exc:  # pragma: no cover - defensive
            logger.warning("chart_data search_fn failed for '%s': %s", query, exc)
        return None

    # No search provider wired up. The agent (which has webfetch) should source
    # the data pre-flight; the resolver degrades gracefully here.
    logger.info(
        "chart_data resolver: no search_fn configured for '%s' — leaving slide "
        "as-is (provide concrete series or configure a provider)", query,
    )
    return None


def _valid_result(result: Dict[str, Any]) -> bool:
    categories = result.get("categories")
    series = result.get("series")
    return (
        isinstance(categories, list) and len(categories) > 0
        and isinstance(series, list) and len(series) > 0
    )


def resolve(slide_data: Dict[str, Any], config: Dict[str, Any]) -> Dict[str, Any]:
    """Resolve a ``data_query`` into sourced chart data (returns a new dict)."""
    out = dict(slide_data)

    if out.get("slide_type") != "chart_slide":
        return out

    query = (out.get("data_query") or "").strip()
    if not query:
        return out

    if _series_is_concrete(out):
        # Existing concrete data wins — do not overwrite.
        return out

    result = _search(query, config)
    if not result or not _valid_result(result):
        return out

    out["categories"] = list(result["categories"])
    out["series"] = [dict(s) for s in result["series"]]
    out.pop("data_query", None)

    cite = config.get("chart_data", {}).get("cite_in_notes", True)
    source = (result.get("source") or "").strip()
    if cite and source:
        existing_notes = (out.get("notes") or "").strip()
        citation = f"Data source: {source}"
        out["notes"] = f"{existing_notes}\n{citation}".strip() if existing_notes else citation
        out["data_source"] = source

    logger.info(
        "chart_data resolver: '%s' -> %d categories, %d series (source: %s)",
        query, len(out["categories"]), len(out["series"]), source or "n/a",
    )
    return out
