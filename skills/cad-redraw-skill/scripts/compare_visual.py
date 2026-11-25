#!/usr/bin/env python3
"""Register a CAD preview onto a source image and emit visual-only comparison artifacts."""

import argparse
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

MODELS = frozenset({"affine", "homography"})
MIN_PAIRS = {"affine": 2, "homography": 4}
EDGE_TOLERANCE_PX = 3.0
VISUAL_ONLY = "visual only — never evidence of physical dimensional accuracy"


def _is_point(value) -> bool:
    """Return True when value is a finite [x, y] numeric pair."""
    if not isinstance(value, (list, tuple)) or len(value) != 2:
        return False
    return all(
        isinstance(v, (int, float)) and not isinstance(v, bool) and math.isfinite(v)
        for v in value
    )


def load_anchors(path: Path) -> dict:
    """Load and parse the anchors JSON; exit 1 with a named error."""
    try:
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)
    except FileNotFoundError:
        print(f"anchors file not found: {path}", file=sys.stderr)
        sys.exit(1)
    except json.JSONDecodeError as exc:
        print(f"invalid anchors JSON '{path}': {exc}", file=sys.stderr)
        sys.exit(1)
    except UnicodeDecodeError:
        print(
            f"anchors '{path}' is not valid UTF-8 text (wrong file?)", file=sys.stderr
        )
        sys.exit(1)
    except OSError as exc:
        print(f"cannot read anchors '{path}': {exc}", file=sys.stderr)
        sys.exit(1)


def load_gray(path: Path) -> np.ndarray:
    """Load an image as grayscale; exit 1 when unreadable."""
    gray = cv2.imread(str(path), cv2.IMREAD_GRAYSCALE)
    if gray is None:
        print(f"cannot read image '{path}'", file=sys.stderr)
        sys.exit(1)
    return gray


def correspondences(anchors: dict, model: str) -> tuple[np.ndarray, np.ndarray]:
    """Return (source_pts, cad_pts) float32 arrays; exit 1 when insufficient."""
    pairs = anchors.get("correspondences")
    if not isinstance(pairs, list) or not pairs:
        print(
            "insufficient correspondences: at least one pair is required",
            file=sys.stderr,
        )
        sys.exit(1)
    source, cad = [], []
    for index, pair in enumerate(pairs):
        if not isinstance(pair, dict):
            print(f"correspondence {index}: expected an object", file=sys.stderr)
            sys.exit(1)
        sp, cp = pair.get("source_px"), pair.get("cad_px")
        if not _is_point(sp) or not _is_point(cp):
            print(
                f"correspondence {index}: needs 'source_px' and 'cad_px' as [x, y]",
                file=sys.stderr,
            )
            sys.exit(1)
        source.append(sp)
        cad.append(cp)
    minimum = MIN_PAIRS[model]
    if len(source) < minimum:
        print(
            f"insufficient correspondences for {model}: {len(source)} provided,"
            f" minimum {minimum}",
            file=sys.stderr,
        )
        sys.exit(1)
    return np.array(source, dtype=np.float32), np.array(cad, dtype=np.float32)


def estimate_transform(model: str, cad_pts: np.ndarray, src_pts: np.ndarray):
    """Estimate a cad→source transform; return (matrix, inlier_mask) or (None, None)."""
    if model == "homography":
        matrix, mask = cv2.findHomography(cad_pts, src_pts, cv2.RANSAC, 3.0)
    else:
        matrix, mask = cv2.estimateAffinePartial2D(cad_pts, src_pts)
    if matrix is None:
        return None, None
    return matrix, mask


def residual_px(matrix, cad_pts, src_pts, mask) -> float | None:
    """Mean inlier reprojection error in pixels, or None without inliers."""
    if mask is None:
        return None
    inliers = mask.ravel().astype(bool)
    if not inliers.any():
        return None
    cad_in, src_in = cad_pts[inliers], src_pts[inliers]
    if matrix.shape == (2, 3):
        projected = cad_in @ matrix[:, :2].T + matrix[:, 2]
    else:
        projected = cv2.perspectiveTransform(cad_in.reshape(-1, 1, 2), matrix).reshape(
            -1, 2
        )
    return float(np.mean(np.linalg.norm(projected - src_in, axis=1)))


def warp_preview(cad_gray: np.ndarray, matrix, size: tuple[int, int]) -> np.ndarray:
    """Warp the CAD preview into source pixel space at size (width, height)."""
    border = dict(borderMode=cv2.BORDER_CONSTANT, borderValue=255)
    if matrix.shape == (2, 3):
        return cv2.warpAffine(cad_gray, matrix, size, **border)
    return cv2.warpPerspective(cad_gray, matrix, size, **border)


def write_artifacts(source: np.ndarray, warped: np.ndarray, out_dir: Path) -> None:
    """Write side_by_side.png, overlay.png, and difference.png (no captions)."""
    cv2.imwrite(str(out_dir / "side_by_side.png"), np.hstack((source, warped)))
    overlay = cv2.addWeighted(source, 0.5, warped, 0.5, 0)
    cv2.imwrite(str(out_dir / "overlay.png"), overlay)
    cv2.imwrite(str(out_dir / "difference.png"), cv2.absdiff(source, warped))


def edge_metrics(source: np.ndarray, warped: np.ndarray) -> tuple[float, float | None]:
    """Return (edge coverage within tolerance, mean edge distance) in pixels."""
    src_edges = cv2.Canny(source, 50, 150)
    cad_edges = cv2.Canny(warped, 50, 150)
    if np.count_nonzero(src_edges) == 0:
        return 0.0, None
    distance = cv2.distanceTransform((cad_edges == 0).astype(np.uint8), cv2.DIST_L2, 3)
    distances = distance[src_edges.astype(bool)]
    return float(np.mean(distances <= EDGE_TOLERANCE_PX)), float(np.mean(distances))


def compare(
    source: np.ndarray,
    cad: np.ndarray,
    anchors: dict,
    model: str,
    out_dir: Path,
) -> dict:
    """Register cad onto source, write artifacts + metrics.json, return metrics."""
    try:
        out_dir.mkdir(parents=True, exist_ok=True)
    except OSError as exc:
        print(f"cannot create output directory '{out_dir}': {exc}", file=sys.stderr)
        sys.exit(1)
    src_pts, cad_pts = correspondences(anchors, model)
    matrix, mask = estimate_transform(model, cad_pts, src_pts)
    if matrix is None:
        print(
            f"{model} estimation failed: correspondences are degenerate"
            " (collinear or identical points)",
            file=sys.stderr,
        )
        sys.exit(1)
    size = (source.shape[1], source.shape[0])
    warped = warp_preview(cad, matrix, size)
    write_artifacts(source, warped, out_dir)
    coverage, mean_distance = edge_metrics(source, warped)
    residual = residual_px(matrix, cad_pts, src_pts, mask)
    metrics = {
        "view": anchors.get("view"),
        "model": model,
        "comparison": VISUAL_ONLY,
        "total_correspondences": int(len(src_pts)),
        "inliers": 0 if mask is None else int(mask.sum()),
        "residual_px": None if residual is None else round(residual, 3),
        "edge_tolerance_px": EDGE_TOLERANCE_PX,
        "edge_coverage": round(coverage, 4),
        "mean_edge_distance_px": (
            None if mean_distance is None else round(mean_distance, 3)
        ),
    }
    metrics_path = out_dir / "metrics.json"
    try:
        metrics_path.write_text(
            json.dumps(metrics, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
        )
    except OSError as exc:
        print(f"cannot write metrics '{metrics_path}': {exc}", file=sys.stderr)
        sys.exit(1)
    return metrics


def _require(condition: bool, what: str) -> None:
    """Raise an AssertionError naming the failed self-check expectation."""
    if not condition:
        raise AssertionError(f"self-check failed: {what}")


def _synthetic_source() -> np.ndarray:
    """Build a white image with a black rectangle and circle, numpy only."""
    width, height = 400, 300
    img = np.full((height, width), 255, dtype=np.uint8)
    img[60:180, 80:280] = 0
    yy, xx = np.mgrid[0:height, 0:width]
    img[(xx - 330) ** 2 + (yy - 220) ** 2 <= 30**2] = 0
    return img


def _synthetic_cad(offset: tuple[int, int] = (40, 20)) -> np.ndarray:
    """Draw the same shapes with cv2 at a known pixel offset."""
    width, height = 400, 300
    ox, oy = offset
    img = np.full((height, width), 255, dtype=np.uint8)
    cv2.rectangle(img, (80 + ox, 60 + oy), (279 + ox, 179 + oy), 0, 1)
    cv2.circle(img, (330 + ox, 220 + oy), 30, 0, 1)
    return img


def _synthetic_anchors() -> dict:
    """Anchor the known rectangle corners of source and offset CAD images."""
    ox, oy = 40, 20
    corners = [(80, 60), (279, 179), (80, 179), (279, 60)]
    return {
        "view": "front",
        "model": "affine",
        "correspondences": [
            {"source_px": [x, y], "cad_px": [x + ox, y + oy]} for x, y in corners
        ],
    }


def self_check() -> int:
    """Compare two synthetic images with known geometry through the pipeline."""
    try:
        with tempfile.TemporaryDirectory(prefix="compare-selfcheck-") as tmp:
            tmp_path = Path(tmp)
            source_png = tmp_path / "source.png"
            cad_png = tmp_path / "cad.png"
            anchors_json = tmp_path / "anchors.json"
            out_dir = tmp_path / "comparison"
            cv2.imwrite(str(source_png), _synthetic_source())
            cv2.imwrite(str(cad_png), _synthetic_cad())
            anchors_json.write_text(json.dumps(_synthetic_anchors()), encoding="utf-8")
            metrics = compare(
                load_gray(source_png),
                load_gray(cad_png),
                load_anchors(anchors_json),
                "affine",
                out_dir,
            )
            for name in (
                "side_by_side.png",
                "overlay.png",
                "difference.png",
                "metrics.json",
            ):
                _require((out_dir / name).is_file(), f"{name} written")
            _require(metrics["edge_coverage"] > 0.5, "edge coverage above 0.5")
            metrics_text = (out_dir / "metrics.json").read_text(encoding="utf-8")
            metrics_read = json.loads(metrics_text)
            _require(
                metrics_read["comparison"] == VISUAL_ONLY,
                "'visual only' label in parsed metrics",
            )
            _require(
                "visual only" in metrics_text, "'visual only' visible in metrics file"
            )
            _require(metrics["inliers"] >= MIN_PAIRS["affine"], "affine inliers >= 2")
            _require(
                metrics["residual_px"] is not None and metrics["residual_px"] < 1.0,
                "residual below 1 px",
            )
    except AssertionError as exc:
        print(str(exc), file=sys.stderr)
        return 1
    except Exception as exc:
        print(f"compare self-check raised: {exc}", file=sys.stderr)
        return 1
    print("compare_visual self-check: PASS")
    return 0


def main(argv: list[str] | None = None) -> int:
    """CLI entry. Exit 0 comparison, 1 bad inputs/correspondences, 2 environment."""
    parser = argparse.ArgumentParser(
        description=(
            "Register a CAD preview onto a source image via anchor correspondences"
            " (affine or homography), then write side-by-side, overlay, and difference"
            " images plus edge-coverage metrics. Comparison output is labeled"
            f" '{VISUAL_ONLY}'."
        )
    )
    parser.add_argument("--source", help="source raster image")
    parser.add_argument("--cad-preview", help="rendered CAD preview image (PNG)")
    parser.add_argument("--anchors", help="anchors JSON with source_px/cad_px pairs")
    parser.add_argument("--output-dir", help="directory for comparison artifacts")
    parser.add_argument(
        "--model",
        choices=sorted(MODELS),
        help="transform model (default: anchors file value, else affine)",
    )
    parser.add_argument(
        "--self-check", action="store_true", help="run built-in checks and exit"
    )
    args = parser.parse_args(argv)

    if args.self_check:
        return self_check()
    if not (args.source and args.cad_preview and args.anchors and args.output_dir):
        parser.error(
            "--source, --cad-preview, --anchors, and --output-dir are required"
            " unless --self-check is used"
        )

    out_dir = Path(args.output_dir)
    inputs = [Path(args.source), Path(args.cad_preview), Path(args.anchors)]
    outputs = [
        out_dir / name
        for name in (
            "side_by_side.png",
            "overlay.png",
            "difference.png",
            "metrics.json",
        )
    ]
    try:
        ensure_safe_outputs(inputs, outputs)
    except ValueError as exc:
        print(f"unsafe comparison output: {exc}", file=sys.stderr)
        return 1

    anchors = load_anchors(Path(args.anchors))
    model = args.model or anchors.get("model") or "affine"
    if model not in MODELS:
        print(
            f"unknown model '{model}' (expected affine or homography)", file=sys.stderr
        )
        return 1
    source = load_gray(Path(args.source))
    cad = load_gray(Path(args.cad_preview))
    try:
        out_dir.mkdir(parents=True, exist_ok=True)
    except OSError as exc:
        print(f"cannot create output directory '{out_dir}': {exc}", file=sys.stderr)
        sys.exit(1)
    metrics = compare(source, cad, anchors, model, out_dir)
    print(
        f"comparison: {out_dir} (edge coverage {metrics['edge_coverage']:.2%})"
        f" — {VISUAL_ONLY}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
