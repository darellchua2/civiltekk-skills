#!/usr/bin/env bats

# Skill isolation guard (#437, PLANS/PLAN-437.md).
# Enforces the AGENTS.md §Skill Isolation Contract:
#   1. no reference to the deleted shared skills/_common package remains
#   2. no skill computes a filesystem path escaping its own directory
#      (parent-chain _common resolution, ../_common hops)
#   3. cross-skill path references are banned except the declared handoffs
#      (uniform owner->targets shape; source of truth for the
#      dependency-map.json requiresSkills entries)
#   4. the three pptx vendored scripts/_common trees are pairwise
#      byte-identical (fix once, copy to all three — never edit one copy)

# Declared cross-skill dependencies. #437: the modifier extends templates,
# the slide engine fills. #597: the inline plan executor routes its delegate
# matrix to the four inline worker skills. #602: the autoresearch loop skills
# cite the core protocol host's references at runtime (multi-owner pair —
# every owner in HANDOFF3_OWNERS maps to every target in HANDOFF3_TARGETS).
# #635: the inline code-review wrapper loads the reviewer baseline + language
# checklists at runtime (declared closure, HANDOFF4).
# #650: the architecture-review-skill decision-tree reviewer loads the
# reviewer baseline at runtime (declared closure, HANDOFF5).
# #641: the inline requirements wrapper loads grilling + the specs skill at
# runtime (declared closure, HANDOFF6).
# Any other edge must be declared the same way or duplicated.
HANDOFF1_OWNER="pptx-template-modifier-skill"
HANDOFF1_TARGETS="pptx-generate-slide-skill"
HANDOFF2_OWNER="plan-execution-inline-skill"
HANDOFF2_TARGETS="testing-inline-skill linting-inline-skill civiltekk-documentation-inline-skill responsive-audit-inline-skill"
HANDOFF3_OWNERS="autoresearch-code-skill autoresearch-ml-skill autoresearch-research-skill"
HANDOFF3_TARGETS="autoresearch-core-skill"
HANDOFF4_OWNER="code-review-inline-skill"
HANDOFF4_TARGETS="reviewer-baseline-skill language-review-checklists-skill"
HANDOFF5_OWNER="architecture-review-skill"
HANDOFF5_TARGETS="reviewer-baseline-skill"
HANDOFF6_OWNER="requirements-inline-skill"
HANDOFF6_TARGETS="grilling-skill civiltekk-requirements-specs-skill"

@test "skill_isolation_no_shared_common_references" {
  # Catches both repo paths (skills/_common/...) and deploy strings
  # (.opencode/skills/_common/...). Runtime carriers: skills + agent docs +
  # top-level docs. tests/ is excluded (this file's own comments name the
  # banned string). -eq 1: grep exit 2 (error) must fail, not false-green.
  run grep -rn "skills/_common" skills/ agents/ README.md MIGRATION.md \
    --exclude-dir=__pycache__ --exclude-dir=.pytest_cache
  [ "$status" -eq 1 ]
}

@test "skill_isolation_no_parent_chain_common_escapes" {
  # Own-dir resolution is `parent / "_common"` (or parents[1]). Anything
  # reaching parents[2]+, a parent.parent.parent chain, a ../_common hop, or a
  # segmented "_"/"common" join escapes the skill dir. parents[N>=2] is banned
  # outright regardless of what follows (census: zero legit uses in skills/).
  # Known residual: variable indirection (_SKILLS / "_common" / "scripts") is
  # invisible to pattern matching — test 3 catches its cross-skill consequence.
  run python3 - <<'PYEOF'
import re, sys
from pathlib import Path

fence_re = re.compile(r"```.*?```", re.S)
tick_re = re.compile(r"```")

def carrier_spans(p, text):
    "Runtime-carrier char spans: whole .py files; fenced blocks in SKILL.md."
    if p.suffix == ".py":
        return [(0, len(text))]
    if p.name == "SKILL.md":
        spans = [f.span() for f in fence_re.finditer(text)]
        last = spans[-1][1] if spans else 0
        # GitHub renders an unclosed trailing fence to EOF — that tail is a
        # runtime carrier too, not a silent skip.
        trailing = [m.start() for m in tick_re.finditer(text, last)]
        if trailing:
            spans.append((trailing[0], len(text)))
        return spans
    return []

pat = re.compile(
    r"parents\[([2-9]|[1-9][0-9]+)\]"
    r"|parent\.parent\.parent"
    r"|\.\./_common"
    r"|['\"]_['\"]\s*/\s*['\"]common"
)
offenders = []
for p in sorted(Path("skills").rglob("*")):
    if not p.is_file():
        continue
    parts = p.parts
    if parts[1].startswith("_"):
        continue
    if any(x in ("__pycache__", ".pytest_cache") for x in parts):
        continue
    try:
        text = p.read_text(encoding="utf-8")
    except (UnicodeDecodeError, ValueError):
        continue
    spans = carrier_spans(p, text)
    for m in pat.finditer(text):
        if not any(s <= m.start() < e for s, e in spans):
            continue
        line = text.count("\n", 0, m.start()) + 1
        offenders.append(f"{p}:{line}: {m.group(0)!r}")
if offenders:
    print("Parent-chain _common escapes:")
    print("\n".join(offenders))
    sys.exit(1)
print("ok")
PYEOF
  [ "$status" -eq 0 ]
}

@test "skill_isolation_no_sibling_skill_paths_outside_declared_handoff" {
  run python3 - "$HANDOFF1_OWNER" "$HANDOFF1_TARGETS" "$HANDOFF2_OWNER" "$HANDOFF2_TARGETS" "$HANDOFF3_OWNERS" "$HANDOFF3_TARGETS" "$HANDOFF4_OWNER" "$HANDOFF4_TARGETS" "$HANDOFF5_OWNER" "$HANDOFF5_TARGETS" "$HANDOFF6_OWNER" "$HANDOFF6_TARGETS" <<'PYEOF'
import re, sys
from pathlib import Path

owner1, targets1, owner2, targets2, owners3, targets3, owner4, targets4, owner5, targets5, owner6, targets6 = sys.argv[1:13]
allowed = {
    owner1: set(targets1.split()),
    owner2: set(targets2.split()),
}
for o in owners3.split():
    allowed[o] = set(targets3.split())
allowed[owner4] = set(targets4.split())
allowed[owner5] = set(targets5.split())
allowed[owner6] = set(targets6.split())
root = Path("skills")
catalog = {d.name for d in root.iterdir()
           if d.is_dir() and not d.name.startswith("_")}

def sibling(name):
    "Resolve a referred name to a catalog dir (exact or Claude-layout +/- -skill)."
    for cand in (name, name + "-skill"):
        if cand in catalog:
            return cand
    return None

def names(own):
    out = {own}
    if own.endswith("-skill"):
        out.add(own[: -len("-skill")])
    return out

ref_re = re.compile(
    r"opencode/skills/([a-z0-9_-]+)/|(?<!\w)skills/([a-z0-9_-]+)/"
    r'|"([a-z0-9_-]+)"\s*\)?\s*/\s*"scripts"'
)
fence_re = re.compile(r"```.*?```", re.S)
tick_re = re.compile(r"```")

def carrier_spans(p, text):
    "Runtime-carrier char spans: whole .py files; fenced blocks in SKILL.md."
    if p.suffix == ".py":
        return [(0, len(text))]
    if p.name == "SKILL.md":
        # Only fenced code blocks are runtime instructions; prose/links
        # (attribution URLs, credits tables — keep those in prose above the
        # fence, never inside fence comments) are documentation.
        spans = [f.span() for f in fence_re.finditer(text)]
        last = spans[-1][1] if spans else 0
        # GitHub renders an unclosed trailing fence to EOF — carrier too.
        trailing = [m.start() for m in tick_re.finditer(text, last)]
        if trailing:
            spans.append((trailing[0], len(text)))
        return spans
    return []

violations = []
for p in sorted(root.rglob("*")):
    if not p.is_file():
        continue
    parts = p.parts
    if any(part in ("__pycache__", ".pytest_cache") for part in parts):
        continue
    try:
        text = p.read_text(encoding="utf-8")
    except (UnicodeDecodeError, ValueError):
        continue  # binary payload — not a path reference carrier
    own = parts[1]
    spans = carrier_spans(p, text)
    for m in ref_re.finditer(text):
        if not any(s <= m.start() < e for s, e in spans):
            continue
        referred = m.group(1) or m.group(2) or m.group(3)
        sib = sibling(referred)
        if sib is None:
            continue  # not a catalog sibling (e.g. target-project paths)
        if sib in names(own):
            continue  # self-reference (either layout naming)
        if sib in allowed.get(own, set()):
            continue  # a declared handoff
        line = text.count("\n", 0, m.start()) + 1
        violations.append(f"{p}:{line}: {m.group(0)!r} ({own} -> {sib})")
if violations:
    print("Sibling skill path refs outside the declared handoffs:")
    print("\n".join(violations))
    sys.exit(1)
print("ok")
PYEOF
  [ "$status" -eq 0 ]
}

@test "skill_isolation_pptx_vendored_trees_pairwise_identical" {
  # Add new vendored scripts/_common trees to this list when a skill gains one
  # (identity across DIFFERENT engines would be wrong — list them explicitly).
  for s in pptx-generate-slide-skill pptx-template-modifier-skill pptx-generate-template-skill; do
    [ -d "skills/$s/scripts/_common" ] || { fail "missing skills/$s/scripts/_common"; }
  done
  diff -r --exclude=__pycache__ --exclude=.pytest_cache \
    "skills/pptx-generate-slide-skill/scripts/_common" \
    "skills/pptx-template-modifier-skill/scripts/_common"
  diff -r --exclude=__pycache__ --exclude=.pytest_cache \
    "skills/pptx-generate-slide-skill/scripts/_common" \
    "skills/pptx-generate-template-skill/scripts/_common"
}

@test "skill_isolation_no_new_underscore_prefixed_shared_dirs" {
  # AGENTS.md §Skill Isolation Contract bans shared `_`-prefixed dirs outright
  # (the _archived legacy exception was retired with its deletion, #563).
  # Pre-assert: a missing skills/ dir would make the pipeline exit 1 on empty
  # input and false-green the test (pipes swallow the ls failure).
  [ -d skills ] || fail "skills/ directory missing"
  run bash -c "ls skills/ | grep '^_'"
  [ "$status" -ne 0 ]
}
