# Route: URDF — robot descriptions (.urdf)

**Load when:** the task creates, edits, or validates URDF robot descriptions.
**Skip when:** the task is MoveIt semantics (Route: SRDF), Gazebo worlds/simulator models (Route: SDF), or mechanical CAD (sibling `cad-generation-skill`).
**Route dir:** `urdf/` beside this file carries this route's deep-dive files (listed in References) — read on demand.

# URDF

Provenance: maintained in [earthtojake/text-to-cad](https://github.com/earthtojake/text-to-cad).
Use the installed local skill files as the runtime source of truth; the
repository link is only for provenance and release review.

Use this skill for URDF robot-description outputs. Treat URDF work as constrained kinematic modeling, not just XML writing. The main correctness risks are frame placement, joint-axis semantics, unit consistency, mesh scale, inertial data, and generated-artifact drift.

## Core Rules

1. Treat the Python source that defines `gen_urdf()` as the source of truth. Treat configured `.urdf` files as generated artifacts.
2. Generate only explicit URDF targets. Do not regenerate unrelated CAD, mesh, render, SRDF, SDF, or simulator artifacts from this skill.
3. The `scripts/urdf` generator validates generated URDFs by default. Do not use or document a separate `validate` command.
4. Before writing or changing URDF XML, establish the robot's frame, joint, geometry, unit, and assumption ledger. See `urdf/design-ledger.md`.
5. Use URDF frame semantics exactly. Joint origins, link frames, joint axes, and visual/collision/inertial origins use different reference frames. See `urdf/frame-semantics.md`.
6. Do not infer spatial transforms, mesh units, handedness, axes, or joint signs from vague prose. Use CAD transforms, dimensioned drawings, measured values, existing source data, or explicit documented assumptions.
7. Prefer simple, auditable generator code over clever XML construction. Keep constants named by physical meaning, not by arbitrary numbers.
8. For physical links, model `inertial`, `visual`, and `collision` separately when the target consumer needs them. Frame-only links may intentionally omit mass and geometry.

## CAD Viewer Handoff

Per the router viewer-handoff rule: hand the created/updated file path(s) to the
`cad-viewer-skill` sibling (install-if-missing). Report when it is unavailable —
never silently omit the handoff.

## Workflow

1. Identify the `gen_urdf()` Python source and target `.urdf` output.
2. Identify target consumers: RViz, robot_state_publisher, Gazebo/Ignition, MoveIt, a real robot driver, or another simulator.
3. Read or create the design ledger before editing frames, origins, axes, mesh scale, limits, or inertials.
4. Edit the generator source, not generated URDF XML.
5. Regenerate only explicit targets with `scripts/urdf`.
6. Let generation-time validation fail fast on XML, graph, joint, geometry, mesh-reference, and inertial problems.
7. When geometry or mesh references depend on changed CAD or exported mesh outputs, regenerate those explicit artifacts with the owning CAD or mesh workflow, then regenerate the affected URDF target.
8. When available, run a consumer smoke test appropriate to the target: RViz display, robot_state_publisher tree, Gazebo/Ignition loading, or MoveIt model loading.
9. Report remaining assumptions, unchecked spatial data, and validation/smoke-test gaps.

## Commands

Run with the project or workspace Python environment (interpreter placeholder rule: router shared spine). The URDF generator and lightweight validator use only the Python standard library; downstream consumers such as RViz, Gazebo, or MoveIt may need their own runtime packages.

From this skill directory, the launcher shape is:

```bash
python scripts/urdf path/to/source.py
python scripts/urdf path/to/source.py -o path/to/robot.urdf
python scripts/urdf path/to/a.py=out/a.urdf path/to/b.py=out/b.urdf
```

Plain Python targets write a sibling `.urdf` beside the source. `-o`/`--output` is valid only with one plain target. Use `SOURCE.py=OUTPUT.urdf` pairs for custom multi-target destinations.

Relative source targets and CLI output overrides are resolved from the current working directory. When running from outside this skill directory, prefix the launcher path so target files still resolve from the intended workspace.

The launcher executes only `gen_urdf()` and validates the generated URDF output. It does not provide a separate validation-only command.

## References

- Design ledger: `urdf/design-ledger.md`
- Frame semantics: `urdf/frame-semantics.md`
- URDF generator contract: `urdf/generator-contract.md`
- URDF generation command: `urdf/gen-urdf.md`
- URDF edit workflow: `urdf/urdf-workflow.md`
- Generation-time validation expectations: `urdf/validation.md`
