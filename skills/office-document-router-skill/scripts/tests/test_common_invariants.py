"""C1 invariant guard for the vendored _common package (PLAN-GIT-72 GAP-1,
re-scoped per skill by #437).

The architecture-review C1 invariant requires that NO module under this
skill's vendored ``scripts/_common/`` imports back into ``ppt_builder`` — the
dependency arrow is strictly ``ppt_builder -> layout_contract`` (and the other
``_common`` modules), never the reverse. Without this test the invariant relied
on a manual grep; this makes it self-policing.

The scan matches only actual import statements (``from ppt_builder`` /
``import ppt_builder`` with word boundaries), so narrative mentions in
docstrings (e.g. "Extracted from ``ppt_builder.py``") do not false-positive.
"""
import re
from pathlib import Path

import layout_contract

_IMPORT_RE = re.compile(r"\b(?:from\s+ppt_builder|import\s+ppt_builder)\b")


def test_common_does_not_import_ppt_builder():
    common_dir = Path(layout_contract.__file__).resolve().parent
    offenders = []
    for py in sorted(common_dir.glob("*.py")):
        for line_no, line in enumerate(py.read_text(encoding="utf-8").splitlines(), 1):
            if _IMPORT_RE.search(line):
                offenders.append(f"{py.name}:{line_no}: {line.strip()}")
    assert not offenders, (
        "C1 invariant (PLAN-GIT-72) violated: _common/scripts must not import "
        f"ppt_builder (dependency direction is ppt_builder -> _common).\nOffenders:\n"
        + "\n".join(offenders)
    )
