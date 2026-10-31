"""Schema definitions package for the slides route engine.

Exposes the per-slide-type schemas and the standalone validator so callers can
import a single, stable entry point::

    from schema_validator import validate_slide_data_list
"""

from .slide_schemas import (
    ALL_FIELD_SPECS,
    CHART_OPTIONS_SPEC,
    CHART_TYPES,
    SLIDE_SCHEMAS,
    VALID_SLIDE_TYPES,
)

__all__ = [
    "SLIDE_SCHEMAS",
    "ALL_FIELD_SPECS",
    "CHART_OPTIONS_SPEC",
    "CHART_TYPES",
    "VALID_SLIDE_TYPES",
]
