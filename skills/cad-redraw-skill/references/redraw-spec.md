# Redraw spec schema

The spec JSON is the interchange format between spec authoring, spec
validation (`spec_to_dxf.py --check-only`), and drawing. One file describes
the entire reconstruction. Unknown values are recorded as `"evidence":
"unreadable"`, never omitted silently.

## Top-level shape

```json
{
  "spec_version": 1,
  "source": {"image": "input.jpg", "sha256": "…", "preflight": "reports/preflight.json"},
  "profile": "general",
  "units": {"system": "mm", "declared": true},
  "views": [],
  "entities": [],
  "constraints": [],
  "layers": [],
  "assumptions": [],
  "disposition": null
}
```

- `profile`: one of `strict-dimensioned`, `general`, `hybrid`, or
  `visual-trace`. `geometry-only` is a separate `spec_to_dxf.py
  --geometry-only` output option, not an evidence profile.
- `units.system`: `mm`, `cm`, `m`, `in`, `ft`, or `unitless`. When the source
  has no unit or scale anchor, use `unitless` with `"declared": false` — do
  not silently default to mm.
- `assumptions`: every inference, stated. Non-empty `assumptions` caps the
  best possible disposition at `pass_with_warnings`.

## Views and calibration

Each view carries its own calibration — never share one across views with
different scales:

```json
{
  "id": "front",
  "calibration": {
    "type": "affine",
    "anchors_px": [[120, 400], [880, 400]],
    "anchors_cad": [[0, 0], [760, 0]],
    "evidence": "known"
  }
}
```

`type`: `affine`, `homography`, or `dimension`. Source coordinates are image
pixels (origin top-left); CAD coordinates are drawing units (origin chosen
for auditability). Calibration `evidence` records how the mapping was
derived. A strict dimensioned spec needs usable `known` or `scaled`
calibration on every view that contains dimensions. Affine/dimension mappings
need at least two distinct paired anchors; homography needs four paired
anchors with no three collinear.

## Entities

Stable IDs (`e1`, `e2`, …) are permanent across edits — validators key on
them, never on list order.

| Field | Required | Notes |
|---|---|---|
| `id` | yes | unique, stable |
| `type` | yes | `line`, `arc`, `circle`, `lwpolyline`, `text`, `mtext`, `dimension` |
| `view` | yes | view id the entity belongs to |
| `layer` | yes | must exist in `layers` |
| `geometry` | yes | type-specific, in CAD units |
| `evidence` | yes | `known`, `scaled`, `inferred`, `unreadable` |
| `text` | text/mtext/dimension only | content; `""` when unreadable |

Geometry shapes: `line` `{start: [x,y], end: [x,y]}`; `arc`
`{center: [x,y], radius: r, start_angle: a, end_angle: a}` (degrees,
counterclockwise); `circle` `{center: [x,y], radius: r}`; `lwpolyline`
`{points: [[x,y],…], closed: bool}`; `text`/`mtext` `{insert: [x,y], height:
h, rotation: deg}` plus `text`; `dimension` `{p1: [x,y], p2: [x,y],
offset: d, value: v|null}` — `value` is the authoritative measurement when
readable, else `null` with `evidence: "unreadable"`.

## Constraints

Declarative relationships the validator checks arithmetically:

```json
{"id": "c1", "kind": "sum", "of": ["d1", "d2"], "equals": "d_total"}
{"id": "c2", "kind": "positive", "ref": "d1"}
{"id": "c3", "kind": "inside", "ref": "e5", "within": "e1"}
{"id": "c4", "kind": "count", "of": "bolt_hole", "equals": 6}
```

Kinds: `sum`, `positive`, `inside` (containment), `count`, `spacing`
(equal repeated spacing), `parallel`, `aligned`. A constraint referencing a
value with `evidence: "unreadable"` is checked only when that evidence is
upgraded.

## Layers

Drawing structure, not part structure. Minimum set for reconstructions:
`LINEWORK`, `TEXT`, `BORDER`, `DIM`; optional `CENTER`, `CONSTRUCTION`,
`HATCH`. Each entry: `{"name": "LINEWORK", "color": 7, "linetype":
"CONTINUOUS"}`. `geometry-only` output keeps `LINEWORK`/`CONSTRUCTION` and
drops annotation layers.

## Evidence rules

- `known`: stated by the user or read directly from the source.
- `scaled`: measured from a calibrated view.
- `inferred`: derived (symmetry, pattern completion) — must have a matching
  `assumptions` entry.
- `unreadable`: present in the source but not recoverable; geometry may be
  traced with `visual-trace` semantics, flagged for review.

`strict-dimensioned` requires every load-bearing dimension to be `known` or
`scaled` with a declared unit system; anything less blocks drawing.
`inferred` values never satisfy `strict-dimensioned`. The authoritative
numeric `geometry.value` must match the measured distance between `p1` and
`p2` within `max(1e-6, 1e-6 × max(|value|, measured distance))` drawing units.
The `--geometry-only` output switch can be used with any evidence profile; it
drops annotation entities without changing the profile.
