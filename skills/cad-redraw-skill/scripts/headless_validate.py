#!/usr/bin/env python3
"""Probe local redraw-validation capabilities without launching optional CAD apps."""

import argparse
import importlib.util
import json
import os
import platform
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from path_safety import ensure_safe_outputs


def _normalize_architecture(machine: str) -> str:
    """Normalize common platform architecture names for binary matching."""
    machine = machine.lower()
    return {
        "amd64": "x86_64",
        "x64": "x86_64",
        "aarch64": "arm64",
        "armv8": "arm64",
    }.get(machine, machine or "unknown")


def _is_wsl(system: str, environ: dict[str, str], release: str) -> bool:
    """Detect WSL using the environment and kernel release signals."""
    return system.lower() == "linux" and (
        bool(environ.get("WSL_DISTRO_NAME"))
        or bool(environ.get("WSL_INTEROP"))
        or "microsoft" in release.lower()
    )


def _is_windows_executable(path: str) -> bool:
    """Recognize Windows suffixes, drive-letter paths, and WSL Windows mounts."""
    return (
        Path(path).suffix.lower() in {".exe", ".bat", ".cmd"}
        or bool(re.match(r"^[a-z]:[\\/]", path, flags=re.IGNORECASE))
        or bool(re.match(r"^/mnt/[a-z]/", path, flags=re.IGNORECASE))
    )


def _module_available(name: str) -> bool:
    """Return whether Python can resolve an optional module."""
    try:
        return importlib.util.find_spec(name) is not None
    except (ImportError, ModuleNotFoundError, ValueError):
        return False


def _tool_record(
    available: bool, status: str, **details: object
) -> dict[str, object]:
    return {"available": available, "status": status, **details}


def _parse_cadcraft_info(stdout: str) -> dict:
    """Parse the required CADCraft summary fields or reject an unknown schema."""
    try:
        info = json.loads(stdout)
    except json.JSONDecodeError as exc:
        raise ValueError(f"CADCraft info did not return valid JSON: {exc}") from exc
    if not isinstance(info, dict):
        raise TypeError("CADCraft info JSON must be an object")

    skipped = info.get("skipped")
    if not isinstance(skipped, dict):
        raise TypeError("CADCraft info is missing the skipped object")
    skipped_count = skipped.get("count")
    if type(skipped_count) is not int or skipped_count < 0:
        raise ValueError("CADCraft info skipped.count must be a non-negative integer")
    if not isinstance(skipped.get("sections"), dict):
        raise TypeError("CADCraft info skipped.sections must be an object")

    read_notes = info.get("readNotes")
    if not isinstance(read_notes, list) or not all(
        isinstance(note, str) for note in read_notes
    ):
        raise TypeError("CADCraft info readNotes must be an array of strings")
    entity_count = info.get("entityCount")
    if type(entity_count) is not int or entity_count < 0:
        raise ValueError("CADCraft info entityCount must be a non-negative integer")
    if not isinstance(info.get("counts"), dict):
        raise TypeError("CADCraft info counts must be an object")
    return info


def _validation_report(
    input_path: Path,
    environment: dict,
    tool: dict | None,
    readback: dict,
    preview: dict,
    disposition: str,
) -> dict:
    """Assemble the readback evidence and explicit validation disposition."""
    return {
        "source": {"path": str(input_path), "format": input_path.suffix.lstrip(".").upper()},
        "environment": {
            "os": environment.get("os"),
            "architecture": environment.get("architecture"),
        },
        "tool": {
            "name": "CADCraft",
            "path": tool.get("path") if tool else None,
            "version": tool.get("version") if tool else None,
        },
        "readback": readback,
        "preview": preview,
        "disposition": disposition,
    }


def validate_drawing(
    input_path: Path,
    report_path: Path | None = None,
    preview_path: Path | None = None,
    environment: dict | None = None,
    run=None,
) -> dict:
    """Read a drawing with CADCraft and optionally render a PNG preview."""
    input_path = Path(input_path).expanduser()
    report_path = Path(report_path).expanduser() if report_path else None
    preview_path = Path(preview_path).expanduser() if preview_path else None
    ensure_safe_outputs(
        [input_path],
        [path for path in (report_path, preview_path) if path is not None],
    )
    if preview_path and preview_path.suffix.lower() != ".png":
        raise ValueError("CADCraft preview output must use the .png extension")
    if not input_path.is_file():
        raise ValueError(f"drawing input does not exist or is not a file: '{input_path}'")

    run = run or subprocess.run
    environment = environment if environment is not None else probe_environment(run=run)
    tools = environment.get("tools", {})
    tool = tools.get("cadcraft_cli") if isinstance(tools, dict) else None
    commands = tool.get("commands", []) if isinstance(tool, dict) else []
    executable = tool.get("path") if isinstance(tool, dict) else None
    if (
        not isinstance(tool, dict)
        or tool.get("status") != "available"
        or not isinstance(executable, str)
        or not executable
        or not isinstance(commands, list)
        or "info" not in commands
    ):
        reason = (
            tool.get("status", "not-installed")
            if isinstance(tool, dict)
            else "not-installed"
        )
        if isinstance(tool, dict) and reason == "available":
            reason = "info-command-unavailable"
        readback: dict[str, object] = {
            "status": "skipped",
            "error": f"CADCraft is not available for this environment ({reason})",
        }
        preview: dict[str, object] = {
            "status": "skipped-unavailable",
            "path": str(preview_path) if preview_path else None,
        }
        return _validation_report(
            input_path, environment, tool, readback, preview, "blocked"
        )

    preview = {
        "status": "not-requested",
        "path": None,
    }
    try:
        result = run(
            [executable, "info", "--compact", str(input_path)],
            capture_output=True,
            text=True,
            check=False,
            timeout=60,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        readback = {"status": "failed", "error": f"CADCraft info failed: {exc}"}
        return _validation_report(
            input_path,
            environment,
            tool,
            readback,
            preview,
            "fail",
        )
    if result.returncode != 0:
        detail = (result.stderr or result.stdout or "").strip()
        readback = {
            "status": "failed",
            "error": f"CADCraft info exited with status {result.returncode}",
            "detail": detail or None,
        }
        return _validation_report(
            input_path, environment, tool, readback, preview, "fail"
        )
    try:
        info = _parse_cadcraft_info(result.stdout or "")
    except (TypeError, ValueError) as exc:
        readback = {"status": "failed", "error": str(exc)}
        return _validation_report(
            input_path, environment, tool, readback, preview, "fail"
        )

    partial = info["skipped"]["count"] > 0 or bool(info["readNotes"])
    readback = {
        "status": "partial" if partial else "pass",
        "entityCount": info["entityCount"],
        "counts": info["counts"],
        "skipped": info["skipped"],
        "readNotes": info["readNotes"],
    }
    disposition = "fail" if partial else "pass"

    if preview_path is None:
        return _validation_report(
            input_path, environment, tool, readback, preview, disposition
        )
    preview["path"] = str(preview_path)
    if partial:
        preview["status"] = "skipped-partial-read"
        return _validation_report(
            input_path, environment, tool, readback, preview, "fail"
        )
    if "convert" not in commands:
        preview["status"] = "unavailable"
        preview["error"] = "CADCraft convert is not available"
        return _validation_report(
            input_path, environment, tool, readback, preview, "blocked"
        )

    try:
        with tempfile.TemporaryDirectory(
            prefix=f".{preview_path.stem}-", dir=preview_path.parent
        ) as temporary_dir:
            temporary_preview = Path(temporary_dir) / "preview.png"
            result = run(
                [executable, "convert", str(input_path), str(temporary_preview)],
                capture_output=True,
                text=True,
                check=False,
                timeout=120,
            )
            if result.returncode != 0:
                detail = (result.stderr or result.stdout or "").strip()
                preview["status"] = "failed"
                preview["error"] = (
                    f"CADCraft convert exited with status {result.returncode}"
                )
                preview["detail"] = detail or None
                return _validation_report(
                    input_path, environment, tool, readback, preview, "fail"
                )
            try:
                preview_size = temporary_preview.stat().st_size
            except OSError as exc:
                preview["status"] = "failed"
                preview["error"] = (
                    f"CADCraft reported success but no preview is available: {exc}"
                )
                return _validation_report(
                    input_path, environment, tool, readback, preview, "fail"
                )
            if preview_size == 0:
                preview["status"] = "failed"
                preview["error"] = "CADCraft reported success but created an empty PNG"
                return _validation_report(
                    input_path, environment, tool, readback, preview, "fail"
                )
            os.replace(temporary_preview, preview_path)
    except (OSError, subprocess.TimeoutExpired) as exc:
        preview["status"] = "failed"
        preview["error"] = f"CADCraft convert failed: {exc}"
        return _validation_report(
            input_path, environment, tool, readback, preview, "fail"
        )
    preview["status"] = "created"
    return _validation_report(
        input_path, environment, tool, readback, preview, disposition
    )


def _write_json(path: Path, value: dict) -> None:
    """Write a JSON report without creating parent directories implicitly."""
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def probe_environment(
    system: str | None = None,
    machine: str | None = None,
    environ: dict[str, str] | None = None,
    release: str | None = None,
    which=None,
    module_available=None,
    run=None,
) -> dict:
    """Report OS, architecture, and installed structural/render capabilities."""
    system = system or platform.system()
    machine = machine or platform.machine()
    environ = environ if environ is not None else dict(os.environ)
    release = release if release is not None else platform.release()
    which = which or shutil.which
    module_available = module_available or _module_available
    run = run or subprocess.run

    if _is_wsl(system, environ, release):
        operating_system = "wsl"
    else:
        operating_system = {
            "linux": "linux",
            "windows": "windows",
            "darwin": "macos",
        }.get(system.lower(), system.lower() or "unknown")
    native_windows = operating_system == "windows"
    architecture = _normalize_architecture(machine)

    tools: dict[str, dict[str, object]] = {}
    structural: list[str] = []
    render_only: list[str] = []

    cadcraft_path = which("cadcraft-cli")
    if cadcraft_path and operating_system == "wsl" and _is_windows_executable(
        cadcraft_path
    ):
        tools["cadcraft_cli"] = _tool_record(
            False,
            "skipped-windows-executable",
            path=cadcraft_path,
            version=None,
            commands=[],
        )
    elif cadcraft_path:
        version_result = None
        help_result = None
        probe_error = None
        try:
            version_result = run(
                [cadcraft_path, "--version"],
                capture_output=True,
                text=True,
                check=False,
                timeout=10,
            )
            help_result = run(
                [cadcraft_path, "--help"],
                capture_output=True,
                text=True,
                check=False,
                timeout=10,
            )
        except (OSError, subprocess.TimeoutExpired) as exc:
            probe_error = str(exc)

        help_text = (
            (help_result.stdout + "\n" + help_result.stderr)
            if help_result is not None
            else ""
        )
        commands = [
            command
            for command in ("info", "convert")
            if re.search(rf"^\s+{command}\s+", help_text, flags=re.MULTILINE)
        ]
        version_text = ""
        if version_result is not None:
            version_text = (version_result.stdout or version_result.stderr).strip()
        verified = (
            probe_error is None
            and version_result is not None
            and version_result.returncode == 0
            and help_result is not None
            and help_result.returncode == 0
        )
        tools["cadcraft_cli"] = _tool_record(
            True,
            "available" if verified else "probe-failed",
            path=cadcraft_path,
            version=version_text or None,
            commands=commands,
            error=probe_error,
        )
        if verified and "info" in commands:
            structural.append("cadcraft-cli info")
        if verified and "convert" in commands:
            render_only.append("cadcraft-cli convert (PNG visual preview)")
    else:
        tools["cadcraft_cli"] = _tool_record(
            False, "not-installed", path=None, version=None, commands=[]
        )

    ezdxf_available = module_available("ezdxf")
    matplotlib_available = module_available("matplotlib")
    tools["ezdxf"] = _tool_record(
        ezdxf_available,
        "available" if ezdxf_available else "not-installed",
        structural_audit=ezdxf_available,
    )
    tools["matplotlib"] = _tool_record(
        matplotlib_available,
        "available" if matplotlib_available else "not-installed",
        rendering=ezdxf_available and matplotlib_available,
    )
    if ezdxf_available:
        structural.append("ezdxf audit")
    if ezdxf_available and matplotlib_available:
        render_only.append("render_preview.py (ezdxf + matplotlib)")

    if native_windows:
        core_console_path = which("accoreconsole.exe") or which("accoreconsole")
        tools["autocad_core_console"] = _tool_record(
            bool(core_console_path),
            "available" if core_console_path else "not-installed",
            path=core_console_path,
        )
    else:
        tools["autocad_core_console"] = _tool_record(
            False, "native-windows-only", path=None
        )

    return {
        "os": operating_system,
        "architecture": architecture,
        "release": release,
        "tools": tools,
        "options": {
            "structural_validation": structural,
            "render_only": render_only,
        },
    }


def main(argv: list[str] | None = None) -> int:
    """Probe capabilities or perform CADCraft readback and optional preview."""
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_mutually_exclusive_group(required=True)
    modes.add_argument(
        "--probe",
        action="store_true",
        help="report OS, architecture, and validation/render capabilities",
    )
    modes.add_argument("--input", help="drawing to read back with CADCraft")
    parser.add_argument("--preview", help="optional CADCraft PNG preview output")
    parser.add_argument("--report", help="optional JSON report output")
    args = parser.parse_args(argv)
    if args.probe:
        if args.preview:
            parser.error("--preview requires --input")
        report = probe_environment()
        result = 0
    else:
        try:
            report = validate_drawing(
                Path(args.input),
                report_path=Path(args.report) if args.report else None,
                preview_path=Path(args.preview) if args.preview else None,
            )
        except (OSError, ValueError) as exc:
            print(f"headless validation failed: {exc}", file=sys.stderr)
            return 1
        result = {"pass": 0, "fail": 1, "blocked": 2}.get(
            report["disposition"], 1
        )
    if args.report:
        try:
            _write_json(Path(args.report), report)
        except OSError as exc:
            print(f"cannot write report '{args.report}': {exc}", file=sys.stderr)
            return 1
    print(json.dumps(report, indent=2, ensure_ascii=False))
    return result


if __name__ == "__main__":
    sys.exit(main())
