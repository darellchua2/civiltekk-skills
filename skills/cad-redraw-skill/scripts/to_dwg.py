#!/usr/bin/env python3
"""Convert a DXF deliverable to DWG via the ODA File Converter (ezdxf.addons.odafc)."""

import argparse
import os
import shutil
import sys
import tempfile
from pathlib import Path

from path_safety import ensure_safe_outputs

# Checked before the ezdxf import so a missing converter never becomes a traceback.
ODA_HINT = (
    "ODA File Converter not found: install it from "
    "https://www.opendesign.com/guestfiles/oda_file_converter and put "
    "'ODAFileConverter' on PATH (see references/linux-toolchain.md)"
)
EZDXF_HINT = "ezdxf is required: pip install ezdxf"
# Output versions the ODA File Converter accepts (subset used by this skill).
VERSIONS = frozenset(
    {"ACAD2000", "ACAD2004", "ACAD2007", "ACAD2010", "ACAD2013", "ACAD2018"}
)


def _require(condition: bool, what: str) -> None:
    """Raise an AssertionError naming the failed self-check expectation."""
    if not condition:
        raise AssertionError(f"self-check failed: {what}")


def _fail(code: int, message: str) -> int:
    """Print a named error to stderr and return the contract exit code."""
    print(f"to_dwg: {message}", file=sys.stderr)
    return code


def _converter_available() -> bool:
    """Report whether the ODA File Converter binary is detectable on PATH."""
    return shutil.which("ODAFileConverter") is not None


def _check_paths(source: Path, output: Path) -> int | None:
    """Return a contract exit code for bad-input path conditions, else None."""
    if not source.is_file():
        return _fail(1, f"input DXF not found: {source}")
    if not os.access(source, os.R_OK):
        return _fail(1, f"input DXF is not readable: {source}")
    try:
        ensure_safe_outputs([source], [output])
    except ValueError as exc:
        return _fail(1, str(exc))
    if output.exists():
        return _fail(1, f"output path already exists: {output}")
    return None


def _convert(source: Path, output: Path, version: str) -> int:
    """Convert DXF to DWG via odafc.convert; exit 2 env, exit 1 bad content."""
    try:
        import ezdxf.addons.odafc as odafc
    except ImportError:
        return _fail(2, EZDXF_HINT)
    try:
        output.parent.mkdir(parents=True, exist_ok=True)
    except OSError as exc:
        return _fail(2, f"cannot create output directory: {exc}")
    try:
        odafc.convert(str(source), str(output), version=version)
    except odafc.ODAFCNotInstalledError:
        return _fail(2, ODA_HINT)
    except odafc.ODAFCError:
        # With ODA present, a converter rejection is a content-validity signal.
        return _fail(1, "invalid or unsupported DXF content (rejected by converter)")
    except Exception as exc:  # unexpected failure is an environment error
        return _fail(2, f"ODA conversion failed: {exc}")
    # ezdxf's convert() swallows the produced-nothing case upstream — check it.
    if not output.is_file() or output.stat().st_size == 0:
        return _fail(2, "ODA conversion produced no DWG output")
    print(
        f"to_dwg: wrote {output} ({output.stat().st_size} bytes) "
        f"via ODA File Converter, target version {version}"
    )
    return 0


def self_check() -> int:
    """Prove the guard paths always; prove a real round-trip only when ODA exists."""
    tmp = Path(tempfile.mkdtemp(prefix="to-dwg-selfcheck-"))
    try:
        missing = tmp / "missing.dxf"
        source = tmp / "src.dxf"
        out = tmp / "out.dwg"
        _require(_check_paths(missing, out) == 1, "missing input exits 1")
        source.write_text("0\nSECTION\n2\nHEADER\n0\nENDSEC\n0\nEOF\n")
        _require(_check_paths(source, source) == 1, "output == source exits 1")
        existing = tmp / "exists.dwg"
        existing.write_text("stale")
        _require(_check_paths(source, existing) == 1, "existing output exits 1")
        _require(_check_paths(source, out) is None, "clean input passes the guards")
        if _converter_available():
            try:
                import ezdxf
            except ImportError:
                print(f"to_dwg: {EZDXF_HINT}", file=sys.stderr)
                return 1
            doc = ezdxf.new()
            doc.saveas(source)
            code = _convert(source, out, "ACAD2018")
            _require(code == 0, "conversion exits 0 with ODA present")
            _require(out.is_file() and out.stat().st_size > 0, "DWG written, non-empty")
            print("to_dwg self-check: PASS")
        else:
            print(
                "SKIPPED: ODA File Converter not detected — guard paths verified only"
            )
        return 0
    except AssertionError as exc:
        print(f"to_dwg: {exc}", file=sys.stderr)
        return 1
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def main(argv: list[str] | None = None) -> int:
    """CLI entry: convert --input DXF to --output DWG, or run --self-check."""
    parser = argparse.ArgumentParser(
        description="Convert a DXF deliverable to DWG via the ODA File Converter. "
        "Exit 0 converted, 1 bad input, 2 environment (ODA/ezdxf missing or failed)."
    )
    parser.add_argument("--input", help="source DXF file")
    parser.add_argument("--output", help="output DWG path (must not already exist)")
    parser.add_argument(
        "--version",
        default="ACAD2018",
        help=f"target DWG version ({', '.join(sorted(VERSIONS))}; default ACAD2018)",
    )
    parser.add_argument(
        "--self-check", action="store_true", help="run built-in checks and exit"
    )
    args = parser.parse_args(argv)

    if args.self_check:
        return self_check()
    if not args.input or not args.output:
        return _fail(1, "--input and --output are both required")
    if args.version not in VERSIONS:
        return _fail(
            1,
            f"unknown --version '{args.version}'; known: {', '.join(sorted(VERSIONS))}",
        )
    source = Path(args.input)
    output = Path(args.output)
    bad_input = _check_paths(source, output)
    if bad_input is not None:
        return bad_input
    if not _converter_available():
        return _fail(2, ODA_HINT)
    os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
    return _convert(source, output, args.version)


if __name__ == "__main__":
    sys.exit(main())
