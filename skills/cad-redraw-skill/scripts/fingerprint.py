#!/usr/bin/env python3
"""Fingerprint a DXF/DWG drawing to JSON plus a human-readable redraw prompt."""

import argparse
import json
import math
import shutil
import subprocess
import sys
import tempfile
from collections import Counter
from pathlib import Path
from typing import Any

try:
    import ezdxf
    from ezdxf import bbox
except ImportError:  # pragma: no cover - environment guard
    print("ezdxf is required: pip install ezdxf", file=sys.stderr)
    sys.exit(2)
from ezdxf.lldxf.tagwriter import TagCollector
from path_safety import ensure_safe_outputs

ANNOTATION_TYPES = ("TEXT", "MTEXT", "DIMENSION", "LEADER", "MLEADER")
PROXY_TYPES = ("ACAD_PROXYENTITY", "ACAD_PROXY_OBJECT", "PROXY_ENTITY")
ANONYMOUS_PREFIXES = ("*U",)
GEOMETRY_TOLERANCE = 1e-6


def _is_handle_tag(code: int) -> bool:
    """Return whether a DXF group code carries a volatile handle/reference."""
    return (
        code in {5, 105, 1005, 480, 481}
        or 320 <= code <= 369
        or 390 <= code <= 399
    )


def load_drawing(path: Path) -> tuple[object, str]:
    """Load a DXF natively, or a DWG via odafc then dwg2dxf; exit 2 on no converter."""
    suffix = path.suffix.lower()
    if suffix == ".dxf":
        return _read_dxf(path), "native"
    if suffix != ".dwg":
        print(
            f"unsupported source format: '{path.suffix or '?'}' (expected .dxf/.dwg)",
            file=sys.stderr,
        )
        sys.exit(1)
    doc_or_none, converter = _read_via_odafc(path)
    if doc_or_none is not None:
        return doc_or_none, converter
    doc_or_none = _read_via_dwg2dxf(path)
    if doc_or_none is not None:
        return doc_or_none, "dwg2dxf"
    print(
        f"cannot read DWG '{path}': no DWG converter available.\n"
        "Install ONE of:\n"
        "  1. ODA File Converter (https://www.opendesign.com, free download; used\n"
        "     via ezdxf.addons.odafc; headless servers need QT_QPA_PLATFORM=offscreen)\n"
        "  2. LibreDWG (apt install libredwg-tools, provides the dwg2dxf command)",
        file=sys.stderr,
    )
    sys.exit(2)


def _read_dxf(path: Path) -> object:
    """Read a DXF file, exiting with a named error on unreadable input."""
    try:
        return ezdxf.readfile(str(path))
    except FileNotFoundError:
        print(f"source file not found: {path}", file=sys.stderr)
        sys.exit(1)
    except IOError as exc:
        print(f"cannot read DXF '{path}': {exc}", file=sys.stderr)
        sys.exit(1)
    except ezdxf.DXFError as exc:
        print(f"invalid DXF '{path}': {exc}", file=sys.stderr)
        sys.exit(1)


def _read_via_odafc(path: Path) -> tuple[object | None, str]:
    """Try ODA File Converter via ezdxf.addons.odafc; return (doc, 'odafc') or (None, '')."""
    try:
        from ezdxf.addons import odafc
    except ImportError:
        return None, ""
    import os

    os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
    try:
        return odafc.readfile(str(path)), "odafc"
    except Exception as exc:  # any odafc failure falls through to dwg2dxf
        print(f"odafc conversion failed ({exc}); trying dwg2dxf", file=sys.stderr)
        return None, ""


def _read_via_dwg2dxf(path: Path) -> object | None:
    """Convert with LibreDWG dwg2dxf to a temp DXF and read it; None if unavailable."""
    exe = shutil.which("dwg2dxf")
    if exe is None:
        return None
    with tempfile.TemporaryDirectory(prefix="fingerprint-dwg2dxf-") as tmp:
        out = Path(tmp) / "converted.dxf"
        try:
            proc = subprocess.run(
                [exe, "-o", str(out), str(path)],
                capture_output=True,
                text=True,
                timeout=120,
            )
        except (OSError, subprocess.SubprocessError) as exc:
            print(f"dwg2dxf failed ({exc})", file=sys.stderr)
            return None
        if proc.returncode != 0 or not out.is_file() or out.stat().st_size == 0:
            print(f"dwg2dxf failed (exit {proc.returncode})", file=sys.stderr)
            return None
        return _read_dxf(out)


def build_fingerprint(
    doc: Any, file_name: str, file_format: str, converter: str
) -> dict:
    """Extract the full fingerprint dict from a loaded ezdxf document."""
    msp_entities = list(doc.modelspace())
    ps_entities: list = []
    for layout in doc.layouts:
        if layout.is_any_paperspace:
            ps_entities.extend(layout)
    all_entities = msp_entities + ps_entities
    geometry_signatures = sorted(
        (_entity_geometry_signature(entity, doc.dxfversion) for entity in all_entities),
        key=lambda signature: json.dumps(
            signature, sort_keys=True, separators=(",", ":"), ensure_ascii=False
        ),
    )

    by_type: Counter = Counter(e.dxftype() for e in all_entities)
    for dxftype in ANNOTATION_TYPES:
        by_type.setdefault(dxftype, 0)

    layer_counts: Counter = Counter(e.dxf.get("layer", "0") for e in all_entities)
    layers = [
        {
            "name": layer.dxf.name,
            "color": layer.dxf.get("color", 7),
            "linetype": layer.dxf.get("linetype", "CONTINUOUS"),
            "entity_count": layer_counts.get(layer.dxf.name, 0),
        }
        for layer in doc.layers
    ]

    insert_counts: Counter = Counter(
        e.dxf.get("name", "") for e in all_entities if e.dxftype() == "INSERT"
    )
    blocks = [
        {"name": block.name, "insert_count": insert_counts.get(block.name, 0)}
        for block in doc.blocks
    ]

    box = bbox.extents(all_entities) if all_entities else None
    extents = {
        "min": [round(box.extmin.x, 6), round(box.extmin.y, 6)]
        if box and box.has_data
        else None,
        "max": [round(box.extmax.x, 6), round(box.extmax.y, 6)]
        if box and box.has_data
        else None,
    }

    return {
        "file": {
            "name": file_name,
            "format": file_format,
            "version": doc.dxfversion,
            "producer": _producer(doc),
            "converter": converter,
        },
        "units": doc.units,
        "extents": extents,
        "entities": {
            "total": len(all_entities),
            "modelspace": len(msp_entities),
            "paperspace": len(ps_entities),
            "by_type": dict(sorted(by_type.items())),
        },
        "geometry": {
            "tolerance": GEOMETRY_TOLERANCE,
            "entities": geometry_signatures,
        },
        "annotations": {
            "dimensions": by_type.get("DIMENSION", 0),
            "leaders": by_type.get("LEADER", 0) + by_type.get("MLEADER", 0),
            "text": by_type.get("TEXT", 0),
            "mtext": by_type.get("MTEXT", 0),
        },
        "layers": layers,
        "blocks": blocks,
        "styles": {
            "text_styles": [style.dxf.name for style in doc.styles],
            "dimstyles": [dimstyle.dxf.name for dimstyle in doc.dimstyles],
        },
    }


def _entity_geometry_signature(entity, dxfversion: str) -> dict:
    """Capture canonical DXF tags while excluding volatile entity and owner handles."""
    writer = TagCollector(dxfversion=dxfversion)
    entity.export_dxf(writer)
    tags = [
        [tag.code, _json_tag_value(tag.value)]
        for tag in writer.tags
        if not _is_handle_tag(tag.code)
    ]
    return {"type": entity.dxftype(), "tags": tags}


def _json_tag_value(value):
    """Convert DXF tag values to JSON-safe primitives without losing geometry precision."""
    if isinstance(value, float) and not math.isfinite(value):
        return str(value)
    if isinstance(value, (str, int, float, bool)) or value is None:
        return value
    if isinstance(value, (list, tuple)):
        return [_json_tag_value(item) for item in value]
    return str(value)


def _producer(doc: object) -> str | None:
    """Return the producing application from the $LASTSAVEDBY header, else None."""
    value = doc.header.get("$LASTSAVEDBY", None)
    return value if isinstance(value, str) and value.strip() else None


def build_prompt(fp: dict) -> str:
    """Render the fingerprint as a redraw prompt with validation criteria and risks."""
    file_info = fp["file"]
    entities = fp["entities"]
    annotations = fp["annotations"]
    lines = [
        f"# Redraw prompt — {file_info['name']}",
        "",
        "## Source classification",
        "",
        f"- Format: {file_info['format'].upper()} {file_info['version'] or '(unknown version)'}"
        f" — read via {file_info['converter']}",
        f"- Producer: {file_info['producer'] or 'unknown'}",
        f"- Units ($INSUNITS): {fp['units']}",
        f"- Entities: {entities['total']} total"
        f" ({entities['modelspace']} modelspace, {entities['paperspace']} paperspace)",
    ]
    if fp["extents"]["min"] and fp["extents"]["max"]:
        lo, hi = fp["extents"]["min"], fp["extents"]["max"]
        lines.append(
            f"- Extents: ({lo[0]:.3f}, {lo[1]:.3f}) to ({hi[0]:.3f}, {hi[1]:.3f})"
            f" — {hi[0] - lo[0]:.3f} x {hi[1] - lo[1]:.3f} drawing units"
        )
    lines += [
        "",
        "## Entity inventory",
        "",
        "| Type | Count |",
        "|------|-------|",
    ]
    lines += [
        f"| {dxftype} | {count} |" for dxftype, count in entities["by_type"].items()
    ]
    lines += [
        "",
        "## Annotations",
        "",
        f"- Dimensions: {annotations['dimensions']}",
        f"- Leaders (LEADER + MLEADER): {annotations['leaders']}",
        f"- TEXT: {annotations['text']}, MTEXT: {annotations['mtext']}",
        "",
        "## Layers",
        "",
        "| Name | Color | Linetype | Entities |",
        "|------|-------|----------|----------|",
    ]
    lines += [
        f"| {layer['name']} | {layer['color']} | {layer['linetype']} | {layer['entity_count']} |"
        for layer in fp["layers"]
    ]
    lines += ["", "## Blocks", ""]
    lines += [
        f"- `{block['name']}` ({block['insert_count']} inserts)"
        for block in fp["blocks"]
    ]
    lines += [
        "",
        "## Styles",
        "",
        f"- Text styles: {', '.join(fp['styles']['text_styles']) or 'none'}",
        f"- Dimension styles: {', '.join(fp['styles']['dimstyles']) or 'none'}",
        "",
        "## Validation criteria (fingerprint_diff gate)",
        "",
        "The rebuild is accepted only when, compared to this fingerprint:",
        "",
        "- entity counts match per type and per space (modelspace/paperspace);",
        f"- per-entity DXF geometry signatures match within tolerance {GEOMETRY_TOLERANCE:g};",
        "- every layer, block, text style, and dimension style listed here exists in the target;",
        (
            f"- dimensions ({annotations['dimensions']}), leaders ({annotations['leaders']}),"
            f" text ({annotations['text']}), and MTEXT ({annotations['mtext']}) counts match —"
            " a missing dimension or leader is a FAILURE, never a warning;"
        ),
        "- extents agree within 1e-6 drawing units.",
        "",
        "## Risk notes",
        "",
    ]
    risks = _risk_notes(fp)
    lines += [f"- {risk}" for risk in risks] or ["- None identified."]
    return "\n".join(lines) + "\n"


def _risk_notes(fp: dict) -> list[str]:
    """Derive risk notes from fingerprint data per references/linux-toolchain.md."""
    risks: list[str] = []
    file_info = fp["file"]
    by_type = fp["entities"]["by_type"]
    if file_info["converter"] != "native":
        risks.append(
            f"DWG read via {file_info['converter']}: conversion fidelity is unproven until the"
            " fingerprint diff passes; proxy objects, SHX glyphs, annotative dimension variants,"
            " and dynamic blocks may degrade (see references/linux-toolchain.md)."
        )
    proxies = [t for t in by_type if t in PROXY_TYPES]
    if proxies:
        risks.append(
            f"Proxy/custom entities present ({', '.join(proxies)}): dropped or exploded outside"
            " their origin application; validate visually."
        )
    anonymous = [
        b["name"] for b in fp["blocks"] if b["name"].startswith(ANONYMOUS_PREFIXES)
    ]
    if anonymous:
        risks.append(
            f"Anonymous blocks present ({len(anonymous)}): likely dynamic blocks whose lookup"
            " tables and actions do not translate."
        )
    dims = fp["annotations"]["dimensions"]
    if dims == 0:
        risks.append(
            "No dimensions in the source: a rebuild cannot be dimension-validated;"
            " prefer a visual-trace/unitless profile."
        )
    if fp["entities"]["paperspace"] > 0:
        count = fp["entities"]["paperspace"]
        risks.append(
            f"Paperspace content present ({count} "
            f"entit{'y' if count == 1 else 'ies'}):"
            " keep layouts in the rebuild or state the omission."
        )
    return risks


def write_outputs(fp: dict, prompt: str, prefix: Path) -> tuple[Path, Path]:
    """Write <prefix>-fingerprint.json and <prefix>-redraw-prompt.md; return both paths."""
    json_path = Path(f"{prefix}-fingerprint.json")
    prompt_path = Path(f"{prefix}-redraw-prompt.md")
    json_path.write_text(json.dumps(fp, indent=2) + "\n", encoding="utf-8")
    prompt_path.write_text(prompt, encoding="utf-8")
    return json_path, prompt_path


def _require(condition: bool, field: str) -> None:
    """Raise an AssertionError naming the fingerprint field when condition fails."""
    if not condition:
        raise AssertionError(f"self-check failed: {field}")


def build_fixture() -> object:
    """Build an in-memory ezdxf doc covering every fingerprint section."""
    doc = ezdxf.new("R2010", setup=True)
    doc.units = 4
    doc.layers.add("WALLS", color=1, linetype="CONTINUOUS")
    doc.layers.add("DIM", color=3, linetype="CONTINUOUS")
    msp = doc.modelspace()
    msp.add_line((0, 0), (100, 0), dxfattribs={"layer": "WALLS"})
    msp.add_line((0, 0), (0, 60), dxfattribs={"layer": "WALLS"})
    msp.add_circle((30, 30), radius=5, dxfattribs={"layer": "0"})
    msp.add_arc((60, 30), radius=8, start_angle=0, end_angle=180)
    msp.add_lwpolyline(
        [(0, 0), (100, 0), (100, 60)], close=True, dxfattribs={"layer": "WALLS"}
    )
    msp.add_text("TITLE", dxfattribs={"layer": "0", "height": 5}).set_placement(
        (10, 70)
    )
    msp.add_mtext(
        "NOTES", dxfattribs={"layer": "0", "char_height": 4, "insert": (10, 80)}
    )
    dim = msp.add_aligned_dim(
        p1=(0, 0), p2=(100, 0), distance=10, text="100", dimstyle="EZDXF"
    )
    dim.render()
    doc.blocks.new("BOLT", dxfattribs={"base_point": (0, 0)})
    msp.add_blockref("BOLT", insert=(40, 40), dxfattribs={"layer": "0"})
    doc.paperspace().add_line((0, 0), (50, 0))
    return doc


def self_check() -> int:
    """Fingerprint an in-memory fixture and assert every section is populated."""
    try:
        doc = build_fixture()
        fp = build_fingerprint(doc, "fixture.dxf", "dxf", "native")
        with tempfile.TemporaryDirectory(prefix="fingerprint-selfcheck-") as tmp:
            json_path, prompt_path = write_outputs(
                fp, build_prompt(fp), Path(tmp) / "fx"
            )
            _require(
                json_path.is_file() and json_path.stat().st_size > 0,
                "file: json written",
            )
            _require(
                prompt_path.is_file() and prompt_path.stat().st_size > 0,
                "file: prompt written",
            )
        _require(fp["file"]["format"] == "dxf", "file.format")
        _require(fp["file"]["version"] == "AC1024", "file.version")
        _require(fp["file"]["converter"] == "native", "file.converter")
        _require(isinstance(fp["file"]["producer"], (str, type(None))), "file.producer")
        _require(fp["units"] == 4, "units")
        _require(
            fp["extents"]["min"] is not None and fp["extents"]["max"] is not None,
            "extents",
        )
        _require(
            len(fp["extents"]["min"]) == 2 and len(fp["extents"]["max"]) == 2,
            "extents size",
        )
        _require(fp["entities"]["total"] == 10, "entities.total")
        _require(
            fp["entities"]["total"]
            == fp["entities"]["modelspace"] + fp["entities"]["paperspace"],
            "entities.total == modelspace + paperspace",
        )
        _require(
            len(fp["geometry"]["entities"]) == fp["entities"]["total"],
            "geometry signature count",
        )
        _require(
            all(
                not _is_handle_tag(tag[0])
                for item in fp["geometry"]["entities"]
                for tag in item["tags"]
            ),
            "geometry signatures omit volatile handles and owner references",
        )
        _require(fp["entities"]["modelspace"] == 9, "entities.modelspace")
        _require(fp["entities"]["paperspace"] == 1, "entities.paperspace")
        _require(fp["entities"]["by_type"]["LINE"] == 3, "entities.by_type.LINE")
        _require(
            fp["entities"]["by_type"]["LWPOLYLINE"] == 1, "entities.by_type.LWPOLYLINE"
        )
        _require(fp["entities"]["by_type"]["CIRCLE"] == 1, "entities.by_type.CIRCLE")
        _require(fp["entities"]["by_type"]["ARC"] == 1, "entities.by_type.ARC")
        _require(
            fp["entities"]["by_type"]["DIMENSION"] == 1, "entities.by_type.DIMENSION"
        )
        _require(fp["annotations"]["dimensions"] == 1, "annotations.dimensions")
        _require(fp["annotations"]["leaders"] == 0, "annotations.leaders")
        _require(fp["annotations"]["text"] == 1, "annotations.text")
        _require(fp["annotations"]["mtext"] == 1, "annotations.mtext")
        walls = next(layer for layer in fp["layers"] if layer["name"] == "WALLS")
        _require(walls["entity_count"] == 3, "layers.WALLS.entity_count")
        _require(
            any(
                layer["name"] == "WALLS" and layer["color"] == 1
                for layer in fp["layers"]
            ),
            "layers.WALLS.color",
        )
        bolt = next(b for b in fp["blocks"] if b["name"] == "BOLT")
        _require(bolt["insert_count"] == 1, "blocks.BOLT.insert_count")
        _require("Standard" in fp["styles"]["text_styles"], "styles.text_styles")
        _require("EZDXF" in fp["styles"]["dimstyles"], "styles.dimstyles")
        prompt = build_prompt(fp)
        for section in (
            "## Source classification",
            "## Validation criteria",
            "## Risk notes",
        ):
            _require(section in prompt, f"prompt section {section!r}")
    except AssertionError as exc:
        print(str(exc), file=sys.stderr)
        return 1
    print("fingerprint self-check: PASS")
    return 0


def main(argv: list[str] | None = None) -> int:
    """CLI entry: fingerprint --source into --output prefix."""
    parser = argparse.ArgumentParser(
        description="Fingerprint a DXF/DWG drawing: write <prefix>-fingerprint.json "
        "and <prefix>-redraw-prompt.md."
    )
    parser.add_argument("--source", help="input .dxf or .dwg file to fingerprint")
    parser.add_argument("--output", help="output path prefix for the two report files")
    parser.add_argument(
        "--json", action="store_true", help="also print the fingerprint JSON to stdout"
    )
    parser.add_argument(
        "--self-check", action="store_true", help="run built-in checks and exit"
    )
    args = parser.parse_args(argv)

    if args.self_check:
        return self_check()
    if not args.source or not args.output:
        parser.error("--source and --output are required unless --self-check is used")

    source = Path(args.source)
    prefix = Path(args.output)
    try:
        ensure_safe_outputs(
            [source],
            [
                Path(f"{prefix}-fingerprint.json"),
                Path(f"{prefix}-redraw-prompt.md"),
            ],
        )
    except ValueError as exc:
        print(f"unsafe fingerprint output: {exc}", file=sys.stderr)
        return 1
    doc, converter = load_drawing(source)
    fp = build_fingerprint(
        doc, source.name, "dxf" if source.suffix.lower() == ".dxf" else "dwg", converter
    )
    try:
        json_path, prompt_path = write_outputs(fp, build_prompt(fp), Path(args.output))
    except OSError as exc:
        print(
            f"cannot write fingerprint outputs '{args.output}': {exc}", file=sys.stderr
        )
        return 1
    print(f"fingerprint: {json_path}")
    print(f"redraw prompt: {prompt_path}")
    print(
        f"summary: {fp['entities']['total']} entities "
        f"({fp['entities']['modelspace']} msp + {fp['entities']['paperspace']} psp), "
        f"{fp['annotations']['dimensions']} dimensions, {len(fp['layers'])} layers, "
        f"converter={converter}"
    )
    if args.json:
        print(json.dumps(fp, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
