# PLAN: OS-aware headless DXF redraw and validation

**Branch**: feat/701
**Issue**: https://github.com/darellchua2/civiltekk-skills/issues/701
**Base**: origin/dev

## Acceptance Criteria

- [ ] Route source CAD, usable PDF vectors, mixed/scanned PDFs, and raster-only references separately; report conversion loss.
- [ ] Keep the four image evidence profiles separate from the geometry-only output switch; enforce per-view calibration and supplied-dimension agreement in strict mode.
- [ ] Detect OS, architecture, and installed tool capabilities; consider AutoCAD Core Console only on native Windows and never launch Windows tools implicitly from WSL.
- [ ] Use CADCraft headlessly for DXF inspection and preview when selected; report version, skipped records, read-loss notes, and unsupported-record information, and reject partial reads.
- [ ] Recommend a matching official CADCraft binary and checksum verification before offering a pinned source build; never install without consent.
- [ ] Keep CAD Viewer optional for headless redraws and label unavailable required checks as skipped, unvalidated, or blocked.
- [ ] Prevent output/report paths from overwriting protected inputs, including aliases and symlinks.
- [ ] Detect moved interior geometry in fingerprints and reject strict dimensions that conflict with measured geometry.
- [ ] Add regressions for geometry, dimension, path-collision, PDF-routing, tool-selection, and CADCraft partial-read cases; document a headless smoke run when available.
- [ ] Update redraw references, generated prompt claims, and the specialist/router handoff without changing existing skill IDs or CLI entry points.

## Dependency & Consumer Map

| Node (file/module) | Depends on (must precede) | Consumers (who depends on this) | Change risk |
|-------------------|---------------------------|---------------------------------|-------------|
| `skills/cad-redraw-skill/scripts/fingerprint.py` | — | `fingerprint_diff.py`, redraw users, generated redraw prompt | high |
| `skills/cad-redraw-skill/scripts/fingerprint_diff.py` | fingerprint representation | redraw users, validation reference | high |
| `skills/cad-redraw-skill/scripts/spec_to_dxf.py` | spec contract | redraw users, generated DXF/report | high |
| `skills/cad-redraw-skill/scripts/preflight_image.py` | evidence-profile contract | image redraw users, preflight report | medium |
| `skills/cad-redraw-skill/scripts/pdf_vector_to_dxf.py` | PDF routing contract | PDF redraw users, intermediate DXF/raster evidence | high |
| `skills/cad-redraw-skill/scripts/headless_validate.py` | installed-tool capability model and CADCraft CLI behavior | redraw users, validation report and preview | high |
| `skills/cad-redraw-skill/tests/test_redraw.py` | scripts and report contracts | skill maintainers, CI, `tests/test_skill_isolation.bats` | medium |
| `skills/cad-redraw-skill/references/redraw-spec.md` | spec validator | spec authors, `spec_to_dxf.py` | high |
| `skills/cad-redraw-skill/references/validation.md` | fingerprint and validation scripts | redraw users, `SKILL.md` | high |
| `skills/cad-redraw-skill/references/linux-toolchain.md` | tool preflight and verified CLI behavior | redraw users, `SKILL.md` | medium |
| `skills/cad-redraw-skill/SKILL.md` | scripts and references | CAD users, CAD specialist agent/router, skill registry | high |
| `skills/cad-specialist-skill/SKILL.md` | redraw's optional viewer contract | `agents/cad-specialist-subagent.md`, routed CAD users | medium |
| `agents/cad-specialist-subagent.md` | router and task-specific unit rules | OpenCode CAD agent users, `deploy/setup.sh` | medium |
| `installer/registry.json` | redraw skill frontmatter description | skill installer and registry consumers | low |

## Implementation Phases

Every step is atomic and has a rationale, completion signal, and consumer list.

### Phase 1: Make evidence and outputs safe

- [ ] **1.1** Add canonical per-entity DXF geometry signatures to source fingerprints and compare them in `fingerprint_diff.py`.
    — **Why:** counts and drawing extents alone let moved interior features pass as unchanged.
    — **Done when:** signatures omit volatile handles/owners, preserve geometric tags, and compare with the documented fingerprint tolerance; a self-check moves an interior circle without changing counts or extents and the diff fails; identical drawings still pass.
    — **Consumers affected:** redraw users, `fingerprint.py`, `fingerprint_diff.py`, generated redraw prompt.

- [ ] **1.2** Separate image evidence profiles from geometry-only drawing output and enforce strict view calibration and dimension agreement.
    — **Why:** DPI metadata and printed labels cannot prove that measured geometry matches physical dimensions.
    — **Done when:** strict validation requires declared units, usable calibration on each dimensioned view, and measured dimension geometry matching its authoritative value within a documented tolerance; tests reject missing calibration, DPI-only evidence, and a mismatched dimension; the four evidence profiles remain supported.
    — **Consumers affected:** image redraw users, `preflight_image.py`, `spec_to_dxf.py`, redraw-spec and validation references.

- [ ] **1.3** Reject spec, DXF output, and report path collisions in spec validation and draw modes.
    — **Why:** an aliased report path can destroy the source spec before users can recover it.
    — **Done when:** same-path, symlink, and existing hard-link collisions fail before writing in both `--check-only` and draw modes; distinct paths still work.
    — **Consumers affected:** redraw users, `spec_to_dxf.py`, validation reports.

- [ ] **1.4** Add focused stdlib regression tests for fingerprint, strict-evidence, and path-safety behavior.
    — **Why:** these failures affect geometry trust and source-file integrity, so each needs a runnable regression.
    — **Done when:** `python3 -m unittest discover -s skills/cad-redraw-skill/tests` passes and fails against the affected pre-fix behavior.
    — **Consumers affected:** skill maintainers and the Phase 1 scripts.

### Phase 2: Route input evidence and headless tools

- [ ] **2.1** Classify PDF pages by actual vector paths, page-frame-only geometry, text, and raster images before extraction.
    — **Why:** extracted text or a page border alone is not reusable CAD geometry, while mixed pages need both vector and image evidence.
    — **Done when:** text-only and border-only fixtures are rejected as usable vector CAD; a mixed vector/raster fixture is identified and can emit a page raster for image evidence; converted DXF output is labeled PDF-derived.
    — **Consumers affected:** PDF redraw users, `pdf_vector_to_dxf.py`, input decision tree.

- [ ] **2.2** Add an OS/architecture/tool capability probe to `headless_validate.py`, with native-Windows-only AutoCAD Core Console detection.
    — **Why:** executable presence is not enough; a preview-only tool cannot satisfy structural validation, and WSL must not cross-launch Windows programs implicitly.
    — **Done when:** simulated Windows, Linux, macOS, and WSL cases report OS/architecture and capability-qualified tools; WSL never probes or launches Windows executables; CADCraft `info`/`convert`, ezdxf structural checks, and render-only alternatives are distinguished.
    — **Consumers affected:** redraw users, `headless_validate.py`, validation workflow.

- [ ] **2.3** Add CADCraft readback-and-preview execution to `headless_validate.py`.
    — **Why:** a zero exit code can still hide skipped DXF records or other read losses.
    — **Done when:** it captures the installed version, parses `info` output, reports `skipped`/`readNotes`, creates a PNG with `convert`, and exits nonzero for a partial read; fake-CLI tests cover clean and lossy reads, and an actual headless smoke run is recorded when the binary is available.
    — **Consumers affected:** redraw users, CADCraft validation reports, `headless_validate.py`.

### Phase 3: Align guidance and verify consumers

- [ ] **3.1** Rewrite the redraw entry point and references around separate source-CAD, PDF, image, and validation decision trees.
    — **Why:** users need the correct evidence path before they choose a conversion or validation tool.
    — **Done when:** documentation states four image profiles plus the separate geometry-only output flag, OS/tool capability checks, verified CADCraft CLI syntax, release/checksum/source-build consent guidance, PDF conversion losses, and honest skipped-check dispositions; it retains useful upstream evidence/fingerprint-first practices without copying code or Windows COM/DWG assumptions; the skill description no longer claims Linux-only support, fingerprint-generated prompts describe the implemented geometry checks, and `node installer/build-registry.mjs` regenerates `installer/registry.json`.
    — **Consumers affected:** CAD users, all changed redraw scripts/references, generated prompts.

- [ ] **3.2** Make CAD Viewer optional for headless redraws and scope the CAD agent's millimeter default to new authoring.
    — **Why:** mandatory viewer startup can block headless jobs, and a default unit can silently mis-scale evidence-based reconstruction.
    — **Done when:** the specialist router permits redraw to skip viewer startup unless requested, while the CAD agent says redraw units follow source evidence; other authoring workflows keep their existing handoff/default behavior.
    — **Consumers affected:** CAD specialist router, CAD specialist agent, redraw users.

- [ ] **3.3** Run the redraw regression set, skill-isolation guard, and repository verification gate against the complete branch diff.
    — **Why:** the change spans executable scripts, skill packaging, and shared CAD handoff guidance.
    — **Done when:** focused Python tests and `tests/test_skill_isolation.bats` pass; the full ticket exit gate is recorded; any available CADCraft smoke result is documented; diff review confirms CLI entry points and skill IDs remain compatible.
    — **Consumers affected:** all changed modules, skill installer users, PR reviewers.

## Technical Notes

- DXF remains the deliverable; AutoCAD and Windows automation are not redraw prerequisites.
- Keep reconstruction separate from parametric authoring; leave the `cad-dxf-skill` / `cad-generation-skill` consolidation for a follow-up.
- Use the official CADCraft release page dynamically. Match the current OS and architecture, verify the published checksum/signature, and offer a pinned upstream source build only when no compatible binary exists. Do not install packages, Rust, or applications without consent.
- CADCraft's observed CLI uses `cadcraft-cli info` and `cadcraft-cli convert`; verify exact shipped behavior with `--help` and smoke tests rather than copying unverified syntax.
- No CodeGraph index was created because `.codegraph/` is not ignored on this branch; impact analysis uses repository search.

## Dependencies

- None.
- The installer dependency map and skill IDs remain unchanged; no new cross-skill runtime dependency is planned.

## Risks & Mitigation

- Geometry signatures can create false mismatches if they include volatile DXF handles; canonicalize geometry and semantic attributes while excluding handles/owners.
- CADCraft JSON may evolve; validate required fields and fail closed with a named report rather than treating an unknown shape as clean.
- PDF border detection is heuristic; label ambiguous content as mixed/uncertain and do not upgrade it to trusted CAD.
- Strict calibration cannot be inferred from pixels or DPI metadata; block the strict deliverable until the spec contains view-specific calibrated evidence.
