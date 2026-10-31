"""
schema_validator.py
===================
Standalone, dependency-free validator for ``slide_data_list`` plus a two-layer
retry wrapper for LLM-produced JSON.

Layered design (mirrors presenton's ``generate_structured_with_schema_retries``):

* **Inner layer** — repairs JSON *parse* failures (fenced code blocks, trailing
  commas, single quotes) so a slightly-malformed LLM payload still becomes a
  Python object.
* **Outer layer** — runs schema validation and returns structured, human-
  readable errors (slide index + field path + reason) that a caller can feed
  back to the model so it self-corrects.

Public API
----------
    validate_slide_data_list(data, *, strict=False, density_mode=None) -> ValidationResult
    parse_and_validate(raw_text, *, strict=False, density_mode=None)   -> ValidationResult
    ValidationResult.is_valid / .errors / .warnings
    ValidationError  (raised only by the engine on fatal structural breakage)

Severity model
--------------
* ``error``   — a structural/content violation. In ``strict`` mode these abort
  the build; otherwise the engine still degrades gracefully.
* ``warning`` — e.g. a missing *recommended* field (``notes``), or an
  out-of-budget density finding. Never fatal, **even in strict mode** for
  density (a word-count budget is a soft guideline, not a structural rule).
"""

from __future__ import annotations

import json
import re
from typing import Any, Dict, List, Optional, Tuple

from density_mode import DEFAULT_DENSITY_MODE, validate_density
from schemas import ALL_FIELD_SPECS, SLIDE_SCHEMAS, VALID_SLIDE_TYPES

# Allowed scalar python types for each declared field ``type`` string.
_TYPE_CHECKERS = {
    "string": (str,),
    "number": (int, float),
    "bool": (bool,),
    "array": (list, tuple),
    "object": dict,
}


class ValidationError(Exception):
    """Raised when a slide_data_list is structurally unrecoverable.

    Carries structured issues so the engine can surface a clear message
    instead of a cryptic traceback.
    """

    def __init__(self, issues: List["ValidationIssue"] | str):
        if isinstance(issues, str):
            issues = [ValidationIssue(reason=issues)]
        self.issues = issues
        super().__init__(self._format())

    def _format(self) -> str:
        if not self.issues:
            return "Validation failed"
        head = self.issues[0].format()
        suffix = f" (and {len(self.issues) - 1} more)" if len(self.issues) > 1 else ""
        return f"{head}{suffix}"


class ValidationIssue:
    """A single validation finding (error or warning)."""

    def __init__(
        self,
        reason: str,
        *,
        slide_index: Optional[int] = None,
        field_path: str = "",
        severity: str = "error",
    ):
        self.slide_index = slide_index
        self.field_path = field_path
        self.reason = reason
        self.severity = severity  # "error" | "warning"

    @property
    def is_error(self) -> bool:
        return self.severity == "error"

    def format(self) -> str:
        loc = "deck"
        if self.slide_index is not None:
            loc = f"slide[{self.slide_index}]"
        path = f".{self.field_path}" if self.field_path else ""
        return f"{loc}{path}: {self.reason}"

    def __repr__(self) -> str:  # pragma: no cover - debug helper
        return f"<{self.severity.upper()} {self.format()}>"


class ValidationResult:
    """Aggregated result of validating a whole deck."""

    def __init__(self) -> None:
        self.issues: List[ValidationIssue] = []

    @property
    def errors(self) -> List[ValidationIssue]:
        return [i for i in self.issues if i.is_error]

    @property
    def warnings(self) -> List[ValidationIssue]:
        return [i for i in self.issues if not i.is_error]

    @property
    def is_valid(self) -> bool:
        return not self.errors

    def add(self, issue: ValidationIssue) -> None:
        self.issues.append(issue)

    def merge(self, other: "ValidationResult") -> None:
        self.issues.extend(other.issues)

    def error_messages(self) -> List[str]:
        return [e.format() for e in self.errors]

    def warning_messages(self) -> List[str]:
        return [w.format() for w in self.warnings]

    def __repr__(self) -> str:  # pragma: no cover - debug helper
        return (
            f"<ValidationResult valid={self.is_valid} "
            f"errors={len(self.errors)} warnings={len(self.warnings)}>"
        )


# ---------------------------------------------------------------------------
# Field-level checking
# ---------------------------------------------------------------------------
def _check_type(value: Any, type_name: str) -> bool:
    checker = _TYPE_CHECKERS.get(type_name)
    if checker is None:
        return True  # unknown type constraints are not enforced here
    # NOTE: booleans are ints in Python; exclude bool from "number".
    if type_name == "number" and isinstance(value, bool):
        return False
    return isinstance(value, checker)


def _validate_field(
    value: Any,
    spec: Dict[str, Any],
    slide_index: int,
    field_path: str,
    result: ValidationResult,
) -> None:
    type_name = spec.get("type")
    if type_name and not _check_type(value, type_name):
        result.add(ValidationIssue(
            f"expected {type_name}, got {type(value).__name__}",
            slide_index=slide_index,
            field_path=field_path,
        ))
        return

    # Enum constraint
    enum_values = spec.get("enum")
    if enum_values and value not in enum_values:
        result.add(ValidationIssue(
            f"value '{value}' is not one of {list(enum_values)}",
            slide_index=slide_index,
            field_path=field_path,
        ))
        return

    # Array item validation
    if type_name == "array" and "items" in spec:
        item_spec = spec["items"]
        min_items = spec.get("min_items")
        if min_items is not None and len(value) < min_items:
            result.add(ValidationIssue(
                f"needs at least {min_items} item(s), got {len(value)}",
                slide_index=slide_index,
                field_path=field_path,
            ))
        for i, item in enumerate(value):
            _validate_field(item, item_spec, slide_index, f"{field_path}[{i}]", result)

    # Object property validation
    if type_name == "object" and isinstance(value, dict):
        for req_name in spec.get("required", []):
            if req_name not in value or value[req_name] in (None, ""):
                result.add(ValidationIssue(
                    f"missing required property '{req_name}'",
                    slide_index=slide_index,
                    field_path=f"{field_path}.{req_name}",
                ))
        for prop_name, prop_spec in spec.get("properties", {}).items():
            if prop_name in value:
                _validate_field(
                    value[prop_name], prop_spec, slide_index,
                    f"{field_path}.{prop_name}", result,
                )


def _validate_generic_fields(
    slide_data: Dict[str, Any],
    slide_index: int,
    result: "ValidationResult",
) -> None:
    """GIT-93 Phase 4 — validate a ``layout_name``-targeted slide generically.

    Used when ``slide_type`` is unknown but ``layout_name`` is present. Instead
    of the per-type schema (which doesn't exist for the unknown type), this
    validates each PRESENT field against the union catalog ``ALL_FIELD_SPECS``
    and enforces a minimal cross-field invariant set.

    Invariant downshift (documented): unknown-type slides lose the per-type
    REQUIRED guarantee in favor of recommended-warnings. ``title`` and
    ``notes`` are warned-if-absent (non-fatal). The chart pair
    (``chart_type`` → ``categories``+``series``) stays hard-error.
    """
    # Per-field validation against the union catalog.
    for field, value in slide_data.items():
        if field in ("slide_type", "layout_name"):
            continue
        spec = ALL_FIELD_SPECS.get(field)
        if spec:
            _validate_field(value, spec, slide_index, field, result)
        else:
            result.add(ValidationIssue(
                f"unknown field '{field}' for layout_name-targeted slide",
                slide_index=slide_index, field_path=field, severity="warning",
            ))
    # T4.2b: title / notes recommended (warn-if-absent) — restores parity with
    # the per-type schemas' required-field intent, kept non-fatal.
    for req_field in ("title", "notes"):
        if req_field not in slide_data or slide_data[req_field] in (None, ""):
            result.add(ValidationIssue(
                f"missing recommended field '{req_field}' for "
                f"layout_name-targeted slide",
                slide_index=slide_index, field_path=req_field, severity="warning",
            ))
    # T4.3: chart pair enforcement — hard error (a chart without data is broken).
    if slide_data.get("chart_type"):
        for req in ("categories", "series"):
            if not slide_data.get(req):
                result.add(ValidationIssue(
                    f"chart slide missing required field '{req}'",
                    slide_index=slide_index, field_path=req, severity="error",
                ))


def validate_slide(slide_data: Any, slide_index: int) -> ValidationResult:
    """Validate a single slide object against its ``slide_type`` schema."""
    result = ValidationResult()

    if not isinstance(slide_data, dict):
        result.add(ValidationIssue(
            f"slide must be a JSON object, got {type(slide_data).__name__}",
            slide_index=slide_index,
        ))
        return result

    slide_type = slide_data.get("slide_type")
    if not slide_type:
        result.add(ValidationIssue(
            "missing required field 'slide_type'",
            slide_index=slide_index,
        ))
        return result

    if not isinstance(slide_type, str):
        result.add(ValidationIssue(
            f"'slide_type' must be a string, got {type(slide_type).__name__}",
            slide_index=slide_index,
            field_path="slide_type",
        ))
        return result

    if slide_type not in SLIDE_SCHEMAS:
        # Unknown slide_type: the engine skips these gracefully, so this is a
        # warning, not a fatal error (keeps backward compatibility).
        # GIT-93 Phase 4: a layout_name-targeted slide (unknown slide_type) is
        # validated via the generic per-field path instead of being skipped.
        if slide_data.get("layout_name"):
            _validate_generic_fields(slide_data, slide_index, result)
        else:
            # Unknown slide_type: the engine skips these gracefully, so this is a
            # warning, not a fatal error (keeps backward compatibility).
            result.add(ValidationIssue(
                f"unknown slide_type '{slide_type}' — will be skipped "
                f"(valid types: {list(VALID_SLIDE_TYPES)}, or supply layout_name)",
                slide_index=slide_index,
                field_path="slide_type",
                severity="warning",
            ))
        return result

    schema = SLIDE_SCHEMAS[slide_type]

    # Required fields
    for name, spec in schema["required"].items():
        if name not in slide_data or slide_data[name] in (None, ""):
            severity = "warning" if spec.get("recommended") else "error"
            result.add(ValidationIssue(
                f"missing required field '{name}'",
                slide_index=slide_index,
                field_path=name,
                severity=severity,
            ))
        else:
            _validate_field(slide_data[name], spec, slide_index, name, result)

    # Optional fields (only validate when present)
    for name, spec in schema["optional"].items():
        if name in slide_data and slide_data[name] is not None:
            _validate_field(slide_data[name], spec, slide_index, name, result)

    return result


def validate_slide_data_list(
    data: Any,
    *,
    strict: bool = False,
    density_mode: Optional[str] = None,
) -> ValidationResult:
    """Validate an entire ``slide_data_list``.

    Parameters
    ----------
    data:
        The deck payload (expected to be a list of slide dicts).
    strict:
        When ``True``, ``notes`` warnings are also treated as fatal errors so a
        pre-flight gate can refuse to render until every slide has notes.
    density_mode:
        Optional deck-wide density mode key (``"concise"`` / ``"standard"`` /
        ``"text-heavy"``). When set, each slide's visible-text word count is
        checked against the mode's per-slide budget and out-of-budget slides
        produce **warnings** (never errors, even in strict mode — a word-count
        budget is a soft guideline the agent self-tightens, not a structural
        rule). When ``None`` (default), no density check runs.
    """
    result = ValidationResult()

    if not isinstance(data, list):
        result.add(ValidationIssue(
            f"slide_data_list must be a JSON array, got {type(data).__name__}",
        ))
        return result

    if len(data) == 0:
        result.add(ValidationIssue(
            "slide_data_list is empty — nothing to render",
            severity="warning",
        ))
        return result

    for index, slide_data in enumerate(data):
        slide_result = validate_slide(slide_data, index)
        result.merge(slide_result)

    if strict:
        # Promote recommended-field warnings (e.g. missing notes) to errors.
        # GIT-93 MINOR-4: broaden the match so the generic layout_name path
        # ("missing recommended field 'notes' for layout_name-targeted slide")
        # is also promoted — previously only the per-type "missing required
        # field 'notes'" substring matched.
        for issue in result.issues:
            if not issue.is_error and "missing" in issue.reason and "'notes'" in issue.reason:
                issue.severity = "error"

    # Density budget check (always non-fatal, even in strict mode). Runs on
    # whatever slides survived structural validation; unknown slide types and
    # non-dict entries are skipped inside ``validate_density``.
    if density_mode is not None:
        try:
            findings = validate_density(data, density_mode)
        except ValueError as exc:
            # Unknown mode key — surface as a single deck-level warning so the
            # caller gets a clear hint instead of a crash. Never fatal.
            result.add(ValidationIssue(
                str(exc),
                severity="warning",
            ))
        else:
            for finding in findings:
                direction = "over" if finding.is_over() else "under"
                result.add(ValidationIssue(
                    f"density '{finding.mode}': {finding.words} words is "
                    f"{direction} budget ({finding.budget_min}-"
                    f"{finding.budget_max} words/slide visible text)",
                    slide_index=finding.slide_index,
                    severity="warning",
                ))

    return result


# ---------------------------------------------------------------------------
# Two-layer retry support (inner: JSON repair, outer: schema validation)
# ---------------------------------------------------------------------------
def _strip_code_fence(text: str) -> str:
    """Remove a single wrapping ```json ... ``` or ``` ... ``` fence."""
    match = re.search(r"```(?:json)?\s*\n?(.*?)```", text, re.DOTALL)
    if match:
        return match.group(1).strip()
    return text.strip()


def _repair_json(text: str) -> str:
    """Best-effort repair of common LLM JSON mistakes."""
    repaired = _strip_code_fence(text)
    # Strip a leading "slide_data_list =" / variable assignment.
    repaired = re.sub(r"^[A-Za-z_][A-Za-z0-9_]*\s*=\s*", "", repaired)
    # Remove trailing commas before closing brackets/braces.
    repaired = re.sub(r",\s*([\]}])", r"\1", repaired)
    # Replace single-quoted strings with double-quoted (naive but effective
    # for keys/simple values without embedded quotes).
    repaired = re.sub(r"'([^']*)'", r'"\1"', repaired)
    return repaired


def _extract_first_json(text: str) -> Optional[str]:
    """Return the first balanced JSON array/object substring, if any."""
    repaired = _repair_json(text)
    for opener, closer in (("[", "]"), ("{", "}")):
        start = repaired.find(opener)
        if start == -1:
            continue
        depth = 0
        in_string = False
        escape = False
        for i in range(start, len(repaired)):
            ch = repaired[i]
            if in_string:
                if escape:
                    escape = False
                elif ch == "\\":
                    escape = True
                elif ch == '"':
                    in_string = False
                continue
            if ch == '"':
                in_string = True
            elif ch == opener:
                depth += 1
            elif ch == closer:
                depth -= 1
                if depth == 0:
                    return repaired[start:i + 1]
    return None


def parse_and_validate(
    raw_text: str,
    *,
    strict: bool = False,
    density_mode: Optional[str] = None,
) -> Tuple[ValidationResult, Optional[List[Dict[str, Any]]]]:
    """Two-layer entry point for LLM output.

    Inner layer: repair + parse the raw text to JSON.
    Outer layer: schema-validate the parsed deck.

    Parameters
    ----------
    raw_text:
        Raw LLM output (possibly fenced / dirty JSON).
    strict:
        Forwarded to :func:`validate_slide_data_list`.
    density_mode:
        Optional deck-wide density mode forwarded to
        :func:`validate_slide_data_list` for out-of-budget warning checks.

    Returns
    -------
    (result, data)
        ``result`` is a :class:`ValidationResult`; ``data`` is the parsed list
        when the inner layer succeeded, else ``None``. On a parse failure the
        result carries a single error whose ``reason`` explains the parse
        problem (and includes a hint the model can use to self-correct).
    """
    result = ValidationResult()

    if not isinstance(raw_text, str) or not raw_text.strip():
        result.add(ValidationIssue(
            "LLM produced empty output — no JSON to parse",
        ))
        return result, None

    candidate = _repair_json(raw_text)
    parsed: Any = None
    parse_error: Optional[str] = None
    try:
        parsed = json.loads(candidate)
    except json.JSONDecodeError as exc_outer:
        parse_error = str(exc_outer)
        # Fallback: try to locate the first balanced JSON structure.
        extracted = _extract_first_json(raw_text)
        if extracted and extracted != candidate:
            try:
                parsed = json.loads(extracted)
                parse_error = None
            except json.JSONDecodeError as exc_inner:
                parse_error = str(exc_inner)

    if parse_error is not None:
        result.add(ValidationIssue(
            f"JSON parse failed: {parse_error}. "
            "Re-emit the slide_data_list as a single valid JSON array.",
        ))
        return result, None

    # Outer layer: schema validation.
    result.merge(validate_slide_data_list(parsed, strict=strict, density_mode=density_mode))
    return result, parsed
