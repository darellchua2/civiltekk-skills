# Route: SDF — SDFormat models & worlds (.sdf)

**Load when:** the deliverable is an SDFormat document or `gen_sdf()` source (Gazebo/libsdformat). NOT for signed-distance-field geometry.
**Skip when:** the task is URDF/SRDF robot description work (Routes: URDF, SRDF).
**Route dir:** `sdf/` beside this file — read on demand.

# SDF

Provenance: maintained in [earthtojake/text-to-cad](https://github.com/earthtojake/text-to-cad).
Use the installed local skill files as the runtime source of truth; the
repository link is only for provenance and release review.

Use this skill when the deliverable is an SDFormat document or a Python `gen_sdf()` source. SDFormat describes simulator and world behavior: models, worlds, frames, poses, links, joints, inertials, visuals, collisions, sensors, lights, physics, plugins, includes, and simulator metadata.

This skill is for **SDFormat**, not signed-distance-field geometry.

## Core rules

1. Treat the Python file defining `gen_sdf()` as source of truth. Treat configured `.sdf` files as generated artifacts unless the user explicitly asks for direct XML editing.
2. Identify the target consumer before editing: Gazebo/libsdformat version, another simulator, visualization-only tooling, model package, or world handoff.
3. Decide document kind: model-level SDF, world-level SDF, or model-in-world. Prefer model-level SDF for reusable robot/object exports.
4. Use SI units unless the target explicitly requires otherwise: meters, kilograms, seconds, radians.
5. Prefer `version="1.12"` for new outputs unless the target consumer constrains the version.
6. Establish the design ledger before writing poses, frames, joint axes, mesh scales, inertials, sensors, or plugins. Use `sdf/design-ledger.md` and `sdf/llm-guardrails.md`.
7. Do not infer spatial transforms from visual impression alone. Derive poses, axes, scale, mass, inertia, and frame names from upstream source data, drawings, simulator documentation, measured values, or explicit assumptions.
8. Prefer helper functions and named constants over large XML string literals. Hidden numbers are a common SDF failure mode.
9. Generate only explicit targets with `scripts/sdf` or the repository's existing SDF launcher. Do not run directory-wide generation.
10. Regenerate upstream geometry, mesh, robot-description, render, topology, or package assets with their owning workflows before regenerating SDF that references them.
11. After generation, run available checks: bundled validation, optional `gz sdf --check`, simulator load, joint motion, and plugin/sensor startup.
12. Report assumptions, skipped checks, unresolved resource paths, and target-specific compatibility risks.

## Scope

Use this skill for SDFormat outputs and generators. Do not use it for signed-distance-field modeling, raw geometry generation, planning semantics, or to paper over incorrect upstream robot/source data unless the task is explicitly simulator-only.

## CAD Viewer Handoff

Per the router viewer-handoff rule: hand the created/updated file path(s) to the
`cad-viewer-skill` sibling (install-if-missing). Report when it is unavailable —
never silently omit the handoff.

## Workflow

1. Locate the `gen_sdf()` source and intended `.sdf` output.
2. Read or create the design ledger.
3. Read `sdf/frame-semantics.md` before editing any `<pose>`, `<frame>`, joint axis, `relative_to`, `expressed_in`, nested scope, sensor frame, or plugin frame.
4. Edit the generator source, not generated XML.
5. Use optional builder helpers when they make the generated structure clearer; raw ElementTree is still allowed.
6. Regenerate the explicit target.
7. Treat bundled validation as a guardrail, not simulator proof.
8. Run target-consumer smoke tests when available.
9. Report checks run, checks skipped, and assumptions. Static rendering does not execute SDF plugins or read file-authored motion metadata.

## Commands

Run with the project or workspace Python environment (interpreter placeholder rule: router shared spine).

```bash
python scripts/sdf path/to/source.py
python scripts/sdf path/to/source.py -o path/to/output.sdf
python scripts/sdf path/to/a.py=out/a.sdf path/to/b.py=out/b.sdf
```

Plain Python targets write sibling `.sdf` files beside their sources. `-o` / `--output` is valid only with one plain target. `SOURCE.py=OUTPUT.sdf` supports custom multi-target destinations.

If the runtime supports optional external checking:

```bash
python scripts/sdf path/to/source.py --gz-check auto
python scripts/sdf path/to/source.py --gz-check required
python scripts/sdf path/to/source.py --gz-check never
```

`gz sdf --check` is optional target-consumer validation. It should be reported as skipped when unavailable unless explicitly required.

## Required report shape

When finishing an SDF task, include a compact report:

```text
Generated: path/to/model.sdf from path/to/model.py
Checks run:
- bundled SDF validation: passed
- gz sdf --check: skipped, gz not installed
- simulator load: skipped, target simulator unavailable
- viewer handoff: `cad-viewer-skill` sibling (install-if-missing) link returned
Assumptions:
- Assumed mesh units are meters.
- Assumed lidar frame is coincident with lidar_link.
Risks:
- Camera plugin filename was not verified in the target simulator environment.
```

## References

- Generation command: `sdf/gen-sdf.md`
- Generator contract: `sdf/generator-contract.md`
- SDF workflow: `sdf/sdf-workflow.md`
- Builder helpers: `sdf/builder-helpers.md`
- LLM guardrails: `sdf/llm-guardrails.md`
- Design ledger: `sdf/design-ledger.md`
- Frame semantics: `sdf/frame-semantics.md`
- Validation scope: `sdf/validation.md`
- Smoke tests: `sdf/smoke-tests.md`
- Interoperability notes: `sdf/interoperability.md`
- Examples: `sdf/examples.md`
- Runtime notes and current limitations: `sdf/implementation-notes.md`
