---
name: cad-redraw-skill
description: >-
  Rebuild and validate 2D CAD drawings across operating systems — source
  DXF/DWG redraw, classified PDF-to-DXF conversion, and evidence-aware image
  reconstruction. Triggers: dwg redraw, redraw dxf, image to dxf, pdf to dxf,
  drawing fingerprint, raster to cad, redraw validation.
license: Apache-2.0
compatibility: opencode
category: CAD & Hardware Design
metadata:
  protocol: opencode-skill
  pattern: clean-room-port
---

# OS-aware CAD redraw and validation

Provenance: the workflow methodology follows
[pengxiaoan/autocad-dwg-redraw-skill](https://github.com/pengxiaoan/autocad-dwg-redraw-skill)
(evidence levels, fingerprint-first redraw, visual-vs-dimensional separation).
That repository ships no license, so no code was copied — this skill is a
clean-room reimplementation on ezdxf for Linux. The installed files are the
runtime source of truth.

## Purpose

Reconstruct an editable, validated 2D CAD drawing from source CAD, PDF, or
image evidence. DXF is the primary deliverable. AutoCAD and Windows automation
are never prerequisites.

- **Mode A — source redraw**: a trustworthy DXF (or DWG) exists. Fingerprint
  it, rebuild it, and prove the rebuild with a fingerprint diff.
- **Mode B — PDF-to-DXF**: a PDF exists but no CAD source. Extract vector
  paths into an auditable intermediate DXF, labeled PDF-derived — never
  claimed as original-CAD-exact.
- **Mode C — image-to-CAD**: only a raster reference (photo, scan,
  screenshot). Build an evidence-aware spec, draw from it, and compare
  visually without ever asserting dimensional accuracy from pixels.

Validation is a separate decision: choose checks that are installed and match
the claim being made. A rendered preview is visual evidence, not structural or
dimensional validation.

## Use this skill when

The user asks for a dwg redraw, to redraw dxf content, convert image to dxf,
pdf to dxf, raster to CAD, or to fingerprint and validate a drawing rebuild.
For 3D solids hand off to `the cad-generation-skill (load via skill tool)`;
this skill is 2D only. `the cad-dxf-skill (load via skill tool)` generates
new parametric drawings; this skill reconstructs existing ones.

## Non-negotiable rules

1. Resolve geometry in this order: explicit user requirements, readable
   dimensions, derived constraints, calibrated measurements, labeled visual
   estimates. Image pixels never override a written dimension.
2. Track every important value as `known`, `scaled`, `inferred`, or
   `unreadable`.
3. Visual similarity never proves dimensional accuracy. Comparison output is
   labeled "visual only".
4. Conflicting dimensions are never silently resolved: record the conflict
   and return `needs_review` or `blocked`.
5. Never overwrite the source file. Always write to a new output path.
6. PDF-derived and image-derived outputs are labeled as such. An intermediate
   is never presented as an exact original CAD source.

## Environment and capability preflight

Before recommending a tool, inspect the current OS, architecture, and installed
capabilities:

```text
python scripts/headless_validate.py --probe
```

The probe distinguishes CADCraft `info` readback from `convert` rendering,
ezdxf structural audits, and Matplotlib-based previews. It checks AutoCAD Core
Console only on native Windows and never launches it. Under WSL, a
Windows-mounted CADCraft executable is reported as skipped; do not cross-launch
Windows tools or install anything automatically.

If a required tool is absent, report the affected check as `skipped` or
`blocked`. Recommend only a CADCraft binary matching the detected OS and
architecture from its official releases; verify the publisher's checksum or
signature before use. Offer a source build pinned to an official release only
when no matching binary exists, and follow its official build instructions.
Get explicit consent before installing any binary, dependency, or application.

## Evidence profiles and output

Choose by input quality; the profile sets the evidence bar:

- `strict-dimensioned`: engineering deliverable. Requires readable units and
  enough known/calibrated anchors to constrain the geometry; otherwise block.
- `general`: balanced default for plans, sketches, screenshots.
- `hybrid`: dimensions where available, calibrated proportions elsewhere,
  inferred geometry labeled.
- `visual-trace`: reproduce visible linework without asserting real-world
  scale.

`--geometry-only` is a separate output switch, not a profile. It keeps drawing
geometry and drops annotations without lowering the selected evidence bar.

No unit or scale anchor → choose `visual-trace` or a `unitless` spec. Never
default to millimeters because a drawing looks technical.

## Mode A — source redraw

1. **Fingerprint** the source:
   `python scripts/fingerprint.py --source input.dxf --output reports/input`
   (DWG input is converted first — see *DWG input/output*). Review the
   generated `<prefix>-redraw-prompt.md`: entity counts, layer table, block
   inventory, styles, annotation inventory, risk notes.
2. **Rebuild**: copy entities into a fresh document (ezdxf importer) or
   round-trip through the DXF converter; write to a new output path.
3. **Validate**:
   `python scripts/fingerprint_diff.py --source reports/input-fingerprint.json --target reports/output-fingerprint.json`
   Exit 0 required. Missing dimensions or leaders in the target when the
   source has them is a validation failure, not a warning.
4. **Preview and hand off** (see *Handoff*).

## Mode B — PDF-to-DXF

1. Classify the selected page before extraction:
   `python scripts/pdf_vector_to_dxf.py --pdf input.pdf --classify-only --report reports/page.json`
   The routes are `usable-vector`, `mixed-vector-raster`, `raster-only`,
   `text-only`, `page-frame-only`, `unsupported-vector-only`, and `empty`.
   Searchable text, a page border, or an embedded scan is not usable vector
   CAD by itself.
2. For `usable-vector` or `mixed-vector-raster`, extract supported paths:
   `python scripts/pdf_vector_to_dxf.py --pdf input.pdf --output intermediate.dxf --report reports/conversion.json`
   Add `--raster-output reports/page.png` when a separate visual reference is
   useful. This raster output is not embedded in the DXF.
3. For raster evidence, request a PNG without a DXF:
   `python scripts/pdf_vector_to_dxf.py --pdf input.pdf --classify-only --raster-output reports/page.png --report reports/page.json`
   Continue through Mode C; the converter does not OCR or trace raster content.
4. PDF-derived DXF coordinates remain PDF points and unitless. The report
   lists omitted page-frame/path items, raster content not embedded, flattened
   curves, and text/layer/unit information that could not be recovered. The
   converter adds a synthetic page-extents border on `BORDER`; do not treat it
   as source geometry. Page-frame detection is heuristic, so review the route
   before treating a large outer shape as part geometry. Label the intermediate
   PDF-derived, then validate it using the Mode A checks.

## Mode C — image-to-CAD

1. **Preflight**:
   `python scripts/preflight_image.py --image input.jpg --mode general --output reports/preflight.json`
   A quality warning becomes a blocker only when the profile requires
   evidence the image cannot provide.
2. **Spec**: author `redraw-spec.json` per
   `references/redraw-spec.md` — stable entity IDs, views with independent
   calibration, evidence levels, constraints.
3. **Validate the spec**:
   `python scripts/spec_to_dxf.py --spec redraw-spec.json --check-only --report reports/spec-validation.json`
   Resolve all errors before drawing.
4. **Draw**:
   `python scripts/spec_to_dxf.py --spec redraw-spec.json --output outputs/redraw.dxf`
   Use `--geometry-only` as a separate output switch when annotations are not
   wanted; keep the chosen evidence profile unchanged.
5. **Inspect and render**:
   `python scripts/render_preview.py --dxf outputs/redraw.dxf --png reports/preview.png`
   Optionally run CADCraft readback and a headless PNG preview when the
   capability probe confirms it:
   `python scripts/headless_validate.py --input outputs/redraw.dxf --preview reports/cadcraft-preview.png --report reports/cadcraft-validation.json`.
   A partial CADCraft read (`skipped` records or any `readNotes`) fails and
   does not render a preview.
6. **Compare**:
   `python scripts/compare_visual.py --source input.jpg --cad-preview reports/preview.png --anchors anchors.json --output-dir reports/comparison`
   Use the comparison to find omitted/shifted geometry — never to validate
   physical dimensions.
7. **Iterate**, then issue exactly one disposition per
   `references/validation.md`: `pass`, `pass_with_warnings`, `needs_review`,
   `blocked`, or `fail`.

## Validation contract

Deterministic checks over eyeballing: entity counts by type and space, layer
membership, closed flags on cut profiles, extents, and every dimension the
user supplied — via `fingerprint_diff.py` and ezdxf queries. The fingerprint
diff is reported even when it passes. Acceptance policies and dispositions:
`references/validation.md`.

`cadcraft-cli info` is a structural readback; `cadcraft-cli convert` to PNG is
render-only. Run the capability probe before selecting either. Neither a clean
readback nor a preview proves dimensional accuracy without the applicable
fingerprint/spec/dimension checks.

## Handoff

CAD Viewer is optional for headless redraws. Do not install or launch it unless
the user requests interactive browser review. When requested and available,
hand it the explicit file path(s) and include its live link(s); otherwise state
that the viewer handoff was skipped. Final responses include generated files,
viewer status, validation actually run or skipped, evidence-level summary,
assumptions, and the disposition.

## DWG input/output

DWG works as both input and output: input is read through the external
converter chain below; output is written by `scripts/to_dwg.py` when the ODA
File Converter is installed. `fingerprint.py` reads `.dwg` sources through
the external converter chain (ODA File Converter via `odafc`, then LibreDWG
`dwg2dxf`) with automatic fallback; see `references/linux-toolchain.md` for
install guidance, converter precedence, fidelity reporting, and the
degradation caveats (proxy objects, SHX text, annotative dimensions, dynamic
blocks). For DWG **output**, `scripts/to_dwg.py` converts a validated DXF to
DWG via the ODA File Converter (target version flag included) when ODA is
installed — DXF remains the default deliverable; produce and validate it
first, then run the writer when a DWG file is mandatory.

## Runtime requirements

Python 3.10+. Required: `ezdxf`. Optional (import-guarded with named install
hints): `odafc` + ODA File Converter or LibreDWG for DWG, `pillow`/`numpy`/
`opencv-python` for image preflight and comparison, `pymupdf` for PDF
extraction, `matplotlib` for preview rendering, and CADCraft CLI for optional
headless readback/rendering. Run scripts with the active project Python from
the workspace that owns the artifacts.
