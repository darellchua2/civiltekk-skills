"""
slide_schemas.py
================
Declarative JSON schema definitions for every supported ``slide_type`` plus
the ``chart_options`` sub-schema.

These schemas are intentionally dependency-free (plain Python dicts) so the
project stays self-contained. The companion ``schema_validator`` module
interprets them and produces structured, human-readable validation errors.

Field specification format
--------------------------
A *field spec* is a dict that may contain:

    {
        "type":        "string" | "array" | "object" | "bool" | "number",
        "enum":        [valid values],            # optional
        "items":       <field spec>,              # required when type == "array"
        "properties":  {name: <field spec>},      # optional when type == "object"
        "min_items":   int,                       # optional, for arrays
        "recommended": bool,                      # optional; if True a *missing*
                                                  #   required field is a warning
                                                  #   rather than a fatal error
    }

A *slide schema* groups fields into ``required`` (must be present) and
``optional`` (may be present) buckets.
"""

from __future__ import annotations

from typing import Any, Dict

# Re-exported set of valid chart_type values (single source of truth, kept in
# sync with ``ppt_builder._CHART_TYPE_MAP``).
CHART_TYPES = (
    "bar",
    "bar_stacked",
    "bar_horizontal",
    "bar_horizontal_stacked",
    "pie",
    "pie_exploded",
    "doughnut",
    "line",
    "line_markers",
)

_LEGEND_POSITIONS = ("bottom", "right", "top", "left", "none")
_IMAGE_POSITIONS = ("full", "half-left", "half-right", "below-title")

# A single chart series object: {"name": "...", "values": [numbers]}
_SERIES_SPEC: Dict[str, Any] = {
    "type": "object",
    "required": ["values"],
    "properties": {
        "name": {"type": "string"},
        "values": {"type": "array", "items": {"type": "number"}, "min_items": 1},
    },
}

# ``chart_options`` sub-schema (mirrors ppt_builder._add_chart_to_slide options)
CHART_OPTIONS_SPEC: Dict[str, Any] = {
    "type": "object",
    "properties": {
        "legend_position": {"type": "string", "enum": _LEGEND_POSITIONS},
        "show_data_labels": {"type": "bool"},
        "value_format": {"type": "string"},
        "y_axis_format": {"type": "string"},
        "y_axis_min": {"type": "number"},
        "y_axis_max": {"type": "number"},
        "y_axis_major_unit": {"type": "number"},
        "y_axis_title": {"type": "string"},
        "x_axis_title": {"type": "string"},
    },
}

# Resource-pipeline placeholder fields (see DESIGN-resource-resolver.md).
# All optional; the resolver replaces them with concrete assets.
_PLACEHOLDER_FIELDS = {
    "image_path": {"type": "string"},
    "image_position": {"type": "string", "enum": _IMAGE_POSITIONS},
    "data_query": {"type": "string"},
    "data_hint": {"type": "string"},
    "data_source": {"type": "string"},
}


def _notes_spec() -> Dict[str, Any]:
    """``notes`` is required by policy but missing it is only a warning so the
    engine stays backward compatible (existing decks omit notes)."""
    return {"type": "string", "recommended": True}


# ---------------------------------------------------------------------------
# Per-slide-type schemas
# ---------------------------------------------------------------------------
SLIDE_SCHEMAS: Dict[str, Dict[str, Dict[str, Any]]] = {
    "title_slide": {
        "required": {"title": {"type": "string"}, "notes": _notes_spec()},
        "optional": {"subtitle": {"type": "string"}, **_PLACEHOLDER_FIELDS},
    },
    "closing_slide": {
        "required": {"title": {"type": "string"}, "notes": _notes_spec()},
        "optional": {
            "subtitle": {"type": "string"},
            "presenter_name": {"type": "string"},
            "presenter_email": {"type": "string"},
            **_PLACEHOLDER_FIELDS,
        },
    },
    "section_header_slide": {
        "required": {"title": {"type": "string"}, "notes": _notes_spec()},
        "optional": {**_PLACEHOLDER_FIELDS},
    },
    "content_slide": {
        "required": {"title": {"type": "string"}, "notes": _notes_spec()},
        "optional": {"body": {"type": "string"}, **_PLACEHOLDER_FIELDS},
    },
    "content_image_slide": {
        "required": {"title": {"type": "string"}, "notes": _notes_spec()},
        "optional": {"body": {"type": "string"}, **_PLACEHOLDER_FIELDS},
    },
    "two_content_slide": {
        "required": {"title": {"type": "string"}, "notes": _notes_spec()},
        "optional": {
            "body_left": {"type": "string"},
            "body_right": {"type": "string"},
            **_PLACEHOLDER_FIELDS,
        },
    },
    "comparison_slide": {
        "required": {"title": {"type": "string"}, "notes": _notes_spec()},
        "optional": {
            "body_left": {"type": "string"},
            "body_right": {"type": "string"},
            **_PLACEHOLDER_FIELDS,
        },
    },
    "chart_slide": {
        "required": {
            "title": {"type": "string"},
            "notes": _notes_spec(),
            "chart_type": {"type": "string", "enum": CHART_TYPES},
            "categories": {"type": "array", "items": {"type": "string"}, "min_items": 1},
            "series": {"type": "array", "items": _SERIES_SPEC, "min_items": 1},
        },
        "optional": {
            "chart_options": CHART_OPTIONS_SPEC,
            **_PLACEHOLDER_FIELDS,
        },
    },
}

# Reverse lookup: every slide_type the engine understands.
VALID_SLIDE_TYPES = tuple(SLIDE_SCHEMAS.keys())


def _build_all_field_specs() -> Dict[str, Dict[str, Any]]:
    """Union of every field spec across the 8 slide types + extended fields.

    GIT-93 Phase 4: used by the validator's generic per-field path for
    ``layout_name``-targeted slides (unknown slide_type). First-wins on
    duplicate field names (specs are consistent across types for a given
    name — e.g. ``title``/``notes``/``body`` are identical everywhere).
    """
    specs: Dict[str, Dict[str, Any]] = {}
    for schema in SLIDE_SCHEMAS.values():
        for bucket in ("required", "optional"):
            for name, spec in schema.get(bucket, {}).items():
                specs.setdefault(name, spec)
    # Extended fields (multi-slot backfill + layout_name targeting — not in
    # the per-type schemas but recognized by the engine/backfill pass).
    specs["layout_name"] = {"type": "string"}
    specs["body_slots"] = {"type": "array"}
    specs["image_paths"] = {"type": "array"}
    specs["title_slots"] = {"type": "array"}
    return specs


ALL_FIELD_SPECS = _build_all_field_specs()
