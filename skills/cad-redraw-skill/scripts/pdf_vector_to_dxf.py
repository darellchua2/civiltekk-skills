#!/usr/bin/env python3
"""Extract vector paths and real text from one PDF page into a generic-layer DXF."""

import argparse
import json
import sys
import tempfile
from collections import Counter
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

BEZIER_TOLERANCE = 0.1  # flattening distance in PDF points
LAYERS = {"LINEWORK": 7, "TEXT": 7, "BORDER": 8, "DIM": 3}
SUPPORTED_PATH_OPS = frozenset({"l", "re", "qu", "c"})
RASTER_DPI = 150


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


def _add_path_items(
    msp,
    drawing: dict,
    page_height: float,
    unsupported_ops: Counter | None = None,
    page_rect=None,
) -> int:
    """Flatten one PDF drawing (strokes and fills) into LINE entities on LINEWORK."""
    count = 0
    for item in drawing["items"]:
        op = item[0]
        if (
            op in SUPPORTED_PATH_OPS
            and page_rect is not None
            and _is_page_frame_item(item, page_rect)
        ):
            continue
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
        elif unsupported_ops is not None:
            unsupported_ops[op] += 1
    return count


def _page_frame_bounds(x0, y0, x1, y1, page_rect) -> bool:
    """Recognize a centered, near-page-size rectangle as a likely page frame."""
    # ponytail: fixed margin heuristic; add an explicit override if real frame-like parts
    # are misclassified in production drawings.
    width, height = page_rect.width, page_rect.height
    if width <= 0 or height <= 0:
        return False
    return (
        x1 - x0 >= width * 0.8
        and y1 - y0 >= height * 0.8
        and abs((x0 + x1) / 2 - (page_rect.x0 + page_rect.x1) / 2) <= width * 0.1
        and abs((y0 + y1) / 2 - (page_rect.y0 + page_rect.y1) / 2) <= height * 0.1
    )


def _is_page_frame_item(item, page_rect) -> bool:
    """Return whether a supported path item looks like a page-border segment."""
    op = item[0]
    if op == "re":
        rect = item[1]
        return _page_frame_bounds(rect.x0, rect.y0, rect.x1, rect.y1, page_rect)
    if op == "qu":
        quad = item[1]
        points = (quad.ul, quad.ur, quad.lr, quad.ll)
        return _page_frame_bounds(
            min(point.x for point in points),
            min(point.y for point in points),
            max(point.x for point in points),
            max(point.y for point in points),
            page_rect,
        )
    if op == "l":
        start, end = item[1], item[2]
        horizontal = (
            abs(start.y - end.y) <= page_rect.height * 0.01
            and min(
                abs(start.y - page_rect.y0), abs(start.y - page_rect.y1)
            )
            <= page_rect.height * 0.15
            and abs(start.x - end.x) >= page_rect.width * 0.8
        )
        vertical = (
            abs(start.x - end.x) <= page_rect.width * 0.01
            and min(
                abs(start.x - page_rect.x0), abs(start.x - page_rect.x1)
            )
            <= page_rect.width * 0.15
            and abs(start.y - end.y) >= page_rect.height * 0.8
        )
        return horizontal or vertical
    return False


def classify_page(page) -> dict:
    """Classify page evidence before conversion; frames alone are not usable CAD."""
    drawings = page.get_drawings()
    words = page.get_text("words")
    image_count = len(page.get_image_info(xrefs=True))
    frame_items = 0
    usable_items = 0
    usable_paths = 0
    unsupported_ops: Counter[str] = Counter()
    for drawing in drawings:
        path_usable = False
        for item in drawing.get("items", ()):
            op = item[0]
            if op not in SUPPORTED_PATH_OPS:
                unsupported_ops[op] += 1
            elif _is_page_frame_item(item, page.rect):
                frame_items += 1
            else:
                usable_items += 1
                path_usable = True
        usable_paths += path_usable

    if usable_items and image_count:
        route = "mixed-vector-raster"
    elif usable_items:
        route = "usable-vector"
    elif image_count:
        route = "raster-only"
    elif frame_items:
        route = "page-frame-only"
    elif unsupported_ops:
        route = "unsupported-vector-only"
    elif words:
        route = "text-only"
    else:
        route = "empty"
    return {
        "route": route,
        "usable_vector": usable_items > 0,
        "usable_vector_paths": usable_paths,
        "usable_vector_items": usable_items,
        "page_frame_items": frame_items,
        "text_words": sum(bool(str(word[4]).strip()) for word in words),
        "raster_images": image_count,
        "unsupported_path_ops": dict(sorted(unsupported_ops.items())),
    }


def render_page_raster(page, output: Path) -> dict:
    """Render one page as separate image evidence at a fixed, reported DPI."""
    scale = RASTER_DPI / 72
    pixmap = page.get_pixmap(
        matrix=pymupdf.Matrix(scale, scale),
        alpha=False,
    )
    pixmap.save(str(output))
    return {"path": str(output), "dpi": RASTER_DPI}


def _open_pdf_page(pdf_path: Path, page_number: int):
    """Open one checked page; exit with a named error for invalid PDF input."""
    try:
        doc = pymupdf.open(str(pdf_path))
    except Exception as exc:
        print(f"cannot open PDF '{pdf_path}': {exc}", file=sys.stderr)
        sys.exit(1)
    if page_number < 1 or page_number > doc.page_count:
        page_count = doc.page_count
        doc.close()
        print(
            f"page {page_number} does not exist: '{pdf_path}' has"
            f" {page_count} page(s)",
            file=sys.stderr,
        )
        sys.exit(1)
    return doc, doc[page_number - 1]


def classify_pdf_page(pdf_path: Path, page_number: int) -> dict:
    """Open, classify, and close one PDF page without producing a DXF."""
    doc, page = _open_pdf_page(pdf_path, page_number)
    try:
        return classify_page(page)
    finally:
        doc.close()


def extract_page(pdf_path: Path, page_number: int, output: Path) -> dict:
    """Extract usable vector content; return counts and unsupported path operations."""
    doc, page = _open_pdf_page(pdf_path, page_number)
    try:
        classification = classify_page(page)
        if not classification["usable_vector"]:
            print(
                f"page {page_number} of '{pdf_path}' is {classification['route']}; "
                "no usable PDF vector geometry, so no DXF was written",
                file=sys.stderr,
            )
            sys.exit(1)
        return _write_page_dxf(pdf_path, page_number, page, output)
    finally:
        doc.close()


def _write_page_dxf(pdf_path: Path, page_number: int, page, output: Path) -> dict:
    """Write one already-classified page as PDF-derived DXF geometry."""
    drawings = page.get_drawings()
    words = page.get_text("words")
    page_height = page.rect.height
    dxf = ezdxf.new("R2010", setup=True)
    dxf.units = 0  # unitless: coordinates are PDF points, scale is unverified
    dxf.header["$PROJECTNAME"] = f"PDF-derived from {pdf_path.name}, page {page_number}"
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
    unsupported_ops: Counter[str] = Counter()
    for drawing in drawings:
        lines += _add_path_items(
            msp, drawing, page_height, unsupported_ops, page.rect
        )

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
    return {
        "lines": lines,
        "texts": texts,
        "curve_count": sum(
            item[0] == "c"
            for drawing in drawings
            for item in drawing.get("items", ())
        ),
        "unsupported_path_ops": dict(sorted(unsupported_ops.items())),
    }


def _conversion_report(
    pdf_path: Path,
    page_number: int,
    classification: dict,
    extraction: dict | None = None,
    raster_output: dict | None = None,
) -> dict:
    """Build a provenance and conversion-loss report for one PDF page."""
    report = {
        "source": {"path": str(pdf_path), "format": "PDF", "page": page_number},
        "classification": classification["route"],
        "evidence": classification,
        "raster_output": raster_output,
    }
    if extraction is None:
        report["conversion"] = None
    else:
        report["conversion"] = {
            "format": "DXF",
            "provenance": "PDF-derived",
            "units": "unitless",
            "coordinates": "PDF points",
            "entities": extraction,
            "losses": {
                "raster_images_not_embedded": classification["raster_images"],
                "page_frame_items_omitted": classification["page_frame_items"],
                "unsupported_path_ops_omitted": extraction["unsupported_path_ops"],
                "curves_flattened_to_lines": extraction["curve_count"],
                "text_fonts_and_layout_preserved": False,
                "source_cad_layers_and_units_recovered": False,
            },
        }
    return report


def _write_report(path: Path | None, report: dict) -> None:
    """Write an optional JSON classification/conversion report."""
    if path is not None:
        path.write_text(
            json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
        )


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
            "Classify one PDF page before optional vector extraction. Page borders,"
            " text-only pages, and raster-only pages are not treated as usable CAD."
            " DXF coordinates stay in PDF points and units stay unitless."
        ),
        epilog="Mode B intermediate: PDF-derived, never claimed as original-CAD-exact.",
    )
    parser.add_argument("--pdf", help="input PDF file")
    parser.add_argument("--output", help="output DXF path (usable vector pages only)")
    parser.add_argument("--report", help="optional JSON classification/loss report")
    parser.add_argument(
        "--raster-output",
        help="optional PNG page image for visual evidence, separate from the DXF",
    )
    parser.add_argument(
        "--classify-only",
        action="store_true",
        help="classify and report the page without creating a DXF",
    )
    parser.add_argument(
        "--page", type=int, default=1, help="1-based page number to extract (default 1)"
    )
    parser.add_argument(
        "--self-check", action="store_true", help="run built-in checks and exit"
    )
    args = parser.parse_args(argv)

    if args.self_check:
        return self_check()
    if not args.pdf:
        parser.error("--pdf is required unless --self-check is used")
    if args.raster_output and Path(args.raster_output).suffix.lower() != ".png":
        parser.error("--raster-output must use the .png extension")
    if args.classify_only and args.output:
        parser.error("--output cannot be used with --classify-only")
    if not args.classify_only and not args.output:
        parser.error("--output is required unless --classify-only is used")

    pdf_path = Path(args.pdf)
    output_paths = [
        Path(path) for path in (args.output, args.report, args.raster_output) if path
    ]
    try:
        ensure_safe_outputs([pdf_path], output_paths)
    except ValueError as exc:
        print(f"unsafe PDF conversion output: {exc}", file=sys.stderr)
        return 1

    doc, page = _open_pdf_page(pdf_path, args.page)
    try:
        try:
            classification = classify_page(page)
            raster = (
                render_page_raster(page, Path(args.raster_output))
                if args.raster_output
                else None
            )
        except (OSError, RuntimeError, ValueError) as exc:
            print(
                f"cannot inspect PDF page {args.page} in '{pdf_path}': {exc}",
                file=sys.stderr,
            )
            return 1

        if args.classify_only:
            try:
                _write_report(
                    Path(args.report) if args.report else None,
                    _conversion_report(
                        pdf_path, args.page, classification, raster_output=raster
                    ),
                )
            except OSError as exc:
                print(f"cannot write report '{args.report}': {exc}", file=sys.stderr)
                return 1
            print(
                f"PDF page {args.page}: {classification['route']} "
                f"(usable vector={classification['usable_vector']}, "
                f"raster images={classification['raster_images']}, "
                f"text words={classification['text_words']})"
            )
            return 0

        if not classification["usable_vector"]:
            try:
                _write_report(
                    Path(args.report) if args.report else None,
                    _conversion_report(
                        pdf_path, args.page, classification, raster_output=raster
                    ),
                )
            except OSError as exc:
                print(f"cannot write report '{args.report}': {exc}", file=sys.stderr)
                return 1
            print(
                f"PDF page {args.page} is {classification['route']}; "
                "no usable vector geometry, so no DXF was written",
                file=sys.stderr,
            )
            return 1

        extraction = _write_page_dxf(
            pdf_path, args.page, page, Path(args.output)
        )
        try:
            _write_report(
                Path(args.report) if args.report else None,
                _conversion_report(
                    pdf_path, args.page, classification, extraction, raster_output=raster
                ),
            )
        except OSError as exc:
            print(f"cannot write report '{args.report}': {exc}", file=sys.stderr)
            return 1
        print(
            f"pdf_vector_to_dxf: {args.output} — "
            f"{extraction['lines']} LINE (incl. border), {extraction['texts']} TEXT; "
            f"PDF-derived, route={classification['route']}, units unitless"
        )
        if extraction["unsupported_path_ops"]:
            print(
                f"conversion loss: omitted path ops "
                f"{extraction['unsupported_path_ops']}",
                file=sys.stderr,
            )
        if classification["raster_images"]:
            print(
                f"conversion loss: {classification['raster_images']} embedded raster "
                "image(s) are not included in the DXF",
                file=sys.stderr,
            )
        return 0
    finally:
        doc.close()


if __name__ == "__main__":
    sys.exit(main())
