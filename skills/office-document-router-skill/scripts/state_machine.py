"""``template_new.pptx`` resolution lifecycle — DESIGN §5 (issue #46).

Plans whether the base template can satisfy a generation request, or whether a
derived ``template_new.pptx`` (with cloned layouts) is needed. The clone itself
is P4 (#47); this phase runs everything around it and is independently
testable:

  ① delete a leftover ``template_new.pptx`` (force freshness each request)
  ② introspect the base ``template.pptx`` (mtime-cached via P0)
  ③ scan the requested ``slide_data_list``; flag any slide whose layout is
    missing or whose content is over-limit
  ⑤ produce the MANDATORY user notification whenever ``template_new.pptx``
    would be used

The plan tells P4 what to clone; P4 performs the clone, swaps the active
template, and emits the notification.
"""
from __future__ import annotations

import logging
import os
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Dict, List, Optional

# Per-skill vendored engine (#437): shared contract layer in scripts/_common.
_COMMON_SCRIPTS = Path(__file__).resolve().parent / "_common"
if str(_COMMON_SCRIPTS) not in sys.path:
    sys.path.insert(0, str(_COMMON_SCRIPTS))

from layout_contract import get_render_contract  # noqa: E402  (US-4.1: prefer embedded JSON)
from constraint_checker import Verdict, evaluate_slide  # noqa: E402 (same package dir)

logger = logging.getLogger(__name__)


def template_new_path_for(template_path: str) -> Path:
    """The derived ephemeral file: ``<stem>_new.pptx`` beside the base."""
    p = Path(template_path)
    return p.with_name(p.stem + "_new" + p.suffix)


@dataclass
class SlideRequirement:
    """A slide the base template cannot satisfy."""

    page: int
    slide_type: str
    verdict: Verdict


@dataclass
class ResolutionPlan:
    """Outcome of planning one generation request."""

    base_template: str
    needs_cloning: bool
    over_limit_slides: List[SlideRequirement] = field(default_factory=list)
    active_template: str = ""
    notification: Optional[str] = None


def delete_leftover(template_path: str) -> bool:
    """State machine ①: delete a pre-existing ``template_new.pptx``.

    Returns ``True`` if a leftover was discarded. The base is re-evaluated every
    request so it always stays authoritative.
    """
    new_path = template_new_path_for(template_path)
    if new_path.exists():
        try:
            new_path.unlink()
            logger.info("Discarded leftover derived template: %s", new_path.name)
            return True
        except OSError as exc:  # pragma: no cover - defensive
            logger.warning("Could not delete leftover %s: %s", new_path, exc)
    return False


def build_notification(over_limit: List[SlideRequirement]) -> str:
    """State machine ⑤: mandatory notice when ``template_new.pptx`` is used."""
    lines = ["Rendered from template_new.pptx because template.pptx could not fit:"]
    for req in over_limit:
        lines.append(f"  - Page {req.page} ({req.slide_type}): {req.verdict.reason}")
    lines.append(
        "A derived template_new.pptx with an extended layout was produced. "
        "Review it before sharing."
    )
    return "\n".join(lines)


def plan_resolution(
    template_path: str,
    slide_data_list: List[Dict[str, Any]],
    words_per_in2: float = None,
    clone_on: str = "missing",
) -> ResolutionPlan:
    """Run the lifecycle (cloning deferred to P4): ①→②→③→plan+notification.

    ``clone_on`` policy (issue #47 / option A):
      * ``"missing"`` (default) — only flag slides whose layout is genuinely
        missing/unknown for cloning; over-limit content is logged as a warning
        (it is handled by density downshift, not cloning).
      * ``"any"`` — flag every non-fitting slide (over-limit included) — the
        original full Capability B behaviour.
    """
    delete_leftover(template_path)  # ①
    contract = get_render_contract(template_path)  # ② (US-4.1: embedded-preferred)

    kwargs = {}
    if words_per_in2 is not None:
        kwargs["words_per_in2"] = words_per_in2

    clone_causes = {"missing", "unknown"} if clone_on == "missing" else {
        "missing", "unknown", "over_limit",
    }
    over_limit: List[SlideRequirement] = []  # slides flagged for cloning
    for page, slide_data in enumerate(slide_data_list, start=1):
        slide_type = slide_data.get("slide_type", "")
        verdict = evaluate_slide(slide_type, slide_data, contract, **kwargs)
        if verdict.cause in clone_causes:
            over_limit.append(
                SlideRequirement(page=page, slide_type=slide_type, verdict=verdict)
            )
        elif not verdict.fits:
            # Over-limit under the "missing" policy: visible warning, no clone.
            logger.warning(
                "Page %d (%s): %s — downshift density to fit", page, slide_type, verdict.reason
            )

    needs_cloning = bool(over_limit)
    notification = build_notification(over_limit) if needs_cloning else None
    return ResolutionPlan(
        base_template=template_path,
        needs_cloning=needs_cloning,
        over_limit_slides=over_limit,
        active_template=template_path,  # P4 swaps this to template_new after cloning
        notification=notification,
    )


def resolve_and_clone(
    template_path: str,
    slide_data_list: List[Dict[str, Any]],
    words_per_in2: float = None,
    clone_on: str = "missing",
    donor_template_path: Optional[str] = None,
) -> tuple:
    """Full Capability B loop (issue #47 wiring): plan → clone → hand off.

    Returns ``(active_template, config_overrides, notification)``:
    * ``active_template`` — ``template_new.pptx`` if a clone was produced, else
      the base path (including when cloning failed — safe fallback).
    * ``config_overrides`` — ``{slide_type: clone_layout_name}`` so Capability A
      renders the cloned slides against the extended layout (empty otherwise).
    * ``notification`` — the mandatory user notice, or ``None``.

    ``clone_on`` (default ``"missing"``): only clone when a slide_type's layout
    is genuinely missing; over-limit content is handled by density downshift
    (option A). Pass ``"any"`` to also clone for over-limit content.

    BT-142 Phase 3.2: ``donor_template_path`` (optional, default ``None``)
    replaces the legacy bundled ``template/default.pptx``. When layouts need
    borrowing, the caller MUST supply a donor PPTX path; if absent, Level 1
    borrow is skipped with a warning (the deck still renders with available
    layouts). Callers can synthesize a minimal donor via
    ``master_repairer._build_minimal_pptx_bytes(None)`` written to a temp file.

    Usage (agent workflow):
        active, overrides, note = resolve_and_clone(base, slides)
        generate_ppt_from_data(slides, template_path=active, config_overrides=overrides)
        if note: <show note to user>
    """
    plan = plan_resolution(
        template_path, slide_data_list, words_per_in2=words_per_in2, clone_on=clone_on
    )
    if not plan.needs_cloning:
        return template_path, {}, None

    contract = get_render_contract(template_path)

    # US-4.8 (CRIT-4): Level 0 (same-file donor clone) + Level 1 (borrow from
    # default.pptx). The dispatch lives HERE in state_machine (not in
    # layout_creator) to avoid the master_cloner ↔ layout_creator circular import.
    from layout_contract import _resolve_layout_by_fingerprint  # already on sys.path

    # Partition: which slide_types have a donor in the user's template (Level 0)
    # vs which are genuinely missing and need borrowing from default (Level 1).
    level0_slide_types = set()
    level1_slide_types = set()
    for req in plan.over_limit_slides:
        idx, _ = _resolve_layout_by_fingerprint(req.slide_type, contract)
        if idx is not None:
            level0_slide_types.add(req.slide_type)
        else:
            level1_slide_types.add(req.slide_type)

    active = template_path
    overrides: Dict[str, str] = {}

    # --- Level 0: clone from same-file donor (existing capability) ---
    if level0_slide_types:
        try:
            from layout_creator import clone_for_over_limit  # lazy: avoid circular import
            active, overrides = clone_for_over_limit(template_path, plan, contract)
        except Exception as exc:  # clone failed → safe fallback to the base template
            logger.warning(
                "Layout cloning failed (%s); rendering against the base template", exc
            )
            active = template_path
            overrides = {}

    # --- Level 1: borrow from a donor template (US-4.8 NEW, BT-142 Phase 3.2) ---
    # BT-142 Phase 3.2: there is no longer a bundled ``template/default.pptx``.
    # When layouts are missing, the caller MUST supply a donor template path
    # via the new ``donor_template_path`` parameter. If absent, Level 1 borrow
    # is skipped with a clear warning — the deck will still render (with the
    # base template's available layouts) but missing slide types degrade.
    if level1_slide_types and active and donor_template_path:
        # If template_path IS the donor, borrowing is meaningless.
        if os.path.normcase(os.path.abspath(template_path)) != os.path.normcase(os.path.abspath(donor_template_path)):
            try:
                from master_cloner import clone_master_and_borrow  # CRIT-4: lazy import
                extended, l1_overrides = clone_master_and_borrow(
                    active,
                    list(level1_slide_types),
                    donor_template_path,
                )
                if l1_overrides:
                    active = extended
                    overrides.update(l1_overrides)
                    logger.info(
                        "Level 1 borrow: %d layout(s) from donor %s",
                        len(l1_overrides), donor_template_path,
                    )
            except Exception as exc:
                logger.warning(
                    "Level 1 borrow failed (%s); continuing with Level 0 only", exc
                )
    elif level1_slide_types and active and not donor_template_path:
        logger.warning(
            "Level 1 borrow skipped: %d missing slide_type(s) cannot be cloned "
            "because no donor_template_path was provided. Provide a donor PPTX "
            "to enable layout borrowing. Missing types: %s",
            len(level1_slide_types), sorted(level1_slide_types),
        )
    # C1 (architecture review): python-pptx's prs.save() inside the clone strips
    # the unmodeled ppt/template_schema.json part from template_new.pptx. Re-embed
    # so the derived file carries a schema describing the CLONED layout — otherwise
    # the extend workflow silently falls back to the sidecar (two-track). Non-fatal.
    # Guard on a normalized path comparison: clone_for_over_limit returns the
    # BASE path (not template_new) when it skips cloning (no donor), and we must
    # NOT write embedded JSON into the user's base template. normcase/abspath
    # makes the comparison robust to slash direction / drive-letter case (Windows).
    if os.path.normcase(os.path.abspath(active)) != os.path.normcase(os.path.abspath(template_path)):
        try:
            from schema_extractor import extract_schema, embed_schema
            embed_schema(active, extract_schema(active), active)
            logger.info("Re-embedded schema into cloned template %s", active)
        except Exception as exc:  # pragma: no cover - non-fatal; sidecar fallback still works
            logger.warning(
                "Re-embed of cloned template failed (%s); sidecar fallback may apply", exc
            )
    return active, overrides, plan.notification
