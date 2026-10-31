"""BT-142 Phase 3.4.1b — Vision-assisted schema extraction.

Companion to ``designer_promoter.py``. The XML-based extractor (cluster_shapes,
extract_theme_from_shapes) is precise on geometry but loses design intent —
most notably the **slide background color**, which in designer decks is
usually conveyed by a large fill rectangle rather than the layout's
``<p:cSld><p:bg>`` element. When promoted, those layouts render with a white
background (PowerPoint default) and the visual identity breaks.

This module closes that gap by rendering each source slide to a PNG via
``soffice`` and dispatching the image to ``image-analyzer-subagent`` (the
 orchestrator does the actual Task-tool dispatch — this module only prepares
 the prompts and aggregates the responses). The vision model returns a
 structured per-slide schema containing:

  - ``dominant_bg_hex`` — the slide's effective background color (most
    important; used to inject ``<p:cSld><p:bg>`` on the promoted layout)
  - ``text_blocks`` — list of ``{role, color_hex, bbox_pct}`` for headline/
    body/accent text (used to validate or override XML-derived text colors)
  - ``regions`` — list of ``{role, fill_hex, bbox_pct}`` for cards/panels
    (used to confirm container_check geometry)
  - ``layout_archetype`` — semantic type (cover, two_column, grid, team,
    closing) — used as a hint for orchestrator routing

The orchestrator calls ``render_slides_to_pngs`` → dispatches each PNG with
``build_image_analyzer_prompt`` → collects responses → passes them to
``promote_designer_slides(..., vision_results=...)``.

Public API:
  - ``render_slides_to_pngs(pptx_path, output_dir=None, dpi=150) -> List[Path]``
  - ``build_image_analyzer_prompt(slide_index, slide_count, png_path) -> str``
  - ``aggregate_vision_results(raw_responses) -> List[VisionSlideSchema]``
  - ``fallback_xml_background(slide) -> Optional[str]``
  - ``VisionSlideSchema`` dataclass
"""

from __future__ import annotations

import json
import logging
import re
import shutil
import subprocess
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Dict, List, Optional

logger = logging.getLogger(__name__)


@dataclass
class TextBlock:
    role: str = ""           # headline | body | accent | caption
    color_hex: str = ""      # "#RRGGBB"
    bbox_pct: List[float] = field(default_factory=list)  # [x, y, w, h] in 0..1


@dataclass
class Region:
    role: str = ""           # card | panel | accent_band | divider
    fill_hex: str = ""
    bbox_pct: List[float] = field(default_factory=list)


@dataclass
class VisionSlideSchema:
    """Per-slide vision-derived schema (one per source slide)."""

    slide_index: int
    layout_archetype: str = "unknown"  # cover | title_content | two_column | grid | team | closing | unknown
    dominant_bg_hex: str = ""          # most important — used to inject layout bg
    text_blocks: List[TextBlock] = field(default_factory=list)
    regions: List[Region] = field(default_factory=list)
    confidence: float = 0.0
    raw_response: str = ""

    def to_dict(self) -> dict:
        return {
            "slide_index": self.slide_index,
            "layout_archetype": self.layout_archetype,
            "dominant_bg_hex": self.dominant_bg_hex,
            "text_blocks": [t.__dict__ for t in self.text_blocks],
            "regions": [r.__dict__ for r in self.regions],
            "confidence": self.confidence,
        }


# --------------------------------------------------------------------------
# Slide rendering (soffice → PDF → PNG)
# --------------------------------------------------------------------------

def _find_soffice() -> Optional[str]:
    """Locate the LibreOffice CLI on PATH or common install locations."""
    candidates = [
        "soffice",
        "/usr/bin/soffice",
        "/usr/lib/libreoffice/program/soffice",
        "/Applications/LibreOffice.app/Contents/MacOS/soffice",
        "/opt/homebrew/bin/soffice",
    ]
    for c in candidates:
        if shutil.which(c) or Path(c).exists():
            return c
    return None


def render_slides_to_pngs(
    pptx_path: str,
    output_dir: Optional[str] = None,
    dpi: int = 150,
    timeout_seconds: int = 120,
) -> List[Path]:
    """Render every slide in ``pptx_path`` to a PNG.

    Uses ``soffice --headless --convert-to pdf`` then ``pdftoppm``. Returns
    a list of PNG paths ordered by slide index. Raises ``RuntimeError`` if
    soffice or pdftoppm is unavailable — caller should fall back to XML-only.
    """
    soffice = _find_soffice()
    if soffice is None:
        raise RuntimeError(
            "soffice (LibreOffice) not found — cannot render slides to PNG. "
            "Install LibreOffice or fall back to XML-only extraction."
        )

    src = Path(pptx_path).resolve()
    if not src.exists():
        raise FileNotFoundError(f"PPTX not found: {src}")

    out_dir = Path(output_dir) if output_dir else Path.cwd() / ".vision_renders" / src.stem
    out_dir.mkdir(parents=True, exist_ok=True)

    # 1. Convert to PDF
    try:
        subprocess.run(
            [soffice, "--headless", "--convert-to", "pdf", "--outdir", str(out_dir), str(src)],
            check=True,
            capture_output=True,
            timeout=timeout_seconds,
        )
    except subprocess.CalledProcessError as exc:
        raise RuntimeError(f"soffice PDF conversion failed: {exc.stderr.decode('utf-8', 'ignore')}")
    except subprocess.TimeoutExpired:
        raise RuntimeError(f"soffice PDF conversion timed out after {timeout_seconds}s")

    pdf_path = out_dir / (src.stem + ".pdf")
    if not pdf_path.exists():
        raise RuntimeError(f"soffice produced no PDF at expected path: {pdf_path}")

    # 2. PDF → PNGs (one per page) via pdftoppm if available, else soffice again
    pdftoppm = shutil.which("pdftoppm")
    png_paths: List[Path] = []
    if pdftoppm:
        prefix = out_dir / "slide"
        try:
            subprocess.run(
                [pdftoppm, "-r", str(dpi), "-png", str(pdf_path), str(prefix)],
                check=True,
                capture_output=True,
                timeout=timeout_seconds,
            )
        except subprocess.CalledProcessError as exc:
            raise RuntimeError(f"pdftoppm failed: {exc.stderr.decode('utf-8', 'ignore')}")
        # pdftoppm emits slide-1.png, slide-2.png, ... (zero-padded depending on count)
        png_paths = sorted(out_dir.glob("slide-*.png"))
    else:
        # Fall back: use soffice's img conversion per page (less reliable)
        try:
            subprocess.run(
                [soffice, "--headless", "--convert-to", "png", "--outdir", str(out_dir), str(pdf_path)],
                check=True,
                capture_output=True,
                timeout=timeout_seconds,
            )
        except subprocess.CalledProcessError:
            raise RuntimeError("neither pdftoppm nor soffice img conversion worked")
        png_paths = sorted(out_dir.glob("*.png"))

    if not png_paths:
        raise RuntimeError(f"rendering produced no PNGs in {out_dir}")

    return png_paths


# --------------------------------------------------------------------------
# image-analyzer-subagent prompt
# --------------------------------------------------------------------------

_IMAGE_ANALYZER_PROMPT_TEMPLATE = """You are analyzing a PowerPoint slide render to extract design intent that XML parsing cannot reliably capture.

Slide image: [attached PNG at {png_path}]
Slide index: {slide_index} (of {slide_count} total)
Source PPTX: {pptx_name}

Return STRICT JSON only (no prose). Schema:

{{
  "layout_archetype": "cover" | "title_content" | "two_column" | "grid" | "team" | "closing" | "unknown",
  "dominant_bg_hex": "#RRGGBB",
  "text_blocks": [
    {{"role": "headline" | "body" | "accent" | "caption", "color_hex": "#RRGGBB", "bbox_pct": [x, y, w, h]}}
  ],
  "regions": [
    {{"role": "card" | "panel" | "accent_band" | "divider", "fill_hex": "#RRGGBB", "bbox_pct": [x, y, w, h]}}
  ],
  "confidence": 0.0-1.0
}}

Rules:
- ``dominant_bg_hex`` is THE most important field — what background color fills most of the slide? (e.g. "#09090B" for a dark deck)
- ``bbox_pct`` coordinates are fractions of slide dimensions (0..1), format [x, y, width, height] with origin top-left.
- Only list ``text_blocks`` and ``regions`` you can see clearly; empty arrays are fine.
- Do NOT guess colors — use the eye-dropper-equivalent dominant pixel value.
- Confidence < 0.5 means you are unsure; the orchestrator will fall back to XML extraction.
"""


def build_image_analyzer_prompt(
    slide_index: int,
    slide_count: int,
    png_path: str,
    pptx_name: str = "",
) -> str:
    """Return the structured prompt for ``image-analyzer-subagent``."""
    return _IMAGE_ANALYZER_PROMPT_TEMPLATE.format(
        png_path=png_path,
        slide_index=slide_index,
        slide_count=slide_count,
        pptx_name=pptx_name,
    )


# --------------------------------------------------------------------------
# Response aggregation
# --------------------------------------------------------------------------

_HEX_RE = re.compile(r"^#?[0-9A-Fa-f]{6}$")


def _coerce_hex(raw: Any) -> str:
    """Normalize various inputs to '#RRGGBB' (or '' if unparseable)."""
    if not raw:
        return ""
    s = str(raw).strip()
    if not s.startswith("#"):
        s = "#" + s
    if not _HEX_RE.match(s):
        return ""
    return s.upper()


def _coerce_bbox(raw: Any) -> List[float]:
    if not isinstance(raw, list):
        return []
    out = []
    for v in raw[:4]:
        try:
            f = float(v)
            if 0 <= f <= 1:
                out.append(f)
        except (TypeError, ValueError):
            continue
    return out


def aggregate_vision_results(raw_responses: List[Any]) -> List[VisionSlideSchema]:
    """Convert raw image-analyzer responses into typed ``VisionSlideSchema``.

    ``raw_responses`` is a list (one per slide, ordered by slide index). Each
    entry may be:
      - a dict already in the right shape
      - a JSON string
      - an ``image-analyzer-subagent`` return contract dict containing
        ``{"analysis": "..."}`` or ``{"json": "..."}``

    Falls back gracefully: missing/invalid entries produce a schema with
    ``dominant_bg_hex=""`` and ``confidence=0``.
    """
    out: List[VisionSlideSchema] = []
    for i, raw in enumerate(raw_responses):
        schema = VisionSlideSchema(slide_index=i)
        if raw is None:
            out.append(schema)
            continue
        # Coerce to dict
        if isinstance(raw, str):
            try:
                raw = json.loads(raw)
            except json.JSONDecodeError:
                # Try to find a JSON block in the text
                m = re.search(r"\{.*\}", raw, re.DOTALL)
                if m:
                    try:
                        raw = json.loads(m.group(0))
                    except json.JSONDecodeError:
                        raw = {}
                else:
                    raw = {}
        if not isinstance(raw, dict):
            raw = {}
        schema.layout_archetype = str(raw.get("layout_archetype", "unknown"))
        schema.dominant_bg_hex = _coerce_hex(raw.get("dominant_bg_hex"))
        for tb in raw.get("text_blocks", []) or []:
            if not isinstance(tb, dict):
                continue
            schema.text_blocks.append(TextBlock(
                role=str(tb.get("role", "")),
                color_hex=_coerce_hex(tb.get("color_hex")),
                bbox_pct=_coerce_bbox(tb.get("bbox_pct")),
            ))
        for r in raw.get("regions", []) or []:
            if not isinstance(r, dict):
                continue
            schema.regions.append(Region(
                role=str(r.get("role", "")),
                fill_hex=_coerce_hex(r.get("fill_hex")),
                bbox_pct=_coerce_bbox(r.get("bbox_pct")),
            ))
        try:
            schema.confidence = float(raw.get("confidence", 0.0))
        except (TypeError, ValueError):
            schema.confidence = 0.0
        schema.raw_response = json.dumps(raw)[:1000]
        out.append(schema)
    return out


# --------------------------------------------------------------------------
# XML fallback (when vision unavailable)
# --------------------------------------------------------------------------

def fallback_xml_background(slide, theme: Optional[Dict[str, str]] = None) -> Optional[str]:
    """Pick the dominant background color from the largest covering shape.

    Used when vision extraction is unavailable. Heuristic: find the shape
    with the largest area whose bounding box covers the slide center; return
    its solid fill color. Returns None if no candidate is found.

    Handles both direct RGB fills (``<a:srgbClr>``) and theme-referenced
    fills (``<a:schemeClr val="dk1">``) by resolving the latter through
    the optional ``theme`` dict (same shape as ``designer_promoter.extract_theme_from_shapes``).
    """
    try:
        slide_w = int(slide.part.package.presentation_part.presentation.slide_width)
        slide_h = int(slide.part.package.presentation_part.presentation.slide_height)
    except Exception:
        slide_w = slide_h = 0
    if slide_w == 0 or slide_h == 0:
        return None
    slide_area = slide_w * slide_h

    def _resolve_fill(shp) -> Optional[str]:
        """Return '#RRGGBB' for the shape's solid fill, handling scheme colors."""
        # Read raw XML — more reliable than python-pptx's ColorFormat for
        # scheme-color references (which throw on .rgb access).
        from pptx.oxml.ns import qn
        ns_a = "http://schemas.openxmlformats.org/drawingml/2006/main"
        spPr = shp._element.find(qn("p:spPr"))
        if spPr is None:
            # Pictures, etc. — skip
            return None
        solid_fill = spPr.find(f"{{{ns_a}}}solidFill")
        if solid_fill is None:
            return None
        # Direct RGB
        srgb = solid_fill.find(f"{{{ns_a}}}srgbClr")
        if srgb is not None:
            val = srgb.get("val")
            if val and len(val) == 6:
                return f"#{val.upper()}"
        # Theme-color reference: <a:schemeClr val="dk1|lt1|dk2|lt2|accent1..6"/>
        # Also handle ECMA-376 aliases: tx1↔dk1, tx2↔dk2, bg1↔lt1, bg2↔lt2,
        # phClr (placeholder color), and the "text"/"background" synonyms.
        scheme = solid_fill.find(f"{{{ns_a}}}schemeClr")
        if scheme is not None and theme:
            role = scheme.get("val")
            # Map aliases to canonical OPC roles
            role_aliases = {
                "tx1": "dk1", "tx2": "dk2",
                "bg1": "lt1", "bg2": "lt2",
                "TEXT1": "dk1", "TEXT2": "dk2",
                "BACKGROUND1": "lt1", "BACKGROUND2": "lt2",
            }
            canonical = role_aliases.get(role, role_aliases.get(role.upper() if role else "", role))
            if canonical and canonical in theme:
                v = theme[canonical]
                return v.upper() if v.startswith("#") else f"#{v}"
        return None

    best = None
    best_area = 0
    for shp in slide.shapes:
        try:
            rect_area = int(shp.width) * int(shp.height)
        except (TypeError, AttributeError):
            continue
        if rect_area < slide_area * 0.5:  # must cover ≥50% of the slide
            continue
        if rect_area <= best_area:
            continue
        hex_color = _resolve_fill(shp)
        if hex_color:
            best = hex_color
            best_area = rect_area
    return best


__all__ = [
    "TextBlock",
    "Region",
    "VisionSlideSchema",
    "render_slides_to_pngs",
    "build_image_analyzer_prompt",
    "aggregate_vision_results",
    "fallback_xml_background",
]
