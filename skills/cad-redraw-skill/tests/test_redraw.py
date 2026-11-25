"""Focused regressions for redraw geometry and strict evidence contracts."""

import importlib.util
import json
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
        script = SCRIPTS / "pdf_vector_to_dxf.py"
        module_spec = importlib.util.spec_from_file_location(
            "pdf_vector_to_dxf_under_test", script
        )
        assert module_spec is not None
        assert module_spec.loader is not None
        module = importlib.util.module_from_spec(module_spec)
        with patch.dict(sys.modules, {"pymupdf": types.ModuleType("pymupdf")}):
            module_spec.loader.exec_module(module)

        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp) / "source.pdf"
            source.write_bytes(b"protected")

            result = module.main(["--pdf", str(source), "--output", str(source)])

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


if __name__ == "__main__":
    unittest.main()
