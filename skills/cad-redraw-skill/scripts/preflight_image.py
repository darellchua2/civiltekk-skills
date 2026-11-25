#!/usr/bin/env python3
"""Preflight a raster source image into a profile-classified JSON quality report."""

import argparse
import hashlib
import json
import math
import sys
import tempfile
from pathlib import Path

from path_safety import ensure_safe_outputs

try:
    import numpy as np
except ImportError:  # pragma: no cover - environment guard
    print("numpy is required: pip install numpy", file=sys.stderr)
    sys.exit(2)
try:
    import cv2
except ImportError:  # pragma: no cover - environment guard
    print("opencv-python is required: pip install opencv-python", file=sys.stderr)
    sys.exit(2)
try:
    from PIL import Image
except ImportError:  # pragma: no cover - environment guard
    print("pillow is required: pip install pillow", file=sys.stderr)
    sys.exit(2)

PROFILES = frozenset({"strict-dimensioned", "general", "hybrid", "visual-trace"})
STRICT_PROFILE = "strict-dimensioned"
BLUR_MIN = 100.0
CONTRAST_MIN = 25.0
MIN_DIMENSION = 400
SKEW_WARN_DEG = 5.0
MAX_DPI = 10000.0


def sha256_file(path: Path) -> str:
    """Return the hex SHA-256 digest of a file, read in chunks."""
    digest = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 16), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_image(path: Path) -> dict:
    """Decode an image into RGB pixels plus DPI metadata; exit 1 when unreadable."""
    try:
        with Image.open(path) as img:
            img.load()
            info = dict(img.info)
            rgb = np.asarray(img.convert("RGB"), dtype=np.uint8)
    except FileNotFoundError:
        print(f"image file not found: {path}", file=sys.stderr)
        sys.exit(1)
    except Exception as exc:  # PIL raises many error types on corrupt input
        print(f"cannot read image '{path}': {exc}", file=sys.stderr)
        sys.exit(1)
    return {"rgb": rgb, "dpi": info.get("dpi")}


def to_gray(rgb: np.ndarray) -> tuple[np.ndarray, str]:
    """Return grayscale pixels and a 'gray'/'rgb' classification."""
    r, g, b = rgb[:, :, 0], rgb[:, :, 1], rgb[:, :, 2]
    color = "gray" if np.array_equal(r, g) and np.array_equal(g, b) else "rgb"
    return cv2.cvtColor(rgb, cv2.COLOR_RGB2GRAY), color


def blur_variance(gray: np.ndarray) -> float:
    """Return the variance of the Laplacian (higher means sharper)."""
    return float(cv2.Laplacian(gray, cv2.CV_64F).var())


def rms_contrast(gray: np.ndarray) -> float:
    """Return RMS contrast: standard deviation of the grayscale values."""
    return float(gray.std())


def estimate_skew_deg(gray: np.ndarray) -> float | None:
    """Return median deviation from the image axes in degrees, or None."""
    edges = cv2.Canny(gray, 50, 150)
    min_length = max(40, int(min(gray.shape) * 0.2))
    lines = cv2.HoughLinesP(
        edges, 1, np.pi / 360, 80, minLineLength=min_length, maxLineGap=4
    )
    if lines is None:
        return None
    deviations = []
    for x1, y1, x2, y2 in lines.reshape(-1, 4):
        if x2 == x1:  # perfectly vertical line
            deviations.append(0.0)
            continue
        angle = math.degrees(math.atan2(float(y2 - y1), float(x2 - x1)))
        deviations.append(angle - 90.0 * round(angle / 90.0))
    if not deviations:
        return None
    return float(np.median(deviations))


def detect_scale_anchor(dpi) -> dict | None:
    """Return a metadata-only DPI scale anchor, or None when absent/implausible."""
    if not isinstance(dpi, (tuple, list)) or len(dpi) != 2:
        return None
    try:
        x_dpi, y_dpi = float(dpi[0]), float(dpi[1])
    except (TypeError, ValueError):
        return None
    plausible = (
        1.0 < x_dpi <= MAX_DPI
        and 1.0 < y_dpi <= MAX_DPI
        and math.isclose(x_dpi, y_dpi, rel_tol=0.05)
    )
    if not plausible:
        return None
    return {
        "type": "dpi_metadata",
        "x_dpi": round(x_dpi, 2),
        "y_dpi": round(y_dpi, 2),
        "note": "metadata only — verify against a readable dimension before use",
    }


def analyze_image(path: Path) -> dict:
    """Analyze one image and return the profile-independent report core."""
    raw = read_image(path)
    gray, color = to_gray(raw["rgb"])
    skew = estimate_skew_deg(gray)
    return {
        "image": {
            "name": path.name,
            "sha256": sha256_file(path),
            "width": int(gray.shape[1]),
            "height": int(gray.shape[0]),
            "color": color,
        },
        "quality": {
            "blur_variance": round(blur_variance(gray), 2),
            "contrast_rms": round(rms_contrast(gray), 2),
            "skew_deg": None if skew is None else round(skew, 2),
        },
        "scale_anchor": detect_scale_anchor(raw["dpi"]),
    }


def classify(core: dict, mode: str) -> dict:
    """Split quality findings into warnings and blockers for the profile."""
    strict = mode == STRICT_PROFILE
    quality, image, anchor = core["quality"], core["image"], core["scale_anchor"]
    findings: list[tuple[str, str, bool]] = []
    if quality["blur_variance"] < BLUR_MIN:
        findings.append(
            (
                "low_blur",
                f"blur variance {quality['blur_variance']:.1f} is below"
                f" {BLUR_MIN:.0f}; fine detail may be unreadable",
                True,
            )
        )
    if quality["contrast_rms"] < CONTRAST_MIN:
        findings.append(
            (
                "low_contrast",
                f"RMS contrast {quality['contrast_rms']:.1f} is below"
                f" {CONTRAST_MIN:.0f}",
                True,
            )
        )
    if min(image["width"], image["height"]) < MIN_DIMENSION:
        findings.append(
            (
                "low_resolution",
                f"{image['width']}x{image['height']} px is below {MIN_DIMENSION} px"
                " on the short side",
                False,
            )
        )
    skew = quality["skew_deg"]
    if skew is not None and abs(skew) > SKEW_WARN_DEG:
        findings.append(
            (
                "apparent_skew",
                f"median line deviation {skew:.1f} deg suggests skew or perspective",
                False,
            )
        )
    if anchor is not None:
        findings.append(
            (
                "unverified_scale_metadata",
                "scale anchor is DPI metadata only; verify it before trusting it",
                False,
            )
        )
    warnings, blockers = [], []
    for code, message, blocks_in_strict in findings:
        if strict and blocks_in_strict:
            blockers.append({"code": code, "message": message})
        else:
            warnings.append({"code": code, "message": message})
    if strict and anchor is None:
        blockers.append(
            {
                "code": "no_scale_anchor",
                "message": (
                    "strict-dimensioned requires a scale anchor; none detected —"
                    " supply calibration or switch to visual-trace"
                ),
            }
        )
    return {"warnings": warnings, "blockers": blockers}


def build_report(core: dict, mode: str) -> dict:
    """Attach profile classification and honest notes to an analysis core."""
    classified = classify(core, mode)
    if core["scale_anchor"] is None:
        note = (
            "scale_anchor: none detected — no unit/DPI metadata in the image;"
            " pixels alone cannot establish real-world scale"
        )
    else:
        note = "scale_anchor: DPI metadata found — unverified, do not trust blindly"
    return {
        "image": core["image"],
        "quality": core["quality"],
        "scale_anchor": core["scale_anchor"],
        "warnings": classified["warnings"],
        "blockers": classified["blockers"],
        "notes": [note],
    }


def _require(condition: bool, what: str) -> None:
    """Raise an AssertionError naming the failed self-check expectation."""
    if not condition:
        raise AssertionError(f"self-check failed: {what}")


def _sharp_image() -> np.ndarray:
    """Build a sharp synthetic RGB image: gradient background plus white rect."""
    width, height = 320, 240
    ramp = np.linspace(30.0, 220.0, width, dtype=np.float32)
    base = np.repeat(ramp[None, :], height, axis=0)
    rgb = np.stack([base] * 3, axis=-1).astype(np.uint8)
    rgb[60:180, 80:240] = 255
    return rgb


def _blurred_image(rgb: np.ndarray) -> np.ndarray:
    """Gaussian-blur an RGB image until its fine detail is gone."""
    return cv2.GaussianBlur(rgb, (31, 31), 0)


def self_check() -> int:
    """Run sharp vs blurred synthetic images through the full analysis path."""
    try:
        with tempfile.TemporaryDirectory(prefix="preflight-selfcheck-") as tmp:
            tmp_path = Path(tmp)
            sharp_png = tmp_path / "sharp.png"
            blurred_png = tmp_path / "blurred.png"
            cv2.imwrite(str(sharp_png), cv2.cvtColor(_sharp_image(), cv2.COLOR_RGB2BGR))
            blurred = _blurred_image(_sharp_image())
            cv2.imwrite(str(blurred_png), cv2.cvtColor(blurred, cv2.COLOR_RGB2BGR))
            sharp = build_report(analyze_image(sharp_png), "general")
            blurred_general = build_report(analyze_image(blurred_png), "general")
            blurred_strict = build_report(analyze_image(blurred_png), STRICT_PROFILE)
            _require(
                sharp["image"]["width"] == 320 and sharp["image"]["height"] == 240,
                "dimensions detected",
            )
            _require(len(sharp["image"]["sha256"]) == 64, "sha256 computed")
            _require(sharp["scale_anchor"] is None, "synthetic image is anchor-less")
            sharp_codes = [w["code"] for w in sharp["warnings"]]
            blurred_codes = [w["code"] for w in blurred_general["warnings"]]
            _require("low_blur" in blurred_codes, "blurred image flagged low_blur")
            _require("low_blur" not in sharp_codes, "sharp image not flagged low_blur")
            _require(
                len(sharp_codes) < len(blurred_codes),
                "sharp has fewer quality warnings than blurred",
            )
            _require(
                any(b["code"] == "no_scale_anchor" for b in blurred_strict["blockers"]),
                "strict-dimensioned blocks the anchor-less image",
            )
            _require(
                any(b["code"] == "low_blur" for b in blurred_strict["blockers"]),
                "strict-dimensioned blocks the blurry image",
            )
            _require(
                not blurred_general["blockers"],
                "general mode never blocks on quality alone",
            )
    except AssertionError as exc:
        print(str(exc), file=sys.stderr)
        return 1
    except Exception as exc:
        print(f"preflight self-check raised: {exc}", file=sys.stderr)
        return 1
    print("preflight_image self-check: PASS")
    return 0


def main(argv: list[str] | None = None) -> int:
    """CLI entry. Exit 0 analyzed (blockers live in the report), 1 unreadable, 2 env."""
    parser = argparse.ArgumentParser(
        description=(
            "Preflight a raster source for Mode C: hash, resolution, blur, contrast,"
            " skew estimate, and scale-anchor detection. A warning becomes a blocker"
            " only when the profile requires evidence the image cannot provide;"
            " visual-trace never blocks on scale. Geometry-only is a separate DXF"
            " output option, not an image evidence profile."
        )
    )
    parser.add_argument("--image", help="input raster image (PNG, JPEG, …)")
    parser.add_argument(
        "--mode",
        choices=sorted(PROFILES),
        help="evidence profile the image must support",
    )
    parser.add_argument("--output", help="output report JSON path")
    parser.add_argument(
        "--self-check", action="store_true", help="run built-in checks and exit"
    )
    args = parser.parse_args(argv)

    if args.self_check:
        return self_check()
    if not (args.image and args.mode and args.output):
        parser.error("--image, --mode, and --output are required unless --self-check")

    try:
        ensure_safe_outputs([Path(args.image)], [Path(args.output)])
    except ValueError as exc:
        print(f"unsafe preflight output: {exc}", file=sys.stderr)
        return 1

    report = build_report(analyze_image(Path(args.image)), args.mode)
    try:
        Path(args.output).write_text(
            json.dumps(report, indent=2) + "\n", encoding="utf-8"
        )
    except OSError as exc:
        print(f"cannot write report '{args.output}': {exc}", file=sys.stderr)
        return 1
    for finding in report["blockers"]:
        print(f"blocker [{finding['code']}] {finding['message']}", file=sys.stderr)
    for finding in report["warnings"]:
        print(f"warning [{finding['code']}] {finding['message']}", file=sys.stderr)
    print(
        f"preflight: {args.output} — {len(report['warnings'])} warnings,"
        f" {len(report['blockers'])} blockers; disposition is the caller's decision"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
