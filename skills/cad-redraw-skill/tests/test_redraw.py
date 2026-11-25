"""Focused regressions for redraw geometry and strict evidence contracts."""

import importlib.util
import json
import os
import sys
import tempfile
import types
import unittest
from copy import deepcopy
from pathlib import Path
from unittest.mock import patch

SCRIPTS = Path(__file__).resolve().parents[1] / "scripts"
sys.path.insert(0, str(SCRIPTS))

import ezdxf
import fingerprint
import fingerprint_diff
import preflight_image
import spec_to_dxf


def _drawing(circle_x: float = 25.0):
    doc = ezdxf.new("R2010", setup=True)
    msp = doc.modelspace()
    msp.add_lwpolyline(
        [(0, 0), (100, 0), (100, 100), (0, 100)],
        close=True,
        dxfattribs={"layer": "OUTLINE"},
    )
    msp.add_circle((circle_x, 25), 5, dxfattribs={"layer": "DETAIL"})
    return doc


def _fingerprint(doc) -> dict:
    return fingerprint.build_fingerprint(doc, "fixture.dxf", "dxf", "native")


def _strict_spec() -> dict:
    spec = deepcopy(spec_to_dxf._valid_spec())
    spec["profile"] = "strict-dimensioned"
    dimension = next(entity for entity in spec["entities"] if entity["id"] == "d2")
    dimension["geometry"]["p2"] = [50, 50]
    return spec


def _load_pdf_module(pymupdf=None):
    """Load the PDF CLI with a lightweight PyMuPDF stand-in."""
    module_spec = importlib.util.spec_from_file_location(
        "pdf_vector_to_dxf_under_test", SCRIPTS / "pdf_vector_to_dxf.py"
    )
    assert module_spec is not None
    assert module_spec.loader is not None
    module = importlib.util.module_from_spec(module_spec)
    stub = pymupdf or types.ModuleType("pymupdf")
    with patch.dict(sys.modules, {"pymupdf": stub}):
        module_spec.loader.exec_module(module)
    return module


def _load_headless_module():
    """Load the headless validator without running its CLI entry point."""
    module_spec = importlib.util.spec_from_file_location(
        "headless_validate_under_test", SCRIPTS / "headless_validate.py"
    )
    assert module_spec is not None
    assert module_spec.loader is not None
    module = importlib.util.module_from_spec(module_spec)
    module_spec.loader.exec_module(module)
    return module


class _FakeRect:
    def __init__(self, x0, y0, x1, y1):
        self.x0, self.y0, self.x1, self.y1 = x0, y0, x1, y1
        self.width, self.height = x1 - x0, y1 - y0


class _FakePdfPage:
    def __init__(self, drawings=(), words=(), images=()):
        self.rect = _FakeRect(0, 0, 612, 792)
        self.drawings, self.words, self.images = drawings, words, images

    def get_drawings(self):
        return self.drawings

    def get_text(self, kind):
        assert kind == "words"
        return self.words

    def get_image_info(self, xrefs=True):
        assert xrefs
        return self.images

    def get_pixmap(self, matrix, alpha):
        assert alpha is False
        return _FakePixmap()


class _FakePixmap:
    def save(self, path):
        Path(path).write_bytes(b"raster")


class _FakePdfDocument:
    def __init__(self, page):
        self.page_count = 1
        self.page = page

    def __getitem__(self, index):
        assert index == 0
        return self.page

    def close(self):
        pass


class FingerprintGeometryTests(unittest.TestCase):
    def test_identical_geometry_matches(self):
        source = _fingerprint(_drawing())
        target = _fingerprint(_drawing())

        delta = fingerprint_diff.compare_fingerprints(
            source, target, fingerprint_diff.DEFAULT_TOLERANCE
        )

        self.assertTrue(delta["match"])

    def test_moved_interior_circle_fails_without_changing_counts_or_extents(self):
        source = _fingerprint(_drawing(25))
        target = _fingerprint(_drawing(35))
        self.assertEqual(source["entities"], target["entities"])
        self.assertEqual(source["extents"], target["extents"])

        delta = fingerprint_diff.compare_fingerprints(
            source, target, fingerprint_diff.DEFAULT_TOLERANCE
        )

        self.assertFalse(delta["match"])
        self.assertIn("geometry", {item["check"] for item in delta["mismatches"]})

    def test_geometry_within_tolerance_matches(self):
        source = _fingerprint(_drawing(25))
        target = _fingerprint(_drawing(25.0000005))

        delta = fingerprint_diff.compare_fingerprints(source, target, 1e-6)

        self.assertTrue(delta["match"])

    def test_legacy_fingerprints_without_geometry_fail_closed(self):
        source = _fingerprint(_drawing())
        target = deepcopy(source)
        source.pop("geometry")
        target.pop("geometry")

        delta = fingerprint_diff.compare_fingerprints(source, target, 1e-6)

        self.assertFalse(delta["match"])
        self.assertIn("regenerate both", delta["mismatches"][-1]["message"])

    def test_invalid_tolerance_is_rejected(self):
        source = _fingerprint(_drawing())

        for tolerance in (float("nan"), float("inf"), -1.0):
            with self.subTest(tolerance=tolerance), self.assertRaises(ValueError):
                fingerprint_diff.compare_fingerprints(source, source, tolerance)

    def test_changed_entity_handles_do_not_change_geometry(self):
        source_doc = _drawing()
        target_doc = _drawing()
        circle = next(iter(target_doc.modelspace().query("CIRCLE")))
        circle.dxf.handle = "F00D"

        delta = fingerprint_diff.compare_fingerprints(
            _fingerprint(source_doc),
            _fingerprint(target_doc),
            fingerprint_diff.DEFAULT_TOLERANCE,
        )

        self.assertTrue(delta["match"])

    def test_generated_redraw_prompt_describes_handle_free_geometry_checks(self):
        prompt = fingerprint.build_prompt(_fingerprint(_drawing()))

        self.assertIn("per-entity DXF tag signatures", prompt)
        self.assertIn("volatile entity and owner handles are excluded", prompt)


class StrictEvidenceTests(unittest.TestCase):
    def test_calibrated_consistent_dimensioned_spec_is_valid(self):
        report = spec_to_dxf.validate_spec(_strict_spec())

        self.assertTrue(report["valid"], report["errors"])

    def test_strict_dimensioned_requires_view_calibration_not_dpi_metadata(self):
        spec = _strict_spec()
        side_view = {"id": "side", "dpi": 300}
        spec["views"].append(side_view)
        spec["entities"].append(
            {
                "id": "d3",
                "type": "dimension",
                "view": "side",
                "layer": "DIM",
                "evidence": "known",
                "text": "10",
                "geometry": {"p1": [0, 0], "p2": [10, 0], "offset": 2, "value": 10},
            }
        )

        report = spec_to_dxf.validate_spec(spec)

        self.assertFalse(report["valid"])
        self.assertTrue(
            any(
                error["code"] == "calibration" and error["entity"] == "side"
                for error in report["errors"]
            )
        )

    def test_strict_dimensioned_reports_malformed_calibration_evidence(self):
        spec = _strict_spec()
        spec["views"][0]["calibration"]["evidence"] = []

        report = spec_to_dxf.validate_spec(spec)

        self.assertFalse(report["valid"])
        self.assertIn("calibration", {error["code"] for error in report["errors"]})

    def test_strict_dimensioned_rejects_value_that_disagrees_with_geometry(self):
        spec = _strict_spec()
        dimension = next(entity for entity in spec["entities"] if entity["id"] == "d1")
        dimension["geometry"]["value"] = 99.9

        report = spec_to_dxf.validate_spec(spec)

        self.assertFalse(report["valid"])
        self.assertIn(
            "dimension_mismatch", {error["code"] for error in report["errors"]}
        )

    def test_strict_dimensioned_rejects_non_finite_supplied_values(self):
        spec = _strict_spec()
        dimension = next(entity for entity in spec["entities"] if entity["id"] == "d1")
        dimension["geometry"]["value"] = float("nan")

        report = spec_to_dxf.validate_spec(spec)

        self.assertFalse(report["valid"])

    def test_strict_dimensioned_reports_malformed_geometry_without_raising(self):
        spec = _strict_spec()
        dimension = next(entity for entity in spec["entities"] if entity["id"] == "d1")
        dimension["geometry"] = "invalid"

        report = spec_to_dxf.validate_spec(spec)

        self.assertFalse(report["valid"])
        self.assertTrue(any(error["code"] == "schema" for error in report["errors"]))

    def test_geometry_only_is_an_output_option_not_an_evidence_profile(self):
        spec = _strict_spec()
        spec["profile"] = "geometry-only"

        report = spec_to_dxf.validate_spec(spec)

        self.assertFalse(report["valid"])
        self.assertNotIn("geometry-only", spec_to_dxf.PROFILES)
        self.assertNotIn("geometry-only", preflight_image.PROFILES)

    def test_geometry_only_output_flag_drops_annotations_without_changing_profile(self):
        spec = deepcopy(spec_to_dxf._valid_spec())
        self.assertEqual(spec["profile"], "general")
        with tempfile.TemporaryDirectory() as tmp:
            output = Path(tmp) / "geometry-only.dxf"
            dropped = spec_to_dxf.draw_spec(spec, output, geometry_only=True)
            doc = ezdxf.readfile(output)

        self.assertEqual(set(dropped), {"e5", "d1", "d2"})
        self.assertEqual(len(doc.modelspace().query("TEXT MTEXT DIMENSION")), 0)


class PathSafetyTests(unittest.TestCase):
    def test_pdf_converter_rejects_output_alias_before_pdf_read(self):
        module = _load_pdf_module()

        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp) / "source.pdf"
            source.write_bytes(b"protected")

            result = module.main(["--pdf", str(source), "--output", str(source)])

            self.assertNotEqual(result, 0)
            self.assertEqual(source.read_bytes(), b"protected")

    def test_pdf_converter_guards_report_and_raster_aliases(self):
        module = _load_pdf_module()
        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp) / "source.pdf"
            source.write_bytes(b"protected")

            for option in ("--report", "--raster-output"):
                with self.subTest(option=option):
                    target = source
                    if option == "--raster-output":
                        target = Path(tmp) / "source.png"
                        target.symlink_to(source)
                    result = module.main(
                        [
                            "--pdf",
                            str(source),
                            "--classify-only",
                            option,
                            str(target),
                        ]
                    )
                    self.assertNotEqual(result, 0)
                    self.assertEqual(source.read_bytes(), b"protected")

    def test_check_only_report_cannot_overwrite_its_spec(self):
        with tempfile.TemporaryDirectory() as tmp:
            spec_path = Path(tmp) / "spec.json"
            spec_path.write_text(json.dumps(spec_to_dxf._valid_spec()), encoding="utf-8")
            before = spec_path.read_bytes()

            result = spec_to_dxf.main(
                [
                    "--spec",
                    str(spec_path),
                    "--check-only",
                    "--report",
                    str(spec_path),
                ]
            )

            self.assertNotEqual(result, 0)
            self.assertEqual(spec_path.read_bytes(), before)

    def test_path_guard_rejects_same_symlink_and_hardlink_aliases(self):
        from path_safety import ensure_safe_outputs

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source = root / "source"
            source.write_text("keep", encoding="utf-8")
            symlink = root / "symlink"
            symlink.symlink_to(source)
            hardlink = root / "hardlink"
            hardlink.hardlink_to(source)

            for output in (source, symlink, hardlink):
                with self.subTest(output=output), self.assertRaisesRegex(
                    ValueError, "aliases protected input"
                ):
                    ensure_safe_outputs([source], [output])

    def test_path_guard_rejects_output_aliases_and_allows_distinct_paths(self):
        from path_safety import ensure_safe_outputs

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source = root / "source"
            first_output = root / "first"
            alias = root / "alias"
            source.write_text("input", encoding="utf-8")
            first_output.write_text("output", encoding="utf-8")
            alias.symlink_to(first_output)

            with self.assertRaisesRegex(ValueError, "output paths"):
                ensure_safe_outputs([source], [first_output, alias])
            ensure_safe_outputs([source], [root / "new-output"])


class PdfClassificationTests(unittest.TestCase):
    def test_text_only_page_is_not_usable_vector_cad(self):
        module = _load_pdf_module()
        page = _FakePdfPage(words=[(10, 10, 40, 20, "TITLE", 0, 0, 0)])

        result = module.classify_page(page)

        self.assertEqual(result["route"], "text-only")
        self.assertFalse(result["usable_vector"])

    def test_page_frame_only_is_not_usable_vector_cad(self):
        module = _load_pdf_module()
        border = ("re", _FakeRect(36, 36, 576, 756))
        page = _FakePdfPage(drawings=[{"items": [border]}])

        result = module.classify_page(page)

        self.assertEqual(result["route"], "page-frame-only")
        self.assertFalse(result["usable_vector"])

    def test_raster_page_with_searchable_text_uses_raster_reference_route(self):
        module = _load_pdf_module()
        page = _FakePdfPage(
            words=[(10, 10, 40, 20, "OCR", 0, 0, 0)],
            images=[{"xref": 1}],
        )

        result = module.classify_page(page)

        self.assertEqual(result["route"], "raster-only")
        self.assertFalse(result["usable_vector"])

    def test_vector_and_raster_content_uses_mixed_route(self):
        module = _load_pdf_module()
        line = (
            "l",
            types.SimpleNamespace(x=100, y=100),
            types.SimpleNamespace(x=200, y=100),
        )
        page = _FakePdfPage(drawings=[{"items": [line]}], images=[{"xref": 1}])

        result = module.classify_page(page)

        self.assertEqual(result["route"], "mixed-vector-raster")
        self.assertTrue(result["usable_vector"])
        self.assertEqual(result["raster_images"], 1)

    def test_mixed_page_can_write_a_separate_raster(self):
        pymupdf = types.ModuleType("pymupdf")
        pymupdf.Matrix = lambda x, y: (x, y)
        module = _load_pdf_module(pymupdf)
        page = _FakePdfPage()

        with tempfile.TemporaryDirectory() as tmp:
            raster = Path(tmp) / "page.png"
            module.render_page_raster(page, raster)

            self.assertEqual(raster.read_bytes(), b"raster")

    def test_raster_output_requires_png_extension(self):
        module = _load_pdf_module()

        with tempfile.TemporaryDirectory() as tmp:
            pdf = Path(tmp) / "source.pdf"
            pdf.write_bytes(b"fixture")
            with self.assertRaises(SystemExit) as raised:
                module.main(
                    [
                        "--pdf",
                        str(pdf),
                        "--classify-only",
                        "--raster-output",
                        str(Path(tmp) / "page.jpg"),
                    ]
                )

            self.assertEqual(raised.exception.code, 2)

    def test_text_only_cli_page_does_not_write_a_dxf(self):
        pymupdf = types.ModuleType("pymupdf")
        pymupdf.open = lambda path: _FakePdfDocument(
            _FakePdfPage(words=[(10, 10, 40, 20, "TITLE", 0, 0, 0)])
        )
        module = _load_pdf_module(pymupdf)

        with tempfile.TemporaryDirectory() as tmp:
            pdf = Path(tmp) / "text.pdf"
            output = Path(tmp) / "text.dxf"
            pdf.write_bytes(b"fixture")

            result = module.main(["--pdf", str(pdf), "--output", str(output)])

            self.assertNotEqual(result, 0)
            self.assertFalse(output.exists())

    def test_border_only_cli_reports_route_without_writing_a_dxf(self):
        border = ("re", _FakeRect(36, 36, 576, 756))
        page = _FakePdfPage(drawings=[{"items": [border]}])
        pymupdf = types.ModuleType("pymupdf")
        pymupdf.open = lambda path: _FakePdfDocument(page)
        module = _load_pdf_module(pymupdf)

        with tempfile.TemporaryDirectory() as tmp:
            pdf = Path(tmp) / "border.pdf"
            output = Path(tmp) / "border.dxf"
            report_path = Path(tmp) / "report.json"
            pdf.write_bytes(b"fixture")

            result = module.main(
                [
                    "--pdf",
                    str(pdf),
                    "--output",
                    str(output),
                    "--report",
                    str(report_path),
                ]
            )

            self.assertEqual(result, 1)
            self.assertFalse(output.exists())
            self.assertEqual(json.loads(report_path.read_text())["classification"], "page-frame-only")

    def test_classify_only_emits_mixed_page_raster_and_report(self):
        line = (
            "l",
            types.SimpleNamespace(x=100, y=100),
            types.SimpleNamespace(x=200, y=100),
        )
        page = _FakePdfPage(drawings=[{"items": [line]}], images=[{"xref": 1}])
        pymupdf = types.ModuleType("pymupdf")
        pymupdf.open = lambda path: _FakePdfDocument(page)
        pymupdf.Matrix = lambda x, y: (x, y)
        module = _load_pdf_module(pymupdf)

        with tempfile.TemporaryDirectory() as tmp:
            pdf = Path(tmp) / "mixed.pdf"
            raster = Path(tmp) / "mixed.png"
            report_path = Path(tmp) / "report.json"
            pdf.write_bytes(b"fixture")

            result = module.main(
                [
                    "--pdf",
                    str(pdf),
                    "--classify-only",
                    "--raster-output",
                    str(raster),
                    "--report",
                    str(report_path),
                ]
            )

            report = json.loads(report_path.read_text())
            self.assertEqual(result, 0)
            self.assertEqual(report["classification"], "mixed-vector-raster")
            self.assertEqual(report["raster_output"]["dpi"], 150)
            self.assertEqual(raster.read_bytes(), b"raster")

    def test_vector_conversion_marks_dxf_provenance_and_reports_losses(self):
        line = (
            "l",
            types.SimpleNamespace(x=100, y=100),
            types.SimpleNamespace(x=200, y=100),
        )
        curve = (
            "c",
            types.SimpleNamespace(x=100, y=200),
            types.SimpleNamespace(x=120, y=180),
            types.SimpleNamespace(x=180, y=220),
            types.SimpleNamespace(x=200, y=200),
        )
        page = _FakePdfPage(
            drawings=[
                {
                    "items": [
                        line,
                        ("re", _FakeRect(36, 36, 576, 756)),
                        curve,
                        ("unsupported",),
                    ]
                }
            ],
            images=[{"xref": 1}],
        )
        pymupdf = types.ModuleType("pymupdf")
        pymupdf.open = lambda path: _FakePdfDocument(page)
        module = _load_pdf_module(pymupdf)

        with tempfile.TemporaryDirectory() as tmp:
            pdf = Path(tmp) / "source.pdf"
            output = Path(tmp) / "output.dxf"
            report_path = Path(tmp) / "report.json"
            pdf.write_bytes(b"fixture")

            result = module.main(
                [
                    "--pdf",
                    str(pdf),
                    "--output",
                    str(output),
                    "--report",
                    str(report_path),
                ]
            )

            report = json.loads(report_path.read_text())
            dxf = ezdxf.readfile(output)
            losses = report["conversion"]["losses"]
            self.assertEqual(result, 0)
            self.assertIn("PDF-derived", dxf.header["$PROJECTNAME"])
            self.assertEqual(report["conversion"]["provenance"], "PDF-derived")
            self.assertEqual(losses["raster_images_not_embedded"], 1)
            self.assertEqual(losses["page_frame_items_omitted"], 1)
            self.assertEqual(losses["unsupported_path_ops_omitted"], {"unsupported": 1})
            self.assertIs(type(losses["curves_flattened_to_lines"]), int)
            self.assertEqual(losses["curves_flattened_to_lines"], 1)
            linework = dxf.modelspace().query('LINE[layer=="LINEWORK"]')
            linework_x = [
                point.x
                for entity in linework
                for point in (entity.dxf.start, entity.dxf.end)
            ]
            self.assertGreater(len(linework), 1)
            self.assertGreaterEqual(min(linework_x), 100)
            self.assertLessEqual(max(linework_x), 200)


class HeadlessProbeTests(unittest.TestCase):
    def test_probe_separates_structural_checks_from_render_only_tools(self):
        module = _load_headless_module()
        run_calls = []

        def which(name):
            return "/usr/bin/cadcraft-cli" if name == "cadcraft-cli" else None

        def run(args, **kwargs):
            run_calls.append(args)
            if args[-1] == "--help":
                output = "Commands:\n  info  Print JSON\n  convert  Render drawing\n"
            else:
                output = "cadcraft-cli 0.18.0"
            return types.SimpleNamespace(returncode=0, stdout=output, stderr="")

        result = module.probe_environment(
            system="Linux",
            machine="x86_64",
            environ={},
            release="6.8.0",
            which=which,
            module_available=lambda name: name in {"ezdxf", "matplotlib"},
            run=run,
        )

        self.assertEqual(result["os"], "linux")
        self.assertEqual(result["architecture"], "x86_64")
        self.assertIn("cadcraft-cli info", result["options"]["structural_validation"])
        self.assertIn("ezdxf audit", result["options"]["structural_validation"])
        self.assertTrue(
            any(
                option.startswith("cadcraft-cli convert")
                for option in result["options"]["render_only"]
            )
        )
        self.assertNotIn("cadcraft-cli convert", result["options"]["structural_validation"])
        self.assertEqual(len(run_calls), 2)

    def test_wsl_skips_windows_executable_without_invoking_it(self):
        module = _load_headless_module()
        which_calls, run_calls = [], []

        def which(name):
            which_calls.append(name)
            if name == "cadcraft-cli":
                return "/mnt/c/Program Files/CADCraft/cadcraft-cli.exe"
            return None

        def run(args, **kwargs):
            run_calls.append(args)
            return types.SimpleNamespace(returncode=0, stdout="", stderr="")

        result = module.probe_environment(
            system="Linux",
            machine="aarch64",
            environ={"WSL_DISTRO_NAME": "Ubuntu"},
            release="6.8.0-microsoft-standard-WSL2",
            which=which,
            module_available=lambda name: name == "ezdxf",
            run=run,
        )

        self.assertEqual(result["os"], "wsl")
        self.assertEqual(result["architecture"], "arm64")
        self.assertNotIn("accoreconsole.exe", which_calls)
        self.assertEqual(run_calls, [])
        self.assertEqual(
            result["tools"]["cadcraft_cli"]["status"],
            "skipped-windows-executable",
        )

    def test_wsl_skips_tools_from_windows_mounts_without_suffix(self):
        module = _load_headless_module()
        run_calls = []

        result = module.probe_environment(
            system="Linux",
            machine="x86_64",
            environ={"WSL_INTEROP": "/run/WSL/123_interop"},
            release="6.8.0-microsoft-standard-WSL2",
            which=lambda name: (
                "/mnt/c/Program Files/CADCraft/cadcraft-cli"
                if name == "cadcraft-cli"
                else None
            ),
            module_available=lambda name: False,
            run=lambda args, **kwargs: run_calls.append(args)
            or types.SimpleNamespace(returncode=0, stdout="", stderr=""),
        )

        self.assertEqual(
            result["tools"]["cadcraft_cli"]["status"],
            "skipped-windows-executable",
        )
        self.assertEqual(run_calls, [])

    def test_core_console_is_probed_only_on_native_windows(self):
        module = _load_headless_module()
        which_calls, run_calls = [], []

        def which(name):
            which_calls.append(name)
            if name == "accoreconsole.exe":
                return r"C:\Program Files\Autodesk\accoreconsole.exe"
            return None

        result = module.probe_environment(
            system="Windows",
            machine="AMD64",
            environ={},
            release="Windows-11",
            which=which,
            module_available=lambda name: False,
            run=lambda args, **kwargs: run_calls.append(args)
            or types.SimpleNamespace(returncode=1, stdout="", stderr=""),
        )

        self.assertEqual(result["os"], "windows")
        self.assertEqual(result["architecture"], "x86_64")
        self.assertTrue(result["tools"]["autocad_core_console"]["available"])
        self.assertIn("accoreconsole.exe", which_calls)
        self.assertFalse(any("accoreconsole" in str(arg).lower() for arg in run_calls))

    def test_macos_reports_arm_architecture_and_skips_windows_probe(self):
        module = _load_headless_module()
        which_calls = []

        def which(name):
            which_calls.append(name)

        result = module.probe_environment(
            system="Darwin",
            machine="arm64",
            environ={},
            release="24.0.0",
            which=which,
            module_available=lambda name: False,
            run=lambda args, **kwargs: types.SimpleNamespace(
                returncode=1, stdout="", stderr=""
            ),
        )

        self.assertEqual(result["os"], "macos")
        self.assertEqual(result["architecture"], "arm64")
        self.assertEqual(result["tools"]["autocad_core_console"]["status"], "native-windows-only")
        self.assertNotIn("accoreconsole.exe", which_calls)


class HeadlessValidationTests(unittest.TestCase):
    @staticmethod
    def _environment():
        return {
            "os": "linux",
            "architecture": "x86_64",
            "tools": {
                "cadcraft_cli": {
                    "available": True,
                    "status": "available",
                    "path": "/usr/bin/cadcraft-cli",
                    "version": "cadcraft-cli 0.18.0",
                    "commands": ["info", "convert"],
                }
            },
        }

    @staticmethod
    def _info(skipped=None, read_notes=None):
        return {
            "entityCount": 2,
            "counts": {"Line": 2},
            "skipped": skipped or {"count": 0, "sections": {}},
            "readNotes": read_notes or [],
        }

    def test_clean_cadcraft_readback_and_preview_pass(self):
        module = _load_headless_module()
        calls = []

        def run(args, **kwargs):
            calls.append(args)
            if "info" in args:
                return types.SimpleNamespace(
                    returncode=0,
                    stdout=json.dumps(self._info()),
                    stderr="",
                )
            Path(args[-1]).write_bytes(b"png")
            return types.SimpleNamespace(returncode=0, stdout="", stderr="")

        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp) / "drawing.dxf"
            preview = Path(tmp) / "preview.png"
            source.write_bytes(b"dxf")

            report = module.validate_drawing(
                source,
                preview_path=preview,
                environment=self._environment(),
                run=run,
            )

            self.assertEqual(report["disposition"], "pass")
            self.assertEqual(report["readback"]["status"], "pass")
            self.assertEqual(report["readback"]["skipped"]["count"], 0)
            self.assertEqual(report["readback"]["readNotes"], [])
            self.assertEqual(report["preview"]["status"], "created")
            self.assertEqual(preview.read_bytes(), b"png")
            self.assertEqual([args[1] for args in calls], ["info", "convert"])

    def test_partial_cadcraft_read_fails_and_does_not_render(self):
        module = _load_headless_module()
        calls = []

        def run(args, **kwargs):
            calls.append(args)
            return types.SimpleNamespace(
                returncode=0,
                stdout=json.dumps(
                    self._info(
                        skipped={"count": 1, "sections": {"ENTITIES": 1}},
                    )
                ),
                stderr="",
            )

        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp) / "drawing.dxf"
            preview = Path(tmp) / "preview.png"
            source.write_bytes(b"dxf")

            report = module.validate_drawing(
                source,
                preview_path=preview,
                environment=self._environment(),
                run=run,
            )

            self.assertEqual(report["disposition"], "fail")
            self.assertEqual(report["readback"]["status"], "partial")
            self.assertEqual(report["readback"]["skipped"]["count"], 1)
            self.assertEqual(report["readback"]["readNotes"], [])
            self.assertEqual(report["preview"]["status"], "skipped-partial-read")
            self.assertEqual([args[1] for args in calls], ["info"])
            self.assertFalse(preview.exists())

    def test_read_notes_alone_mark_cadcraft_readback_partial(self):
        module = _load_headless_module()

        def run(args, **kwargs):
            return types.SimpleNamespace(
                returncode=0,
                stdout=json.dumps(
                    self._info(read_notes=["Unsupported entity was skipped"])
                ),
                stderr="",
            )

        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp) / "drawing.dxf"
            source.write_bytes(b"dxf")

            report = module.validate_drawing(
                source,
                environment=self._environment(),
                run=run,
            )

            self.assertEqual(report["disposition"], "fail")
            self.assertEqual(report["readback"]["status"], "partial")
            self.assertEqual(report["readback"]["skipped"]["count"], 0)
            self.assertEqual(
                report["readback"]["readNotes"], ["Unsupported entity was skipped"]
            )

    def test_missing_fresh_preview_does_not_accept_or_overwrite_old_preview(self):
        module = _load_headless_module()

        def run(args, **kwargs):
            if "info" in args:
                return types.SimpleNamespace(
                    returncode=0,
                    stdout=json.dumps(self._info()),
                    stderr="",
                )
            return types.SimpleNamespace(returncode=0, stdout="", stderr="")

        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp) / "drawing.dxf"
            preview = Path(tmp) / "preview.png"
            source.write_bytes(b"dxf")
            preview.write_bytes(b"old-preview")

            report = module.validate_drawing(
                source,
                preview_path=preview,
                environment=self._environment(),
                run=run,
            )

            self.assertEqual(report["disposition"], "fail")
            self.assertEqual(report["preview"]["status"], "failed")
            self.assertEqual(preview.read_bytes(), b"old-preview")

    def test_preview_render_is_not_confused_by_coarse_timestamps(self):
        module = _load_headless_module()

        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp) / "drawing.dxf"
            preview = Path(tmp) / "preview.png"
            source.write_bytes(b"dxf")
            preview.write_bytes(b"old")
            previous = preview.stat()

            def run(args, **kwargs):
                if "info" in args:
                    return types.SimpleNamespace(
                        returncode=0,
                        stdout=json.dumps(self._info()),
                        stderr="",
                    )
                target = Path(args[-1])
                target.write_bytes(b"new")
                os.utime(
                    target,
                    ns=(previous.st_atime_ns, previous.st_mtime_ns),
                )
                return types.SimpleNamespace(returncode=0, stdout="", stderr="")

            report = module.validate_drawing(
                source,
                preview_path=preview,
                environment=self._environment(),
                run=run,
            )

            self.assertEqual(report["disposition"], "pass")
            self.assertEqual(report["preview"]["status"], "created")
            self.assertEqual(preview.read_bytes(), b"new")

    def test_unknown_cadcraft_info_schema_fails_closed(self):
        module = _load_headless_module()

        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp) / "drawing.dxf"
            source.write_bytes(b"dxf")
            report = module.validate_drawing(
                source,
                environment=self._environment(),
                run=lambda args, **kwargs: types.SimpleNamespace(
                    returncode=0,
                    stdout=json.dumps(
                        {
                            "counts": {},
                            "skipped": {"count": 0, "sections": {}},
                        }
                    ),
                    stderr="",
                ),
            )

            self.assertEqual(report["disposition"], "fail")
            self.assertEqual(report["readback"]["status"], "failed")
            self.assertIn("readNotes", report["readback"]["error"])

    def test_missing_cadcraft_info_command_is_blocked_without_execution(self):
        module = _load_headless_module()
        environment = self._environment()
        environment["tools"]["cadcraft_cli"]["commands"] = ["convert"]
        calls = []

        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp) / "drawing.dxf"
            source.write_bytes(b"dxf")
            report = module.validate_drawing(
                source,
                environment=environment,
                run=lambda args, **kwargs: calls.append(args),
            )

        self.assertEqual(report["disposition"], "blocked")
        self.assertEqual(report["readback"]["status"], "skipped")
        self.assertIn("info-command-unavailable", report["readback"]["error"])
        self.assertEqual(calls, [])

    def test_path_safety_rejects_report_alias_before_cadcraft_read(self):
        module = _load_headless_module()
        calls = []

        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp) / "drawing.dxf"
            source.write_bytes(b"protected")
            with self.assertRaisesRegex(ValueError, "aliases protected input"):
                module.validate_drawing(
                    source,
                    report_path=source,
                    environment=self._environment(),
                    run=lambda args, **kwargs: calls.append(args),
                )

            self.assertEqual(calls, [])
            self.assertEqual(source.read_bytes(), b"protected")


if __name__ == "__main__":
    unittest.main()
