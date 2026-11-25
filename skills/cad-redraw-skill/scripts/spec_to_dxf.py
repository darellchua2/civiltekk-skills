#!/usr/bin/env python3
"""Validate a redraw spec per references/redraw-spec.md and draw it to a DXF."""

import argparse
import copy
import json
import math
import re
import subprocess
import sys
import tempfile
from itertools import combinations
from pathlib import Path

try:
    import ezdxf
except ImportError:  # pragma: no cover - environment guard
    print("ezdxf is required: pip install ezdxf", file=sys.stderr)
    sys.exit(2)
from path_safety import ensure_safe_outputs

SPEC_VERSION = 1
ENTITY_TYPES = frozenset(
    {"line", "arc", "circle", "lwpolyline", "text", "mtext", "dimension"}
)
PROFILES = frozenset({"strict-dimensioned", "general", "hybrid", "visual-trace"})
EVIDENCE_LEVELS = frozenset({"known", "scaled", "inferred", "unreadable"})
CONSTRAINT_KINDS = frozenset(
    {"sum", "positive", "inside", "count", "spacing", "parallel", "aligned"}
)
UNIT_CODES = {"in": 1, "ft": 2, "mm": 4, "cm": 5, "m": 6, "unitless": 0}
ANNOTATION_TYPES = frozenset({"text", "mtext", "dimension"})
ANNOTATION_LAYERS = frozenset({"TEXT", "DIM"})
STRICT_EVIDENCE = frozenset({"known", "scaled"})
TOLERANCE = 1e-9
DIMENSION_TOLERANCE = 1e-6
TOP_LEVEL_FIELDS = (
    "spec_version",
    "profile",
    "units",
    "views",
    "entities",
    "constraints",
    "layers",
    "assumptions",
)


def _error(code: str, entity: str | None, message: str) -> dict:
    """Build one error/warning record for the validation report."""
    return {"code": code, "entity": entity, "message": message}


def _num(value) -> float | None:
    """Return value as float when it is a real number (bools excluded), else None."""
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    try:
        number = float(value)
    except OverflowError:
        return None
    return number if math.isfinite(number) else None


def _point(value) -> tuple[float, float] | None:
    """Return value as an (x, y) float pair when well-formed, else None."""
    if not isinstance(value, (list, tuple)) or len(value) != 2:
        return None
    x, y = _num(value[0]), _num(value[1])
    if x is None or y is None:
        return None
    return x, y


def _entity_bbox(entity: dict) -> tuple[float, float, float, float] | None:
    """Return a conservative (minx, miny, maxx, maxy) box for any entity type."""
    geometry = entity.get("geometry") or {}
    etype = entity.get("type")
    points: list[tuple[float, float]] = []
    if etype == "line":
        points = [
            p for p in (_point(geometry.get("start")), _point(geometry.get("end"))) if p
        ]
    elif etype in ("arc", "circle"):
        center, radius = _point(geometry.get("center")), _num(geometry.get("radius"))
        if center and radius is not None:
            points = [
                (center[0] - radius, center[1] - radius),
                (center[0] + radius, center[1] + radius),
            ]
    elif etype == "lwpolyline":
        points = [p for p in (_point(pt) for pt in geometry.get("points") or []) if p]
    elif etype in ("text", "mtext"):
        insert, height = _point(geometry.get("insert")), _num(geometry.get("height"))
        if insert and height is not None:
            pad = abs(height)
            points = [
                (insert[0] - pad, insert[1] - pad),
                (insert[0] + pad, insert[1] + pad),
            ]
    elif etype == "dimension":
        p1, p2 = _point(geometry.get("p1")), _point(geometry.get("p2"))
        offset = _num(geometry.get("offset"))
        if p1 and p2 and offset is not None:
            points = [p1, p2]
            for base in (p1, p2):
                for dx, dy in (
                    (-offset, 0.0),
                    (offset, 0.0),
                    (0.0, -offset),
                    (0.0, offset),
                ):
                    points.append((base[0] + dx, base[1] + dy))
    if len(points) < 2:
        return None
    xs, ys = [p[0] for p in points], [p[1] for p in points]
    return min(xs), min(ys), max(xs), max(ys)


def _numeric_value(entity: dict) -> float | None:
    """Resolve the numeric value an entity contributes to constraints, or None."""
    geometry = entity.get("geometry") or {}
    if not isinstance(geometry, dict):
        return None
    etype = entity.get("type")
    if etype in ("circle", "arc"):
        return _num(geometry.get("radius"))
    if etype == "line":
        start, end = _point(geometry.get("start")), _point(geometry.get("end"))
        if start and end:
            return math.dist(start, end)
    if etype in ("text", "mtext"):
        return _num(geometry.get("height"))
    if etype == "dimension":
        return _num(geometry.get("value"))
    return None


def _representative_point(entity: dict) -> tuple[float, float] | None:
    """Return one anchor point per entity for spacing checks."""
    geometry = entity.get("geometry") or {}
    etype = entity.get("type")
    if etype in ("arc", "circle"):
        return _point(geometry.get("center"))
    if etype == "line":
        return _point(geometry.get("start"))
    if etype == "lwpolyline":
        points = geometry.get("points") or []
        return _point(points[0]) if points else None
    if etype in ("text", "mtext"):
        return _point(geometry.get("insert"))
    if etype == "dimension":
        return _point(geometry.get("p1"))
    return None


def _assumption_texts(assumptions) -> list[str]:
    """Flatten assumptions entries (strings or dicts of string values) to searchable text."""
    texts: list[str] = []
    for entry in assumptions or []:
        if isinstance(entry, str):
            texts.append(entry)
        elif isinstance(entry, dict):
            texts.extend(
                str(v) for v in entry.values() if isinstance(v, (str, int, float))
            )
    return texts


def _calibration_problem(view: dict) -> str | None:
    """Return why a view lacks usable, evidence-backed pixel-to-CAD calibration."""
    calibration = view.get("calibration")
    if not isinstance(calibration, dict):
        return "calibration is missing"
    kind = calibration.get("type")
    if not isinstance(kind, str):
        return "calibration type is missing or invalid"
    minimum = {"affine": 2, "dimension": 2, "homography": 4}.get(kind)
    if minimum is None:
        return f"calibration type {kind!r} is unsupported"
    if calibration.get("evidence") not in STRICT_EVIDENCE:
        return "calibration evidence must be 'known' or 'scaled'"
    pixels, cad = calibration.get("anchors_px"), calibration.get("anchors_cad")
    if (
        not isinstance(pixels, list)
        or not isinstance(cad, list)
        or len(pixels) != len(cad)
        or len(pixels) < minimum
    ):
        return f"{kind} calibration needs at least {minimum} paired anchors"
    pixel_points = _finite_points(pixels)
    cad_points = _finite_points(cad)
    if pixel_points is None or cad_points is None:
        return "calibration anchors must be finite [x, y] pairs"
    if len(set(pixel_points)) < minimum or len(set(cad_points)) < minimum:
        return "calibration anchors must be distinct in both coordinate systems"
    if kind == "homography":
        for points in (pixel_points, cad_points):
            if any(
                abs(
                    (b[0] - a[0]) * (c[1] - a[1])
                    - (b[1] - a[1]) * (c[0] - a[0])
                )
                <= TOLERANCE
                for a, b, c in combinations(points, 3)
            ):
                return "homography anchors must contain no three collinear points"
    return None


def _finite_points(values: list) -> list[tuple[float, float]] | None:
    """Return finite points for a calibration anchor list, else None."""
    points = []
    for value in values:
        point = _point(value)
        if point is None or not all(math.isfinite(coordinate) for coordinate in point):
            return None
        points.append(point)
    return points


def _has_matching_assumption(entity_id: str, texts: list[str]) -> bool:
    """An assumption matches when any entry mentions the entity id as a whole word."""
    pattern = re.compile(rf"\b{re.escape(entity_id)}\b")
    return any(pattern.search(text) for text in texts)


def _validate_geometry(entity: dict, errors: list) -> None:
    """Check the type-specific geometry payload; append schema/non_positive errors."""
    eid, etype = entity.get("id"), entity.get("type")
    geometry = entity.get("geometry")
    if not isinstance(geometry, dict):
        errors.append(
            _error("schema", eid, f"entity '{eid}': geometry must be an object")
        )
        return

    def need_point(field):
        """Extract geometry[field] as a [x, y] point, appending a schema error if malformed."""
        value = _point(geometry.get(field))
        if value is None:
            errors.append(
                _error(
                    "schema",
                    eid,
                    f"entity '{eid}': geometry.{field} must be [x, y] numbers",
                )
            )
        return value

    def need_number(field):
        """Extract geometry[field] as a number, appending a schema error if malformed."""
        value = _num(geometry.get(field))
        if value is None:
            errors.append(
                _error(
                    "schema", eid, f"entity '{eid}': geometry.{field} must be a number"
                )
            )
        return value

    if etype == "line":
        start, end = need_point("start"), need_point("end")
        if start and end and math.dist(start, end) <= TOLERANCE:
            errors.append(
                _error("non_positive", eid, f"entity '{eid}': zero-length line")
            )
    elif etype in ("arc", "circle"):
        need_point("center")
        radius = need_number("radius")
        if radius is not None and radius <= 0:
            errors.append(
                _error(
                    "non_positive",
                    eid,
                    f"entity '{eid}': radius must be > 0 (got {radius})",
                )
            )
        if etype == "arc":
            for field in ("start_angle", "end_angle"):
                need_number(field)
    elif etype == "lwpolyline":
        raw_points = geometry.get("points")
        if not isinstance(raw_points, list):
            errors.append(
                _error("schema", eid, f"entity '{eid}': geometry.points must be a list")
            )
            raw_points = []
        points = [_point(pt) for pt in raw_points]
        if any(p is None for p in points):
            errors.append(
                _error(
                    "schema",
                    eid,
                    f"entity '{eid}': geometry.points entries must be [x, y]",
                )
            )
        closed = geometry.get("closed", False)
        minimum = 3 if closed else 2
        if len(points) < minimum:
            errors.append(
                _error(
                    "schema",
                    eid,
                    f"entity '{eid}': lwpolyline needs >= {minimum} points"
                    f" ({'closed' if closed else 'open'})",
                )
            )
    elif etype in ("text", "mtext"):
        need_point("insert")
        height = need_number("height")
        if height is not None and height < 0:
            errors.append(
                _error(
                    "non_positive",
                    eid,
                    f"entity '{eid}': height must be >= 0 (got {height})",
                )
            )
        if not isinstance(entity.get("text"), str):
            errors.append(
                _error(
                    "schema",
                    eid,
                    f"entity '{eid}': {etype} requires a 'text' field (\"\" when unreadable)",
                )
            )
        if "rotation" in geometry and _num(geometry.get("rotation")) is None:
            errors.append(
                _error(
                    "schema", eid, f"entity '{eid}': geometry.rotation must be a number"
                )
            )
    elif etype == "dimension":
        need_point("p1")
        need_point("p2")
        offset = need_number("offset")
        if offset is not None and offset < 0:
            errors.append(
                _error(
                    "non_positive",
                    eid,
                    f"entity '{eid}': offset must be >= 0 (got {offset})",
                )
            )
        value = geometry.get("value")
        if value is not None and _num(value) is None:
            errors.append(
                _error(
                    "schema",
                    eid,
                    f"entity '{eid}': geometry.value must be a number or null",
                )
            )
        if not isinstance(entity.get("text"), str):
            errors.append(
                _error(
                    "schema",
                    eid,
                    f"entity '{eid}': dimension requires a 'text' field (\"\" when unreadable)",
                )
            )


def _resolve_ref(
    ref, entities_by_id: dict
) -> tuple[float | None, str | None, str | None]:
    """Resolve a constraint reference to a value; return (value, problem, problem_kind)."""
    literal = _num(ref)
    if (
        literal is not None
        or isinstance(ref, (int, float))
        and not isinstance(ref, bool)
    ):
        return literal, None, None
    entity = entities_by_id.get(ref)
    if entity is None:
        return None, f"unknown entity '{ref}'", "undefined_ref"
    if entity.get("evidence") == "unreadable":
        return None, f"entity '{ref}' has evidence 'unreadable'", "unreadable"
    value = _numeric_value(entity)
    if value is None:
        return None, f"entity '{ref}' has no numeric value", "no_value"
    return value, None, None


def _validate_constraints(
    spec: dict, entities: list, entities_by_id: dict
) -> tuple[list, list]:
    """Check every constraint arithmetically where evidence permits."""
    errors: list = []
    warnings: list = []
    for constraint in spec.get("constraints") or []:
        cid = constraint.get("id") if isinstance(constraint, dict) else None
        kind = constraint.get("kind") if isinstance(constraint, dict) else None
        if kind not in CONSTRAINT_KINDS:
            errors.append(
                _error("schema", cid, f"constraint '{cid}': unknown kind {kind!r}")
            )
            continue

        def skip(reason):
            """Downgrade this constraint to a warning with a named reason instead of drawing it."""
            warnings.append(
                _error("constraint", cid, f"constraint '{cid}' skipped: {reason}")
            )

        if kind == "sum":
            refs = constraint.get("of") or []
            values = []
            for ref in [*refs, constraint.get("equals")]:
                value, problem, problem_kind = _resolve_ref(ref, entities_by_id)
                if problem_kind == "unreadable":
                    skip(problem + " — checked only when evidence is upgraded")
                    values = []
                    break
                if problem:
                    errors.append(
                        _error("constraint", cid, f"constraint '{cid}': {problem}")
                    )
                    values = []
                    break
                values.append(value)
            if len(values) == len(refs) + 1:
                total, expected = sum(values[:-1]), values[-1]
                if abs(total - expected) > TOLERANCE * max(1.0, abs(expected)):
                    errors.append(
                        _error(
                            "constraint",
                            cid,
                            f"constraint '{cid}': sum {total:g} != {expected:g}",
                        )
                    )
        elif kind == "positive":
            value, problem, problem_kind = _resolve_ref(
                constraint.get("ref"), entities_by_id
            )
            if problem_kind == "unreadable":
                skip(problem + " — checked only when evidence is upgraded")
            elif problem:
                errors.append(
                    _error("constraint", cid, f"constraint '{cid}': {problem}")
                )
            elif value <= 0:
                errors.append(
                    _error(
                        "constraint",
                        cid,
                        f"constraint '{cid}': value {value:g} is not positive",
                    )
                )
        elif kind == "inside":
            inner = entities_by_id.get(constraint.get("ref"))
            outer = entities_by_id.get(constraint.get("within"))
            for role, entity in (("ref", inner), ("within", outer)):
                if entity is None:
                    errors.append(
                        _error(
                            "undefined_ref",
                            cid,
                            f"constraint '{cid}': {role} '{constraint.get(role)}' is not defined",
                        )
                    )
            if inner and outer:
                inner_box, outer_box = _entity_bbox(inner), _entity_bbox(outer)
                if inner_box is None or outer_box is None:
                    skip("cannot compute bounds of ref/within entities")
                else:
                    tol = TOLERANCE * max(
                        1.0, max(abs(v) for v in (*inner_box, *outer_box))
                    )
                    contained = (
                        inner_box[0] >= outer_box[0] - tol
                        and inner_box[1] >= outer_box[1] - tol
                        and inner_box[2] <= outer_box[2] + tol
                        and inner_box[3] <= outer_box[3] + tol
                    )
                    if not contained:
                        errors.append(
                            _error(
                                "constraint",
                                cid,
                                f"constraint '{cid}': '{inner.get('id')}' is not inside"
                                f" '{outer.get('id')}'",
                            )
                        )
        elif kind == "count":
            token, expected = constraint.get("of"), constraint.get("equals")
            if (
                not isinstance(token, str)
                or not isinstance(expected, int)
                or isinstance(expected, bool)
            ):
                errors.append(
                    _error(
                        "schema",
                        cid,
                        f"constraint '{cid}': count needs a string 'of' and integer 'equals'",
                    )
                )
            else:
                found = sum(1 for e in entities if token in e.get("id", ""))
                if found != expected:
                    errors.append(
                        _error(
                            "constraint",
                            cid,
                            f"constraint '{cid}': count of '{token}' is {found}, spec says {expected}",
                        )
                    )
        elif kind == "spacing":
            refs = constraint.get("of") or []
            points = []
            for ref in refs:
                entity = entities_by_id.get(ref)
                if entity is None:
                    errors.append(
                        _error(
                            "undefined_ref",
                            cid,
                            f"constraint '{cid}': reference '{ref}' is not defined",
                        )
                    )
                    points = []
                    break
                point = _representative_point(entity)
                if point is None:
                    skip(f"cannot locate '{ref}'")
                    points = []
                    break
                points.append(point)
            if len(points) >= 3:
                x_spread = max(p[0] for p in points) - min(p[0] for p in points)
                y_spread = max(p[1] for p in points) - min(p[1] for p in points)
                axis = 0 if x_spread >= y_spread else 1
                ordered = sorted(p[axis] for p in points)
                deltas = [b - a for a, b in zip(ordered, ordered[1:])]
                if any(
                    abs(d - deltas[0]) > TOLERANCE * max(1.0, abs(deltas[0]))
                    for d in deltas
                ):
                    errors.append(
                        _error(
                            "constraint",
                            cid,
                            f"constraint '{cid}': spacing is not equal along {'xy'[axis]} "
                            f"(deltas {['%.6g' % d for d in deltas]})",
                        )
                    )
            elif len(points) == len(refs):
                skip(f"spacing needs at least 3 references (got {len(refs)})")
        elif kind in ("parallel", "aligned"):
            refs = constraint.get("of") or []
            lines = []
            for ref in refs:
                entity = entities_by_id.get(ref)
                if entity is None:
                    errors.append(
                        _error(
                            "undefined_ref",
                            cid,
                            f"constraint '{cid}': reference '{ref}' is not defined",
                        )
                    )
                    lines = []
                    break
                if entity.get("type") != "line":
                    skip(f"'{ref}' is not a line")
                    lines = []
                    break
                lines.append(entity)
            if len(lines) == len(refs) == 2:
                directions, origins = [], []
                for line in lines:
                    geometry = line.get("geometry") or {}
                    start = _point(geometry.get("start"))
                    end = _point(geometry.get("end"))
                    if start is None or end is None:
                        skip(f"cannot read start/end points of '{line.get('id')}'")
                        directions = []
                        break
                    length = math.dist(start, end)
                    if length <= TOLERANCE:
                        skip(f"'{line.get('id')}' is zero-length")
                        directions = []
                        break
                    directions.append(
                        ((end[0] - start[0]) / length, (end[1] - start[1]) / length)
                    )
                    origins.append(start)
                if len(directions) == 2:
                    cross = (
                        directions[0][0] * directions[1][1]
                        - directions[0][1] * directions[1][0]
                    )
                    if abs(cross) > TOLERANCE:
                        errors.append(
                            _error(
                                "constraint",
                                cid,
                                f"constraint '{cid}': lines are not parallel"
                                f" (cross {cross:.3g})",
                            )
                        )
                    elif kind == "aligned":
                        offset_vector = (
                            origins[1][0] - origins[0][0],
                            origins[1][1] - origins[0][1],
                        )
                        offset_cross = (
                            offset_vector[0] * directions[0][1]
                            - offset_vector[1] * directions[0][0]
                        )
                        if abs(offset_cross) > TOLERANCE:
                            errors.append(
                                _error(
                                    "constraint",
                                    cid,
                                    f"constraint '{cid}': lines are parallel"
                                    " but not aligned",
                                )
                            )
            elif len(lines) == len(refs):
                skip(f"{kind} needs exactly 2 line references (got {len(refs)})")
    return errors, warnings


def validate_spec(spec) -> dict:
    """Validate a parsed spec; return {valid, errors, warnings, evidence_counts}."""
    errors: list = []
    warnings: list = []
    if not isinstance(spec, dict):
        return {
            "valid": False,
            "errors": [_error("schema", None, "spec root must be a JSON object")],
            "warnings": warnings,
            "evidence_counts": {level: 0 for level in sorted(EVIDENCE_LEVELS)},
        }
    if spec.get("spec_version") != SPEC_VERSION:
        errors.append(
            _error(
                "spec_version",
                None,
                f"spec_version must be {SPEC_VERSION} (got {spec.get('spec_version')!r})",
            )
        )
    for field in TOP_LEVEL_FIELDS:
        if field not in spec:
            errors.append(
                _error("schema", None, f"missing required top-level field '{field}'")
            )

    profile = spec.get("profile")
    if profile not in PROFILES:
        errors.append(
            _error(
                "schema",
                None,
                f"profile must be one of {sorted(PROFILES)} (got {profile!r})",
            )
        )
    units = spec.get("units")
    if not isinstance(units, dict) or units.get("system") not in UNIT_CODES:
        errors.append(
            _error(
                "schema",
                None,
                f"units.system must be one of {sorted(UNIT_CODES)} with a 'declared' flag",
            )
        )

    layer_names: list[str] = []
    for layer in spec.get("layers") or []:
        name = layer.get("name") if isinstance(layer, dict) else None
        if not isinstance(name, str) or not name:
            errors.append(
                _error(
                    "schema", None, f"layer entry {layer!r} needs a non-empty 'name'"
                )
            )
        elif name in layer_names:
            errors.append(_error("schema", None, f"duplicate layer name '{name}'"))
        else:
            layer_names.append(name)

    view_ids: list[str] = []
    for view in spec.get("views") or []:
        vid = view.get("id") if isinstance(view, dict) else None
        if not isinstance(vid, str) or not vid:
            errors.append(
                _error("schema", None, f"view entry {view!r} needs a non-empty 'id'")
            )
        elif vid in view_ids:
            errors.append(_error("duplicate_id", vid, f"duplicate view id '{vid}'"))
        else:
            view_ids.append(vid)

    entities_raw = spec.get("entities") or []
    if not isinstance(entities_raw, list):
        errors.append(_error("schema", None, "'entities' must be a list"))
        entities_raw = []
    entities = [e for e in entities_raw if isinstance(e, dict)]
    for raw in entities_raw:
        if not isinstance(raw, dict):
            errors.append(
                _error(
                    "schema",
                    None,
                    "non-object entry in 'entities' (each entity must be a JSON object)",
                )
            )
    entity_ids: list[str] = []
    entities_by_id: dict = {}
    evidence_counts = {level: 0 for level in sorted(EVIDENCE_LEVELS)}
    assumption_texts = _assumption_texts(spec.get("assumptions"))
    for entity in entities:
        eid = entity.get("id")
        for field in ("id", "type", "view", "layer", "geometry", "evidence"):
            if field not in entity:
                errors.append(
                    _error(
                        "schema",
                        eid,
                        f"entity {eid!r}: missing required field '{field}'",
                    )
                )
        if not isinstance(eid, str) or not eid:
            continue
        if eid in entities_by_id:
            errors.append(_error("duplicate_id", eid, f"duplicate entity id '{eid}'"))
            continue
        entities_by_id[eid] = entity
        entity_ids.append(eid)
        if entity.get("type") not in ENTITY_TYPES:
            errors.append(
                _error(
                    "schema",
                    eid,
                    f"entity '{eid}': type must be one of {sorted(ENTITY_TYPES)}",
                )
            )
        if entity.get("evidence") not in EVIDENCE_LEVELS:
            errors.append(
                _error(
                    "schema",
                    eid,
                    f"entity '{eid}': evidence must be one of {sorted(EVIDENCE_LEVELS)}",
                )
            )
        elif entity["evidence"] in evidence_counts:
            evidence_counts[entity["evidence"]] += 1
        if entity.get("view") not in view_ids:
            errors.append(
                _error(
                    "undefined_view",
                    eid,
                    f"entity '{eid}': view '{entity.get('view')}' is not defined",
                )
            )
        if entity.get("layer") not in layer_names:
            errors.append(
                _error(
                    "undefined_layer",
                    eid,
                    f"entity '{eid}': layer '{entity.get('layer')}' is not defined",
                )
            )
        _validate_geometry(entity, errors)
        if entity.get("evidence") == "inferred" and not _has_matching_assumption(
            eid, assumption_texts
        ):
            errors.append(
                _error(
                    "evidence",
                    eid,
                    f"entity '{eid}': inferred value requires a matching assumptions entry"
                    " naming the entity id",
                )
            )

    constraint_errors, constraint_warnings = _validate_constraints(
        spec, entities, entities_by_id
    )
    errors += constraint_errors
    warnings += constraint_warnings

    if profile == "strict-dimensioned":
        units_ok = isinstance(units, dict) and units.get("declared") is True
        system = units.get("system") if isinstance(units, dict) else None
        if not units_ok or system == "unitless" or system is None:
            errors.append(
                _error(
                    "profile",
                    None,
                    "strict-dimensioned requires units.declared=true with a system other"
                    " than 'unitless'",
                )
            )
        views_by_id = {
            view["id"]: view
            for view in spec.get("views") or []
            if isinstance(view, dict) and isinstance(view.get("id"), str)
        }
        dimension_views = {
            entity.get("view")
            if isinstance(entity.get("view"), str)
            else None
            for entity in entities
            if entity.get("type") == "dimension"
        }
        for view_id in sorted(dimension_views, key=lambda value: value or ""):
            view = views_by_id.get(view_id)
            problem = (
                "view is missing" if view is None else _calibration_problem(view)
            )
            if problem:
                errors.append(
                    _error(
                        "calibration",
                        str(view_id),
                        f"strict-dimensioned view '{view_id}' is not calibrated: {problem}",
                    )
                )
        for entity in entities:
            if entity.get("type") != "dimension":
                continue
            eid = entity.get("id")
            if entity.get("evidence") not in STRICT_EVIDENCE:
                errors.append(
                    _error(
                        "profile",
                        eid,
                        f"strict-dimensioned blocked: dimension '{eid}' evidence"
                        f" is '{entity.get('evidence')}' (requires known/scaled)",
                    )
                )
            geometry = entity.get("geometry")
            if not isinstance(geometry, dict):
                continue  # _validate_geometry already reported the schema error
            p1, p2 = _point(geometry.get("p1")), _point(geometry.get("p2"))
            value = _num(geometry.get("value"))
            if p1 is None or p2 is None or value is None:
                errors.append(
                    _error(
                        "profile",
                        eid,
                        f"strict-dimensioned requires a readable numeric value and "
                        f"measurable geometry for dimension '{eid}'",
                    )
                )
                continue
            measured = math.dist(p1, p2)
            allowed = DIMENSION_TOLERANCE * max(1.0, abs(measured), abs(value))
            if abs(measured - value) > allowed:
                errors.append(
                    _error(
                        "dimension_mismatch",
                        eid,
                        f"dimension '{eid}' value {value:g} differs from measured "
                        f"geometry {measured:g} by {abs(measured - value):g} "
                        f"(tolerance {allowed:g})",
                    )
                )
    elif profile == "visual-trace":
        if (
            isinstance(units, dict)
            and units.get("declared") is True
            and units.get("system") != "unitless"
        ):
            warnings.append(
                _error(
                    "profile",
                    None,
                    "visual-trace output cannot claim scale; declared units will not be asserted",
                )
            )
    return {
        "valid": not errors,
        "errors": errors,
        "warnings": warnings,
        "evidence_counts": evidence_counts,
    }


def draw_spec(spec: dict, output: Path, geometry_only: bool = False) -> list[str]:
    """Draw a validated spec to output.dxf; return ids of dropped annotation entities."""
    doc = ezdxf.new("R2010", setup=True)
    doc.units = UNIT_CODES.get((spec.get("units") or {}).get("system"), 0)
    for layer in spec.get("layers") or []:
        name = layer.get("name")
        if geometry_only and name in ANNOTATION_LAYERS:
            continue
        doc.layers.add(
            name,
            color=layer.get("color", 7),
            linetype=layer.get("linetype") or "CONTINUOUS",
        )
    msp = doc.modelspace()
    dropped: list[str] = []
    for entity in spec.get("entities") or []:
        etype, layer = entity["type"], entity["layer"]
        geometry = entity["geometry"]
        if geometry_only and etype in ANNOTATION_TYPES:
            dropped.append(entity["id"])
            continue
        attribs = {"layer": layer}
        if etype == "line":
            msp.add_line(geometry["start"], geometry["end"], dxfattribs=attribs)
        elif etype == "arc":
            msp.add_arc(
                geometry["center"],
                geometry["radius"],
                geometry["start_angle"],
                geometry["end_angle"],
                dxfattribs=attribs,
            )
        elif etype == "circle":
            msp.add_circle(geometry["center"], geometry["radius"], dxfattribs=attribs)
        elif etype == "lwpolyline":
            msp.add_lwpolyline(
                geometry["points"],
                format="xy",
                close=geometry.get("closed", False),
                dxfattribs=attribs,
            )
        elif etype == "text":
            text = msp.add_text(
                entity.get("text", ""),
                dxfattribs={
                    **attribs,
                    "height": geometry["height"],
                    "rotation": geometry.get("rotation", 0.0),
                    "style": "Standard",
                },
            )
            text.set_placement(geometry["insert"])
        elif etype == "mtext":
            msp.add_mtext(
                entity.get("text", ""),
                dxfattribs={
                    **attribs,
                    "char_height": geometry["height"],
                    "rotation": geometry.get("rotation", 0.0),
                    "insert": geometry["insert"],
                    "style": "Standard",
                },
            )
        elif etype == "dimension":
            value = geometry.get("value")
            dim = msp.add_aligned_dim(
                p1=geometry["p1"],
                p2=geometry["p2"],
                distance=geometry["offset"],
                text="<>" if value is None else str(value),
                dimstyle="EZDXF",
                dxfattribs=attribs,
            )
            dim.render()
    doc.saveas(str(output))
    return dropped


def load_spec(path: Path) -> dict:
    """Load and parse the spec JSON; exit 1 with a named error on bad input."""
    try:
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)
    except FileNotFoundError:
        print(f"spec file not found: {path}", file=sys.stderr)
        sys.exit(1)
    except json.JSONDecodeError as exc:
        print(f"invalid spec JSON '{path}': {exc}", file=sys.stderr)
        sys.exit(1)
    except UnicodeDecodeError:
        print(f"spec '{path}' is not valid UTF-8 text (wrong file?)", file=sys.stderr)
        sys.exit(1)
    except OSError as exc:
        print(f"cannot read spec '{path}': {exc}", file=sys.stderr)
        sys.exit(1)


def format_report(report: dict) -> str:
    """Render the human summary of a validation report, one issue per line."""
    lines = [
        f"valid: {report['valid']}, errors: {len(report['errors'])}, warnings: {len(report['warnings'])}"
    ]
    lines += [
        f"error [{e['code']}] {e['entity'] or 'spec'}: {e['message']}"
        for e in report["errors"]
    ]
    lines += [
        f"warning [{w['code']}] {w['entity'] or 'spec'}: {w['message']}"
        for w in report["warnings"]
    ]
    lines.append(f"evidence: {json.dumps(report['evidence_counts'])}")
    return "\n".join(lines)


def emit_report(report: dict, path: Path | None) -> None:
    """Write the full report JSON to path, or dump it to stdout when no path is given."""
    if path is not None:
        try:
            path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
        except OSError as exc:
            print(f"cannot write report '{path}': {exc}", file=sys.stderr)
            sys.exit(1)
    else:
        print(json.dumps(report, indent=2))
    print(format_report(report))


def _require(condition: bool, what: str) -> None:
    """Raise an AssertionError naming the failed self-check expectation."""
    if not condition:
        raise AssertionError(f"self-check failed: {what}")


def _valid_spec() -> dict:
    """Build an in-memory spec exercising every entity type and constraint kind."""
    return {
        "spec_version": 1,
        "source": {
            "image": "input.jpg",
            "sha256": "0" * 64,
            "preflight": "preflight.json",
        },
        "profile": "general",
        "units": {"system": "mm", "declared": True},
        "views": [
            {
                "id": "front",
                "calibration": {
                    "type": "affine",
                    "anchors_px": [[120, 400], [880, 400]],
                    "anchors_cad": [[0, 0], [100, 0]],
                    "evidence": "known",
                },
            }
        ],
        "layers": [
            {"name": "LINEWORK", "color": 7, "linetype": "CONTINUOUS"},
            {"name": "TEXT", "color": 7, "linetype": "CONTINUOUS"},
            {"name": "DIM", "color": 3, "linetype": "CONTINUOUS"},
        ],
        "entities": [
            {
                "id": "e1",
                "type": "line",
                "view": "front",
                "layer": "LINEWORK",
                "evidence": "known",
                "geometry": {"start": [0, 0], "end": [100, 0]},
            },
            {
                "id": "e6",
                "type": "line",
                "view": "front",
                "layer": "LINEWORK",
                "evidence": "known",
                "geometry": {"start": [0, 50], "end": [100, 50]},
            },
            {
                "id": "e7",
                "type": "line",
                "view": "front",
                "layer": "LINEWORK",
                "evidence": "known",
                "geometry": {"start": [40, 0], "end": [60, 0]},
            },
            {
                "id": "e3",
                "type": "arc",
                "view": "front",
                "layer": "LINEWORK",
                "evidence": "scaled",
                "geometry": {
                    "center": [50, 25],
                    "radius": 10,
                    "start_angle": 0,
                    "end_angle": 180,
                },
            },
            {
                "id": "e4",
                "type": "lwpolyline",
                "view": "front",
                "layer": "LINEWORK",
                "evidence": "known",
                "geometry": {"points": [[0, 0], [100, 0], [100, 50]], "closed": True},
            },
            {
                "id": "hole_1",
                "type": "circle",
                "view": "front",
                "layer": "LINEWORK",
                "evidence": "scaled",
                "geometry": {"center": [25, 25], "radius": 5},
            },
            {
                "id": "hole_2",
                "type": "circle",
                "view": "front",
                "layer": "LINEWORK",
                "evidence": "scaled",
                "geometry": {"center": [50, 25], "radius": 5},
            },
            {
                "id": "hole_3",
                "type": "circle",
                "view": "front",
                "layer": "LINEWORK",
                "evidence": "scaled",
                "geometry": {"center": [75, 25], "radius": 5},
            },
            {
                "id": "e5",
                "type": "text",
                "view": "front",
                "layer": "TEXT",
                "evidence": "known",
                "text": "PLAN VIEW",
                "geometry": {"insert": [10, 70], "height": 5, "rotation": 0},
            },
            {
                "id": "d1",
                "type": "dimension",
                "view": "front",
                "layer": "DIM",
                "evidence": "known",
                "text": "100",
                "geometry": {"p1": [0, 0], "p2": [100, 0], "offset": 10, "value": 100},
            },
            {
                "id": "d2",
                "type": "dimension",
                "view": "front",
                "layer": "DIM",
                "evidence": "scaled",
                "text": "50",
                "geometry": {"p1": [0, 50], "p2": [100, 50], "offset": 10, "value": 50},
            },
        ],
        "constraints": [
            {"id": "c1", "kind": "sum", "of": ["d1", "d2"], "equals": 150},
            {"id": "c2", "kind": "positive", "ref": "d1"},
            {"id": "c3", "kind": "inside", "ref": "hole_1", "within": "e4"},
            {"id": "c4", "kind": "count", "of": "hole", "equals": 3},
            {"id": "c5", "kind": "spacing", "of": ["hole_1", "hole_2", "hole_3"]},
            {"id": "c6", "kind": "parallel", "of": ["e1", "e6"]},
            {"id": "c7", "kind": "aligned", "of": ["e1", "e7"]},
        ],
        "assumptions": [],
        "disposition": None,
    }


def self_check() -> int:
    """Draw a valid spec to a tempdir and prove the three named rejection paths."""
    try:
        spec = _valid_spec()
        report = validate_spec(spec)
        _require(report["valid"] is True, f"valid spec must pass: {report['errors']}")
        _require(
            sum(report["evidence_counts"].values()) == len(spec["entities"]),
            "evidence_counts totals",
        )

        with tempfile.TemporaryDirectory(prefix="spec-selfcheck-") as tmp:
            output = Path(tmp) / "redraw.dxf"
            dropped = draw_spec(spec, output)
            _require(
                output.is_file() and output.stat().st_size > 0,
                "valid spec draws to a DXF file",
            )
            _require(dropped == [], "full draw drops nothing")
            check_doc = ezdxf.readfile(str(output))
            _require(
                len(list(check_doc.modelspace())) == len(spec["entities"]),
                "drawn entity count",
            )

        duplicate = copy.deepcopy(spec)
        duplicate["entities"].append(copy.deepcopy(duplicate["entities"][0]))
        codes = {e["code"] for e in validate_spec(duplicate)["errors"]}
        _require(
            "duplicate_id" in codes, f"duplicate id rejected (codes: {sorted(codes)})"
        )

        negative = copy.deepcopy(spec)
        negative["entities"][5]["geometry"]["radius"] = -1
        codes = {e["code"] for e in validate_spec(negative)["errors"]}
        _require(
            "non_positive" in codes,
            f"negative radius rejected (codes: {sorted(codes)})",
        )

        unitless = copy.deepcopy(spec)
        unitless["profile"] = "strict-dimensioned"
        unitless["units"] = {"system": "unitless", "declared": False}
        result = validate_spec(unitless)
        codes = {e["code"] for e in result["errors"]}
        _require(
            "profile" in codes,
            f"strict-dimensioned + unitless blocked (codes: {sorted(codes)})",
        )

        malformed = copy.deepcopy(spec)
        malformed["entities"][0]["geometry"].pop("end")
        result = validate_spec(malformed)
        _require(result["valid"] is False, "malformed geometry fails validation")
        _require(
            any(w["entity"] == "c6" for w in result["warnings"]),
            "parallel over a line without geometry.end skips with a warning",
        )
        zero_length = copy.deepcopy(spec)
        zero_length["entities"][0]["geometry"]["end"] = [0, 0]
        result = validate_spec(zero_length)
        _require(
            any(w["entity"] == "c6" for w in result["warnings"]),
            "parallel over a zero-length line skips with a warning",
        )
        with tempfile.TemporaryDirectory(prefix="spec-selfcheck-cli-") as tmp:
            spec_path = Path(tmp) / "malformed-spec.json"
            spec_path.write_text(json.dumps(malformed), encoding="utf-8")
            proc = subprocess.run(
                [
                    sys.executable,
                    str(Path(__file__).resolve()),
                    "--spec",
                    str(spec_path),
                    "--check-only",
                ],
                capture_output=True,
                text=True,
            )
        _require(proc.returncode == 1, "malformed spec exits 1")
        _require(
            "Traceback" not in proc.stderr + proc.stdout,
            "malformed spec reports without a traceback",
        )
        _require(
            "error [schema]" in proc.stdout and "warning [constraint]" in proc.stdout,
            "malformed spec prints a named report",
        )
    except AssertionError as exc:
        print(str(exc), file=sys.stderr)
        return 1
    print("spec_to_dxf self-check: PASS")
    return 0


def main(argv: list[str] | None = None) -> int:
    """CLI entry: validate (--check-only) and/or draw (--output) a redraw spec."""
    parser = argparse.ArgumentParser(
        description="Validate a redraw spec (references/redraw-spec.md) and draw it to a DXF. "
        "Exit 0 valid/drawn, 1 bad input or invalid spec, 2 environment error."
    )
    parser.add_argument("--spec", help="redraw spec JSON file")
    parser.add_argument("--output", help="output DXF path (draw mode)")
    parser.add_argument(
        "--geometry-only",
        action="store_true",
        help="drop text/mtext/dimension entities when drawing",
    )
    parser.add_argument(
        "--check-only",
        action="store_true",
        help="validate the spec and exit without drawing",
    )
    parser.add_argument(
        "--report", help="write the validation report JSON to this path"
    )
    parser.add_argument(
        "--self-check", action="store_true", help="run built-in checks and exit"
    )
    args = parser.parse_args(argv)

    if args.self_check:
        return self_check()
    if not args.spec:
        parser.error("--spec is required unless --self-check is used")
    if not args.check_only and not args.output:
        parser.error("--output is required in draw mode (or pass --check-only)")

    spec_path = Path(args.spec)
    outputs = [Path(path) for path in (args.output, args.report) if path]
    try:
        ensure_safe_outputs([spec_path], outputs)
    except ValueError as exc:
        print(f"unsafe redraw output: {exc}", file=sys.stderr)
        return 1

    spec = load_spec(spec_path)
    report = validate_spec(spec)
    if args.check_only or not report["valid"]:
        emit_report(report, Path(args.report) if args.report else None)
        if not report["valid"]:
            if not args.check_only:
                print("spec invalid; nothing drawn", file=sys.stderr)
            return 1
        return 0

    output = Path(args.output)
    try:
        dropped = draw_spec(spec, output, args.geometry_only)
    except (OSError, ezdxf.DXFError) as exc:
        print(f"draw failed for '{output}': {exc}", file=sys.stderr)
        return 2
    if args.report:
        try:
            Path(args.report).write_text(
                json.dumps(report, indent=2) + "\n", encoding="utf-8"
            )
        except OSError as exc:
            print(f"cannot write report '{args.report}': {exc}", file=sys.stderr)
            return 1
    total = sum(report["evidence_counts"].values())
    drawn = total - len(dropped)
    print(
        f"drew {drawn} of {total} entities"
        f"{' (dropped ' + str(len(dropped)) + ' annotation entities)' if dropped else ''}"
        f" -> {output}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
