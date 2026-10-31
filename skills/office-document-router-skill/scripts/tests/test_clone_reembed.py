"""C1 re-embed guard test (US-4.1 architecture review).

architecture review C1: after cloning, the derived template_new.pptx must carry
embedded JSON (python-pptx's prs.save strips it otherwise). The re-embed logic
in state_machine.resolve_and_clone is guarded on ``active != template_path`` so
that when clone_for_over_limit SKIPS (no donor) and returns the BASE path, the
base template is NOT modified by a spurious re-embed. This file tests that guard.

(The positive path — re-embed of a real template_new.pptx — uses the already-
tested extract_schema/embed_schema primitives, and is only reachable when a clone
actually succeeds. The bundled template has no donor for content_slide, so a
clone cannot be triggered there; the guard test below is the stable, meaningful
coverage for this code path on the bundled template.)
"""
import shutil

from state_machine import resolve_and_clone
from schema_extractor import read_embedded_schema


def test_no_spurious_reembed_on_base_when_clone_skipped(template_path, tmp_path):
    base = shutil.copy2(template_path, tmp_path / "template.pptx")
    # content_slide has no donor on the bundled template -> clone skips -> active == base.
    deck = [
        {"slide_type": "title_slide", "title": "T"},
        {"slide_type": "content_slide", "title": "C", "body": "**A** - x"},
    ]
    before = read_embedded_schema(str(base) if isinstance(base, str) else str(base))
    active, overrides, note = resolve_and_clone(str(base), deck)
    assert active == str(base), "clone should skip (no donor) -> active is the base"
    after = read_embedded_schema(str(base))
    assert after == before, (
        "base template must NOT be modified by a spurious re-embed when cloning skipped"
    )
