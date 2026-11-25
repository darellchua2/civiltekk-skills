#!/usr/bin/env python3
"""Render a DXF modelspace to a deterministic PNG (and optional PDF) preview."""

import argparse
import sys
import tempfile
from pathlib import Path

from path_safety import ensure_safe_outputs

try:
    import ezdxf
except ImportError:  # pragma: no cover - environment guard
    print("ezdxf is required: pip install ezdxf", file=sys.stderr)
    sys.exit(2)

PAGE_INCHES = (11.0, 8.5)
DPI = 200
BACKGROUND = "#FFFFFF"


def _load_backend():
    """Import the matplotlib drawing backend (Agg) or exit 2 with an install hint."""
    try:
        import matplotlib

        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
        from ezdxf.addons.drawing import Frontend
        from ezdxf.addons.drawing.matplotlib import MatplotlibBackend
        from ezdxf.addons.drawing.properties import LayoutProperties, RenderContext
    except ImportError:  # pragma: no cover - environment guard
        print(
            "matplotlib is required for preview rendering: pip install matplotlib",
            file=sys.stderr,
        )
        sys.exit(2)
    return plt, Frontend, MatplotlibBackend, LayoutProperties, RenderContext


def load_drawing(path: Path):
    """Read the DXF file, exiting with a named error on unreadable input."""
    try:
        return ezdxf.readfile(str(path))
    except FileNotFoundError:
        print(f"DXF file not found: {path}", file=sys.stderr)
        sys.exit(1)
    except IOError as exc:
        print(f"cannot read DXF '{path}': {exc}", file=sys.stderr)
        sys.exit(1)
    except ezdxf.DXFError as exc:
        print(f"invalid DXF '{path}': {exc}", file=sys.stderr)
        sys.exit(1)


def render(doc, png: Path, pdf: Path | None = None) -> None:
    """Render the modelspace: white background, zoom extents, fixed page size."""
    plt, frontend_cls, backend_cls, layout_props_cls, render_ctx_cls = _load_backend()
    figure = plt.figure(dpi=DPI)
    axes = figure.add_axes((0, 0, 1, 1))
    axes.set_facecolor("white")
    layout = doc.modelspace()
    properties = layout_props_cls.from_layout(layout)
    properties.set_colors(BACKGROUND)
    backend = backend_cls(axes)
    frontend_cls(render_ctx_cls(doc), backend).draw_layout(
        layout, finalize=True, layout_properties=properties
    )
    figure.set_size_inches(*PAGE_INCHES)
    figure.patch.set_facecolor("white")
    figure.savefig(png, dpi=DPI, facecolor="white")
    if pdf is not None:
        figure.savefig(pdf, facecolor="white")
    plt.close(figure)


def _require(condition: bool, what: str) -> None:
    """Raise an AssertionError naming the failed self-check expectation."""
    if not condition:
        raise AssertionError(f"self-check failed: {what}")


def build_fixture():
    """Build a tiny in-memory drawing to exercise the render path."""
    doc = ezdxf.new("R2010", setup=True)
    doc.units = 4
    msp = doc.modelspace()
    msp.add_line((0, 0), (100, 0))
    msp.add_line((0, 0), (0, 50))
    msp.add_circle((40, 25), radius=10)
    msp.add_lwpolyline([(0, 0), (100, 0), (100, 50)], close=True)
    return doc


def self_check() -> int:
    """Render the in-memory fixture to a tempdir and assert a non-empty PNG."""
    try:
        with tempfile.TemporaryDirectory(prefix="render-selfcheck-") as tmp:
            png = Path(tmp) / "preview.png"
            pdf = Path(tmp) / "preview.pdf"
            render(build_fixture(), png, pdf)
            _require(png.is_file(), "PNG file written")
            _require(png.stat().st_size > 0, "PNG file is non-empty")
            _require(pdf.is_file() and pdf.stat().st_size > 0, "PDF file written")
    except AssertionError as exc:
        print(str(exc), file=sys.stderr)
        return 1
    except Exception as exc:
        print(f"render self-check raised: {exc}", file=sys.stderr)
        return 1
    print("render_preview self-check: PASS")
    return 0


def main(argv: list[str] | None = None) -> int:
    """CLI entry: render a DXF to PNG/PDF. Exit 0 ok, 1 render failure, 2 environment."""
    parser = argparse.ArgumentParser(
        description="Render a DXF modelspace to a deterministic PNG (white background,"
        " zoom extents, fixed page) and optionally a PDF."
    )
    parser.add_argument("--dxf", help="input DXF file to render")
    parser.add_argument("--png", help="output PNG path")
    parser.add_argument("--pdf", help="optional output PDF path")
    parser.add_argument(
        "--self-check", action="store_true", help="run built-in checks and exit"
    )
    args = parser.parse_args(argv)

    if args.self_check:
        return self_check()
    if not args.dxf or not args.png:
        parser.error("--dxf and --png are required unless --self-check is used")

    outputs = [Path(path) for path in (args.png, args.pdf) if path]
    try:
        ensure_safe_outputs([Path(args.dxf)], outputs)
    except ValueError as exc:
        print(f"unsafe preview output: {exc}", file=sys.stderr)
        return 1

    doc = load_drawing(Path(args.dxf))
    try:
        render(doc, Path(args.png), Path(args.pdf) if args.pdf else None)
    except Exception as exc:
        print(f"render failed: {exc}", file=sys.stderr)
        return 1
    print(f"preview: {args.png}" + (f" and {args.pdf}" if args.pdf else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
