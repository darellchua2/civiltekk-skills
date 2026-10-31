---
name: cad-specialist-skill
description: >-
  CAD, robotics, and hardware router — one entry point for parametric CAD,
  STEP/STL/3MF/GLB parts, DXF drawings, drawing redraw, URDF/SRDF/SDF robot
  descriptions (Gazebo, MoveIt), G-code slicing, 3D printing, SendCutSend
  preflight, Civil 3D, Autodesk APS, Open3D point clouds, and part catalogs.
  Routes each task to the right specialist route.
license: Apache-2.0
compatibility: opencode
metadata:
  protocol: opencode-skill
category: CAD & Hardware Design
---

# CAD Specialist Router

One entry point for CAD, robotics, and hardware tasks. Identify the task, run
only the matched route's file, and follow it. Heavy tooling lives in
installable sibling skills — never absorbed here.

Provenance: routes consolidated from the former cad-* skill family (2026-10,
#679); per-route provenance lines live in the route files.

## Routes (load exactly one)

| Task | Route | Read | Skip-when |
|------|-------|------|-----------|
| URDF robot description (.urdf) | `urdf` | `references/routes/urdf.md` | MoveIt semantics → srdf |
| MoveIt planning semantics (.srdf) | `srdf` | `references/routes/srdf.md` | URDF structure → urdf |
| Gazebo SDFormat model/world (.sdf) | `sdf` | `references/routes/sdf.md` | signed-distance-field geometry → sibling cad-generation |
| Slice meshes to G-code / validate .gcode | `gcode` | `references/routes/gcode.md` | Bambu upload/start → bambu |
| Bambu Lab LAN print handoff | `bambu` | `references/routes/bambu.md` | slicing itself → gcode |
| SendCutSend upload preflight (DXF/STEP) | `sendcutsend` | `references/routes/sendcutsend.md` | geometry generation → sibling cad-generation |
| step.parts catalog search/download | `step-parts` | `references/routes/step-parts.md` | custom geometry → sibling cad-generation |
| Civil 3D corridors, pipes, grading, survey | `civil3d` | `references/routes/civil3d.md` | APS cloud APIs → aps |
| Autodesk APS/Forge REST + Revit/Fusion/AutoCAD add-ins | `aps` | `references/routes/aps.md` | desktop Civil 3D design → civil3d |
| Open3D point clouds, meshes, reconstruction | `open3d` | `references/routes/open3d.md` | CAD authoring → sibling cad-generation |

Route files open with their own **Load when / Skip when** lines. Route detail
dirs (`references/routes/<id>/`) load on demand when the route file names them
— never preload.

## Sibling skills (install-if-missing)

Heavy tooling stays out of this skill. When a task matches a sibling row and
the skill is not installed (check the user's skill list), offer:

```
npx github:darellchua2/civiltekk-opencode-claude-skills add <skill>
```

| Task | Sibling skill |
|------|---------------|
| Parametric CAD parts, STEP/STL/3MF/GLB output | `cad-generation-skill` |
| 2D DXF drawings from Python ezdxf sources | `cad-dxf-skill` |
| Drawing redraw (DWG/DXF/PDF/image source) | `cad-redraw-skill` |
| Implicit CAD (.implicit.js / .mjs) | `cad-implicit-skill` |
| Browser preview / review links for artifacts | `cad-viewer-skill` |

Contract: dry-run first, show the resolved install set, install only with user
consent (civiltekk-install-assistant conventions). Never auto-install. On
decline or install failure, report the capability as unavailable — do not
improvise the tooling.

## Shared spine (all routes)

- `gen_urdf()` / `gen_srdf()` / `gen_sdf()` Python sources are the source of
  truth; generated XML is an artifact. Edit the generator, regenerate explicit
  targets only.
- `python` in examples is an interpreter placeholder — substitute `python3`, a
  project virtualenv, or the configured interpreter.
- Derive spatial data (frames, poses, axes, units, masses) from source data or
  explicit documented assumptions — never from visual impression.
- Validate every generated artifact at generation time; run consumer smoke
  tests when available.
- Viewer handoff: after creating or modifying a viewable artifact, hand the
  file path(s) to `cad-viewer-skill` (install-if-missing). Report when
  unavailable — never silently omit.
- Report assumptions, skipped checks, and unresolved risks; route files define
  their own report shapes (the sdf route carries the canonical example).

## Hard rules

- No invented printer profiles (gcode route); no scraping — hosted APIs only
  (step-parts, sendcutsend fetch official sources directly).
- Printer starts require explicit `--execute --confirm-start-print`; the bambu
  route owns the full safety rules — read it before any live printer action.
- Scripts run from this skill's directory: `scripts/<tool>` as each route file
  documents; one merged `requirements.txt` at the skill root.
- Each route file owns its deep detail; this router never restates it.

## Gates

- Zero-preload: only the matched route file (+ its on-demand detail dir)
  enters context.
- Report shape complete before declaring done: outputs, checks run/skipped,
  assumptions, risks.
- Any sibling-dependent capability goes through the install-if-missing
  contract above.
