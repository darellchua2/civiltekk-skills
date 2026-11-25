#!/usr/bin/env python3
"""Compare two fingerprint JSON files per references/validation.md and report every mismatch."""

import argparse
import copy
import json
import math
import sys
from pathlib import Path

from path_safety import ensure_safe_outputs

DEFAULT_TOLERANCE = 1e-6
ANNOTATION_KEYS = ("dimensions", "leaders", "text", "mtext")
SPACE_KEYS = ("modelspace", "paperspace")


def _parse_tolerance(value: str) -> float:
    """Parse a finite, non-negative comparison tolerance."""
    try:
        tolerance = float(value)
    except ValueError as exc:
        raise argparse.ArgumentTypeError("tolerance must be a number") from exc
    if not math.isfinite(tolerance) or tolerance < 0:
        raise argparse.ArgumentTypeError(
            "tolerance must be finite and non-negative"
        )
    return tolerance


def _signature_parts(signature: dict) -> tuple[tuple, tuple[float, ...]]:
    """Split a signature into an exact grouping key and tolerant float values."""
    tags = signature["tags"]
    if not isinstance(tags, list):
        raise TypeError("tags must be a list")
    key: list[tuple[object, ...]] = []
    numbers: list[float] = []
    for tag in tags:
        if not isinstance(tag, list) or len(tag) != 2 or not isinstance(tag[0], int):
            raise TypeError("each tag must be a [group-code, value] pair")
        code, value = tag
        if type(value) is float and math.isfinite(value):
            key.append((code, "float"))
            numbers.append(value)
        else:
            key.append((code, type(value).__name__, json.dumps(value, sort_keys=True)))
    return (signature["type"], tuple(key)), tuple(numbers)


def _geometry_mismatches(source: dict, target: dict, tolerance: float) -> list[dict]:
    """Compare per-entity DXF signatures independent of entity order and handles."""
    source_geometry, target_geometry = source.get("geometry"), target.get("geometry")
    source_items = source_geometry.get("entities") if isinstance(source_geometry, dict) else None
    target_items = target_geometry.get("entities") if isinstance(target_geometry, dict) else None
    if not isinstance(source_items, list) or not isinstance(target_items, list):
        return [
            {
                "check": "geometry",
                "source": None,
                "target": None,
                "message": (
                    "fingerprint lacks per-entity geometry signatures; regenerate both "
                    "fingerprints with the current script"
                ),
            }
        ]

    source_groups: dict[tuple, list[tuple[tuple[float, ...], dict]]] = {}
    target_groups: dict[tuple, list[tuple[tuple[float, ...], dict]]] = {}
    try:
        for entries, groups in (
            (source_items, source_groups),
            (target_items, target_groups),
        ):
            for signature in entries:
                if not isinstance(signature, dict) or not isinstance(
                    signature.get("type"), str
                ):
                    raise TypeError("entity signature must have a type and tags")
                key, numbers = _signature_parts(signature)
                groups.setdefault(key, []).append((numbers, signature))
    except (TypeError, ValueError, json.JSONDecodeError) as exc:
        return [
            {
                "check": "geometry",
                "source": len(source_items),
                "target": len(target_items),
                "message": f"invalid geometry signatures: {exc}",
            }
        ]

    mismatches = []
    for key in sorted(set(source_groups) | set(target_groups), key=repr):
        source_group = sorted(source_groups.get(key, []), key=lambda item: item[0])
        target_group = sorted(target_groups.get(key, []), key=lambda item: item[0])
        changed = sum(
            any(abs(a - b) > tolerance for a, b in zip(source_numbers, target_numbers))
            for (source_numbers, _), (target_numbers, _) in zip(
                source_group, target_group
            )
        )
        missing = max(0, len(source_group) - len(target_group))
        extra = max(0, len(target_group) - len(source_group))
        if changed or missing or extra:
            entity_type = key[0]
            mismatches.append(
                {
                    "check": "geometry",
                    "source": len(source_group),
                    "target": len(target_group),
                    "message": (
                        f"{entity_type} geometry signatures differ: {changed} changed, "
                        f"{missing} missing, {extra} extra (tolerance {tolerance:g})"
                    ),
                }
            )

    for label, entities, fingerprints in (
        ("source", source["entities"]["total"], source_items),
        ("target", target["entities"]["total"], target_items),
    ):
        if len(fingerprints) != entities:
            mismatches.append(
                {
                    "check": "geometry",
                    "source": len(source_items),
                    "target": len(target_items),
                    "message": (
                        f"{label} geometry signature count {len(fingerprints)} does not "
                        f"match entity total {entities}"
                    ),
                }
            )
    return mismatches


def _geometry_count(fingerprint: dict) -> int:
    """Return the available signature count without trusting malformed metadata."""
    geometry = fingerprint.get("geometry")
    entities = geometry.get("entities") if isinstance(geometry, dict) else None
    return len(entities) if isinstance(entities, list) else 0


def compare_fingerprints(source: dict, target: dict, tolerance: float) -> dict:
    """Return the full delta report; 'match' is True only when every gate check passes."""
    if not math.isfinite(tolerance) or tolerance < 0:
        raise ValueError("tolerance must be finite and non-negative")
    mismatches: list[dict] = []

    src_types = source["entities"]["by_type"]
    tgt_types = target["entities"]["by_type"]
    for dxftype in sorted(set(src_types) | set(tgt_types)):
        src_count, tgt_count = src_types.get(dxftype, 0), tgt_types.get(dxftype, 0)
        if src_count != tgt_count:
            mismatches.append(
                {
                    "check": "entity_type",
                    "source": src_count,
                    "target": tgt_count,
                    "message": f"entity count for {dxftype}: source={src_count} target={tgt_count}",
                }
            )

    for space in SPACE_KEYS:
        src_count = source["entities"][space]
        tgt_count = target["entities"][space]
        if src_count != tgt_count:
            mismatches.append(
                {
                    "check": space,
                    "source": src_count,
                    "target": tgt_count,
                    "message": f"{space} entity count: source={src_count} target={tgt_count}",
                }
            )
    src_total = source["entities"]["total"]
    tgt_total = target["entities"]["total"]
    if src_total != tgt_total:
        mismatches.append(
            {
                "check": "total",
                "source": src_total,
                "target": tgt_total,
                "message": f"total entity count: source={src_total} target={tgt_total}",
            }
        )

    tgt_layers = {layer["name"] for layer in target["layers"]}
    for layer in source["layers"]:
        if layer["name"] not in tgt_layers:
            mismatches.append(
                {
                    "check": "layer",
                    "source": layer["name"],
                    "target": None,
                    "message": f"source layer '{layer['name']}' missing in target",
                }
            )
    tgt_blocks = {block["name"] for block in target["blocks"]}
    for block in source["blocks"]:
        if block["name"] not in tgt_blocks:
            mismatches.append(
                {
                    "check": "block",
                    "source": block["name"],
                    "target": None,
                    "message": f"source block '{block['name']}' missing in target",
                }
            )
    for style_key in ("text_styles", "dimstyles"):
        tgt_styles = set(target["styles"][style_key])
        for name in source["styles"][style_key]:
            if name not in tgt_styles:
                label = (
                    "text style" if style_key == "text_styles" else "dimension style"
                )
                mismatches.append(
                    {
                        "check": style_key,
                        "source": name,
                        "target": None,
                        "message": f"source {label} '{name}' missing in target",
                    }
                )

    for key in ANNOTATION_KEYS:
        src_count = source["annotations"][key]
        tgt_count = target["annotations"][key]
        if src_count != tgt_count:
            note = (
                " — missing dimensions in the target is a FAILURE, never a warning"
                if key in ("dimensions", "leaders") and src_count > tgt_count
                else ""
            )
            mismatches.append(
                {
                    "check": key,
                    "source": src_count,
                    "target": tgt_count,
                    "message": f"{key}: source={src_count} target={tgt_count}{note}",
                }
            )

    for extent_key, axis_pairs in (
        ("min", (source["extents"]["min"], target["extents"]["min"])),
        ("max", (source["extents"]["max"], target["extents"]["max"])),
    ):
        src_pt, tgt_pt = axis_pairs
        if src_pt is None and tgt_pt is None:
            continue
        if src_pt is None or tgt_pt is None:
            mismatches.append(
                {
                    "check": "extents",
                    "source": src_pt,
                    "target": tgt_pt,
                    "message": f"extents {extent_key}: source={src_pt} target={tgt_pt}",
                }
            )
            continue
        for axis, src_val, tgt_val in zip("xy", src_pt, tgt_pt):
            if abs(src_val - tgt_val) > tolerance:
                mismatches.append(
                    {
                        "check": "extents",
                        "source": src_val,
                        "target": tgt_val,
                        "message": (
                            f"extents {extent_key}[{axis}]: source={src_val} "
                            f"target={tgt_val} differ by {abs(src_val - tgt_val):.3g} "
                            f"(tolerance {tolerance:g})"
                        ),
                    }
                )

    mismatches.extend(_geometry_mismatches(source, target, tolerance))

    return {
        "match": not mismatches,
        "tolerance": tolerance,
        "mismatches": mismatches,
        "compared": {
            "entity_types": sorted(set(src_types) | set(tgt_types)),
            "spaces": list(SPACE_KEYS),
            "totals": {"source": src_total, "target": tgt_total},
            "layers": {
                "source": len(source["layers"]),
                "target": len(target["layers"]),
            },
            "blocks": {
                "source": len(source["blocks"]),
                "target": len(target["blocks"]),
            },
            "text_styles": {
                "source": len(source["styles"]["text_styles"]),
                "target": len(target["styles"]["text_styles"]),
            },
            "dimstyles": {
                "source": len(source["styles"]["dimstyles"]),
                "target": len(target["styles"]["dimstyles"]),
            },
            "annotations": list(ANNOTATION_KEYS),
            "extents": True,
            "geometry": {
                "source": _geometry_count(source),
                "target": _geometry_count(target),
                "tolerance": tolerance,
            },
        },
        "extra_in_target": {
            "layers": sorted(
                {layer["name"] for layer in target["layers"]}
                - {layer["name"] for layer in source["layers"]}
            ),
            "blocks": sorted(
                {block["name"] for block in target["blocks"]}
                - {block["name"] for block in source["blocks"]}
            ),
        },
    }


def format_summary(delta: dict) -> str:
    """Render the human summary: one line per mismatch, plus the compared-what footer."""
    compared = delta["compared"]
    lines = []
    for mismatch in delta["mismatches"]:
        lines.append(f"MISMATCH [{mismatch['check']}] {mismatch['message']}")
    if delta["match"]:
        lines.append(
            f"PASS: fingerprints match within tolerance {delta['tolerance']:g} "
            f"(compared {len(compared['entity_types'])} entity types, spaces "
            f"{'+'.join(compared['spaces'])}, {compared['layers']['source']} source layers, "
            f"{compared['blocks']['source']} blocks, "
            f"{compared['text_styles']['source']} text styles, "
            f"{compared['dimstyles']['source']} dim styles, "
            f"annotations {', '.join(compared['annotations'])}, extents, "
            f"{compared['geometry']['source']} entity geometry signatures)"
        )
    else:
        lines.append(f"FAIL: {len(delta['mismatches'])} mismatch(es)")
    return "\n".join(lines)


def _load_fingerprint(path: Path) -> dict:
    """Load a fingerprint JSON file, exiting with a named error on failure."""
    try:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
    except FileNotFoundError:
        print(f"fingerprint file not found: {path}", file=sys.stderr)
        sys.exit(1)
    except json.JSONDecodeError as exc:
        print(f"invalid fingerprint JSON '{path}': {exc}", file=sys.stderr)
        sys.exit(1)
    if (
        not isinstance(data, dict)
        or "entities" not in data
        or "annotations" not in data
    ):
        print(f"not a fingerprint file: {path}", file=sys.stderr)
        sys.exit(1)
    return data


def _fixture() -> dict:
    """Build a minimal but complete fingerprint dict in memory."""
    return {
        "file": {
            "name": "a.dxf",
            "format": "dxf",
            "version": "AC1024",
            "producer": None,
            "converter": "native",
        },
        "units": 4,
        "extents": {"min": [0.0, 0.0], "max": [100.0, 50.0]},
        "entities": {
            "total": 7,
            "modelspace": 7,
            "paperspace": 0,
            "by_type": {"LINE": 4, "CIRCLE": 1, "DIMENSION": 2, "TEXT": 0, "MTEXT": 0},
        },
        "annotations": {"dimensions": 2, "leaders": 0, "text": 0, "mtext": 0},
        "layers": [
            {"name": "0", "color": 7, "linetype": "CONTINUOUS", "entity_count": 5},
            {"name": "DIM", "color": 3, "linetype": "CONTINUOUS", "entity_count": 2},
        ],
        "blocks": [{"name": "BOLT", "insert_count": 1}],
        "styles": {"text_styles": ["Standard"], "dimstyles": ["Standard", "EZDXF"]},
        "geometry": {
            "tolerance": DEFAULT_TOLERANCE,
            "entities": [
                *({"type": "LINE", "tags": [[10, float(i)]]} for i in range(4)),
                {"type": "CIRCLE", "tags": [[10, 30.0]]},
                *({"type": "DIMENSION", "tags": [[10, float(i)]]} for i in range(2)),
            ],
        },
    }


def _require(condition: bool, what: str) -> None:
    """Raise an AssertionError naming the failed self-check expectation."""
    if not condition:
        raise AssertionError(f"self-check failed: {what}")


def self_check() -> int:
    """Prove drift detection: identical pair passes, one-removed dimension fails."""
    try:
        source = _fixture()
        identical = compare_fingerprints(
            source, copy.deepcopy(source), DEFAULT_TOLERANCE
        )
        _require(identical["match"] is True, "identical pair must match")
        _require(
            identical["mismatches"] == [], "identical pair must have zero mismatches"
        )

        drifted = copy.deepcopy(source)
        drifted["annotations"]["dimensions"] = 1
        drifted["entities"]["by_type"]["DIMENSION"] = 1
        drifted["entities"]["total"] = 6
        delta = compare_fingerprints(source, drifted, DEFAULT_TOLERANCE)
        _require(delta["match"] is False, "drifted pair must not match")
        named = [
            m
            for m in delta["mismatches"]
            if "dimensions" in m["message"] or m["check"] == "dimensions"
        ]
        _require(bool(named), "dimension drift must name 'dimensions'")
        summary = format_summary(delta)
        _require("dimensions" in summary, "human summary must name 'dimensions'")
        _require(delta["compared"]["extents"] is True, "extents must be compared")
    except AssertionError as exc:
        print(str(exc), file=sys.stderr)
        return 1
    print(
        format_summary(
            compare_fingerprints(source, copy.deepcopy(source), DEFAULT_TOLERANCE)
        )
    )
    print(format_summary(delta))
    print("fingerprint_diff self-check: PASS")
    return 0


def main(argv: list[str] | None = None) -> int:
    """CLI entry: diff source vs target fingerprint; exit 0 only on a full match."""
    parser = argparse.ArgumentParser(
        description="Compare two fingerprint JSON files (see references/validation.md): "
        "exit 0 only when entity counts, layers, blocks, styles, annotations, "
        "extents, and per-entity geometry signatures all agree."
    )
    parser.add_argument("--source", help="source fingerprint JSON path")
    parser.add_argument("--target", help="target fingerprint JSON path")
    parser.add_argument(
        "--tolerance",
        type=_parse_tolerance,
        default=DEFAULT_TOLERANCE,
        help=f"geometry/extents tolerance in drawing units (default {DEFAULT_TOLERANCE:g})",
    )
    parser.add_argument("--json", help="write the full delta JSON to this path")
    parser.add_argument(
        "--self-check", action="store_true", help="run built-in checks and exit"
    )
    args = parser.parse_args(argv)

    if args.self_check:
        return self_check()
    if not args.source or not args.target:
        parser.error("--source and --target are required unless --self-check is used")

    if args.json:
        try:
            ensure_safe_outputs(
                [Path(args.source), Path(args.target)], [Path(args.json)]
            )
        except ValueError as exc:
            print(f"unsafe diff report path: {exc}", file=sys.stderr)
            return 1

    delta = compare_fingerprints(
        _load_fingerprint(Path(args.source)),
        _load_fingerprint(Path(args.target)),
        args.tolerance,
    )
    print(format_summary(delta))
    if args.json:
        Path(args.json).write_text(json.dumps(delta, indent=2) + "\n", encoding="utf-8")
    else:
        print(json.dumps(delta, indent=2))
    return 0 if delta["match"] else 1


if __name__ == "__main__":
    sys.exit(main())
