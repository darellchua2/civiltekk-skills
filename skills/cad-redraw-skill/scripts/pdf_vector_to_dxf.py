#!/usr/bin/env python3
"""Extract vector paths and real text from one PDF page into a generic-layer DXF."""

import argparse
import sys
import tempfile
from pathlib import Path

from path_safety import ensure_safe_outputs

try:
    import ezdxf
    from ezdxf.path import Path as EzdxfPath
except ImportError:  # pragma: no cover - environment guard
    print("ezdxf is required: pip install ezdxf", file=sys.stderr)
    sys.exit(2)
try:
    import pymupdf
except ImportError:  # pragma: no cover - environment guard
    print("pymupdf is required: pip install pymupdf", file=sys.stderr)
    sys.exit(2)

PT_TO_MM = 25.4 / 72.0  # 1 PDF point = 0.3528 mm — documented constant, not applied
BEZIER_TOLERANCE = 0.1  # flattening distance in PDF points
LAYERS = {"LINEWORK": 7, "TEXT": 7, "BORDER": 8, "DIM": 3}


def _pt(x: float, y: float, page_height: float) -> tuple[float, float]:
    """Map a PyMuPDF coordinate (top-left origin) to DXF space (bottom-left origin)."""
    return (float(x), page_height - float(y))


def _add_segment(msp, start, end, layer: str) -> int:
    """Add one LINE entity on layer; return 1 for uniform counting."""
    msp.add_line(start, end, dxfattribs={"layer": layer})
    return 1


def _add_ring(msp, corners, page_height: float, layer: str) -> int:
    """Close a corner ring with LINE entities on layer."""
    points = [_pt(x, y, page_height) for x, y in corners]
    points.append(points[0])
    for start, end in zip(points, points[1:]):
        _add_segment(msp, start, end, layer)
    return len(points) - 1


def _add_cubic(msp, p1, c1, c2, p4, page_height: float) -> int:
    """Flatten one cubic Bézier into LINE segments at BEZIER_TOLERANCE."""
    path = EzdxfPath(_pt(p1.x, p1.y, page_height))
    path.curve4_to(
        _pt(p4.x, p4.y, page_height),
        _pt(c1.x, c1.y, page_height),
        _pt(c2.x, c2.y, page_height),
    )
    points = [(v.x, v.y) for v in path.flattening(BEZIER_TOLERANCE)]
    for start, end in zip(points, points[1:]):
        _add_segment(msp, start, end, "LINEWORK")
    return max(len(points) - 1, 0)


def _add_path_items(msp, drawing: dict, page_height: float) -> int:
    """Flatten one PDF drawing (strokes and fills) into LINE entities on LINEWORK."""
    count = 0
    for item in drawing["items"]:
        op = item[0]
        if op == "l":
            count += _add_segment(
                msp,
                _pt(item[1].x, item[1].y, page_height),
                _pt(item[2].x, item[2].y, page_height),
                "LINEWORK",
            )
        elif op == "re":
            rect = item[1]
            corners = [
                (rect.x0, rect.y0),
                (rect.x1, rect.y0),
                (rect.x1, rect.y1),
                (rect.x0, rect.y1),
            ]
            count += _add_ring(msp, corners, page_height, "LINEWORK")
        elif op == "qu":
            quad = item[1]
            corners = [
                (quad.ul.x, quad.ul.y),
                (quad.ur.x, quad.ur.y),
                (quad.lr.x, quad.lr.y),
                (quad.ll.x, quad.ll.y),
            ]
            count += _add_ring(msp, corners, page_height, "LINEWORK")
        elif op == "c":
            count += _add_cubic(msp, item[1], item[2], item[3], item[4], page_height)
    return count


def extract_page(pdf_path: Path, page_number: int, output: Path) -> dict:
    """Extract one PDF page into a DXF; return entity counts for the summary."""
    try:
        doc = pymupdf.open(str(pdf_path))
    except Exception as exc:
        print(f"cannot open PDF '{pdf_path}': {exc}", file=sys.stderr)
        sys.exit(1)
    if page_number < 1 or page_number > doc.page_count:
        print(
            f"page {page_number} does not exist: '{pdf_path}' has"
            f" {doc.page_count} page(s)",
            file=sys.stderr,
        )
        sys.exit(1)
    page = doc[page_number - 1]
    drawings = page.get_drawings()
    words = page.get_text("words")
    if not drawings and not words:
        print(
            f"page {page_number} of '{pdf_path}' has no vector or text content",
            file=sys.stderr,
        )
        sys.exit(1)

    page_height = page.rect.height
    dxf = ezdxf.new("R2010", setup=True)
    dxf.units = 0  # unitless: coordinates are PDF points, scale is unverified
    for name, color in LAYERS.items():
        dxf.layers.add(name, color=color)
    msp = dxf.modelspace()

    lines = _add_ring(
        msp,
        [
            (page.rect.x0, page.rect.y0),
            (page.rect.x1, page.rect.y0),
            (page.rect.x1, page.rect.y1),
            (page.rect.x0, page.rect.y1),
        ],
        page_height,
        "BORDER",
    )
    for drawing in drawings:
        lines += _add_path_items(msp, drawing, page_height)

    texts = 0
    for word in words:
        x0, y0, _, y1, text = word[0], word[1], word[2], word[3], word[4]
        if not text.strip():
            continue
        msp.add_text(
            text,
            dxfattribs={"layer": "TEXT", "height": max(y1 - y0, 0.1)},
        ).set_placement(_pt(x0, y1, page_height))
        texts += 1

    try:
        dxf.saveas(str(output))
    except OSError as exc:
        print(f"cannot write DXF '{output}': {exc}", file=sys.stderr)
        sys.exit(1)
    doc.close()
    return {"lines": lines, "texts": texts}


def _require(condition: bool, what: str) -> None:
    """Raise an AssertionError naming the failed self-check expectation."""
    if not condition:
        raise AssertionError(f"self-check failed: {what}")


def _build_pdf(path: Path) -> None:
    """Write a one-page PDF with a line, a rectangle, and one text word."""
    doc = pymupdf.open()
    page = doc.new_page(width=400, height=300)
    page.draw_line(pymupdf.Point(20, 20), pymupdf.Point(380, 280))
    page.draw_rect(pymupdf.Rect(40, 40, 360, 260))
    page.insert_text((50, 30), "TITLE")
    doc.save(str(path))
    doc.close()


def self_check() -> int:
    """Extract a generated single-page PDF and assert real DXF content."""
    try:
        with tempfile.TemporaryDirectory(prefix="pdf-selfcheck-") as tmp:
            tmp_path = Path(tmp)
            pdf = tmp_path / "fixture.pdf"
            dxf_path = tmp_path / "fixture.dxf"
            _build_pdf(pdf)
            counts = extract_page(pdf, 1, dxf_path)
            _require(dxf_path.is_file() and dxf_path.stat().st_size > 0, "DXF written")
            doc = ezdxf.readfile(str(dxf_path))
            msp = doc.modelspace()
            linework = msp.query('LINE[layer=="LINEWORK"]')
            texts = msp.query('TEXT[layer=="TEXT"]')
            border = msp.query('LINE[layer=="BORDER"]')
            _require(len(linework) >= 1, "at least one LINE on LINEWORK")
            _require(len(texts) >= 1, "at least one TEXT on TEXT")
            _require(len(border) >= 4, "page border drawn on BORDER")
            _require(counts["lines"] == len(linework) + len(border), "counts agree")
            _require(counts["texts"] == len(texts), "text counts agree")
            _require(int(doc.units) == 0, "units stay unitless")
    except AssertionError as exc:
        print(str(exc), file=sys.stderr)
        return 1
    except Exception as exc:
        print(f"pdf_vector self-check raised: {exc}", file=sys.stderr)
        return 1
    print("pdf_vector_to_dxf self-check: PASS")
    return 0


def main(argv: list[str] | None = None) -> int:
    """CLI entry. Exit 0 extracted, 1 bad page/PDF, 2 environment."""
    parser = argparse.ArgumentParser(
        description=(
            "Extract vector paths and real text from one PDF page into a DXF on"
            " generic layers (LINEWORK, TEXT, BORDER, DIM). Coordinates stay in PDF"
            " points with origin bottom-left (Y flipped from PyMuPDF's top-left);"
            f" 1 pt = {PT_TO_MM:.4f} mm. Units stay unitless — declare units only"
            " after verifying scale. Fill-only paths land on LINEWORK too; text is"
            " written as TEXT only when PyMuPDF can extract it."
        ),
        epilog="Mode B intermediate: PDF-derived, never claimed as original-CAD-exact.",
    )
    parser.add_argument("--pdf", help="input PDF file")
    parser.add_argument("--output", help="output DXF path")
    parser.add_argument(
        "--page", type=int, default=1, help="1-based page number to extract (default 1)"
    )
    parser.add_argument(
        "--self-check", action="store_true", help="run built-in checks and exit"
    )
    args = parser.parse_args(argv)

    if args.self_check:
        return self_check()
    if not (args.pdf and args.output):
        parser.error("--pdf and --output are required unless --self-check is used")

    try:
        ensure_safe_outputs([Path(args.pdf)], [Path(args.output)])
    except ValueError as exc:
        print(f"unsafe PDF conversion output: {exc}", file=sys.stderr)
        return 1

    counts = extract_page(Path(args.pdf), args.page, Path(args.output))
    print(
        f"pdf_vector_to_dxf: {args.output} — {counts['lines']} LINE (incl. border),"
        f" {counts['texts']} TEXT; PDF-derived intermediate in PDF points"
        f" (1 pt = {PT_TO_MM:.4f} mm), units unitless"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
