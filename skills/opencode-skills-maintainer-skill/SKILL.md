---
name: opencode-skills-maintainer-skill
description: Scan, validate, and audit OpenCode skills — consistency, redundancy, modularization, subagent suitability, duplication matrix, and token usage optimization
license: Apache-2.0
compatibility: opencode
metadata:
  harness: "opencode"
  protocol: autoresearch-opt-in
category: OpenCode Meta
---

## What I do

Audit the skill library: structure validation, bloat/regrowth detection, redundancy mapping, consolidation candidates, subagent-skill suitability, quantitative duplication scoring, token-cost analysis.

## When to use me

- Auditing all skills (`skills/`) for consistency
- Validating frontmatter (name/description present, valid YAML, name = directory name)
- Finding redundant skills or consolidation candidates
- Detecting content bloat or regrowth after the 2026-09 trim
- Checking which subagents can legitimately load which skills (#60)
- Scoring skill-pair overlap and hunting token waste

## Validation (one pass)

```bash
cd skills
for dir in */; do
  f="$dir/SKILL.md"; [ -f "$f" ] || { echo "missing: $dir"; continue; }
  grep -q '^name:' "$f" || echo "no name: $dir"
  grep -q '^description:' "$f" || echo "no description: $dir"
  [ "${dir%/}" = "$(grep '^name:' "$f" | head -1 | cut -d' ' -f2)" ] || echo "name/dir mismatch: $dir"
  python3 -c "import re,yaml,sys; m=re.match(r'^---\n(.*?)\n---\n', open(sys.argv[1]).read(), re.S); sys.exit('no frontmatter') if not m else yaml.safe_load(m.group(1))" "$f" 2>/dev/null || echo "bad YAML: $dir"
done
node installer/build-registry.mjs --check  # from repo root
```

## Bloat check (lean standard — from `civiltekk-opencode-creation-skill`)

A skill encodes only house-specific content; model-known textbook/vendor docs are bloat. Flag:

- Category A/B/E SKILL.md **> 300 lines** (E exempt when a `reference.md` sibling exists and SKILL.md ≤ 200)
- Category C (house workflow) SKILL.md **> 600 lines** — workflows legitimately run long; this ceiling catches regrowth, not legitimacy
- Any trimmed skill (contains a `> Removed 2026-09` marker) whose body re-adds spec re-quotation, vendor doc dumps, or example catalogs
- **Description without boundary clause** — descriptions lacking a "not for X" / "use when" decision boundary; colliding families (lint, test-gen, ticket, grill) then route unpredictably
- **Tutorial-fence density** — non-template skills with >12 code fences (template/reference skills whose fences ARE the payload are exempt)
- `wc -l skills/*/SKILL.md | sort -rn | head -20` — the standing top-20 bloat watchlist

## Redundancy & modularization

```bash
grep -h '^description:' skills/*/SKILL.md | sort | uniq -cd | sort -rn   # duplicate descriptions
```

Flag near-identical purposes/audiences across skills; compound skills containing multiple distinct capabilities; consolidation candidates with a migration path (which callers load which skill — grep the AGENTS.md chain first, external § anchors must survive any merge).

## Subagent suitability (#60)

For each skill, determine which subagent(s) may legitimately load it: required tools (bash/gh/npm/webfetch mentioned in the body), MCP needs, and whether agent `permissions:` frontmatter forbids them. A skill only a bash-allowed agent can run is `primary-only`; a primary-only skill composed into a subagent-allowed chain needs decomposition.

```bash
python3 - <<'EOF'
import glob, json, re, yaml
tiers = json.load(open('installer/agent-tiers.json'))['tiers']
for f in sorted(glob.glob('skills/*/SKILL.md')):
    body = open(f).read().lower()
    tools = sorted(set(re.findall(r'\b(bash|gh cli|npm|npx|webfetch|docker)\b', body)))
    tier_hits = sorted({t for a, t in tiers.items() if a.replace('-subagent','') in body})
    verdict = 'primary-only' if ('bash' in tools or 'gh cli' in tools) else 'subagent-safe'
    print(f"{f.split('/')[1]:45} tools={','.join(tools) or '-':20} {verdict}")
EOF
```

Report per skill: suitable tiers, tool requirements, MCP access, violation (skill assumes a tool the matching subagent's `permissions:` denies), decomposition verdict. Cross-check denials in `agents/*.md` frontmatter `permissions:` before declaring a pair compatible.

## Duplication matrix (#60)

Quantitative overlap per skill pair — Jaccard over 4+ char tokens of the full SKILL.md (description + body + section headers):

```bash
python3 - <<'EOF'
import glob, re
docs = {f.split('/')[1]: set(re.findall(r'[a-z0-9]{4,}', open(f).read().lower()))
        for f in sorted(glob.glob('skills/*/SKILL.md'))}
names = sorted(docs)
for i, a in enumerate(names):
    for b in names[i+1:]:
        j = len(docs[a] & docs[b]) / len(docs[a] | docs[b])
        if j >= 0.50: print(f"{int(j*100):3}%  {a}  ~  {b}")
EOF
```

Action thresholds: **> 70%** merge (one skill, redirect callers); **50–70%** extract the shared capability into a referenced skill both load; **< 50%** separate is acceptable. Score is a triage signal, not a verdict — always read both bodies before recommending a merge (shared section headers alone can inflate the score).

## Token cost estimation (#60)

```bash
for f in skills/*/SKILL.md; do
  c=$(wc -c < "$f"); printf "%6d chars ~%5d tok  %s\n" "$c" $((c / 4)) "$f"
done | sort -k3 -rn | head -10
```

Report the top-10 heaviest with a redundancy estimate (repeated examples, vendor-doc restatement, duplicated section content — see Bloat check). Reduction strategies, in preference order: move verbose examples to `references/` siblings; reference vendor docs instead of restating them; compose small skills instead of extending chains; delete content the model already knows.

## Citation drift audit (autoresearch protocol)

1. **Keyword-presence-without-citation**: flag any SKILL.md containing iteration-related keywords (`{"pass"`, `Iterations:`, `results.tsv`, `keep/revert`, `stuck detection`, `autoresearch`) WITHOUT a corresponding `autoresearch-skill/references/` path citation.
2. **Frontmatter-section mismatch**: `metadata.protocol: autoresearch-opt-in` MUST be present in frontmatter iff `## Iteration Protocol (opt-in)` section is present in body. Flag mismatches in either direction.
3. **Reference existence**: every cited `autoresearch-skill/references/<name>.md` path must resolve.

Report: skill path + violation type + suggested fix.

## Report format

Skills found / valid / invalid; per-issue list (missing field, bad YAML, name mismatch, bloat flag, redundancy pair); suitability table (skill → allowed tiers, violations, decomposition verdicts); duplication pairs ≥ 50% with recommended action; top-10 token watchlist with reduction actions; standing watchlist (top-20 by size).

> Removed 2026-09: the 6-step ceremony walkthrough, categorization pattern table (categories come from frontmatter `category`), example report output, common-issues restatements, verification checklist duplication. Audit rules kept verbatim.

## Iteration Protocol (opt-in)

**DO NOT execute any of the following unless `AUTORESEARCH_PROTOCOL=1` is set in your environment.** When unset, this skill behaves exactly as documented in all sections above; the Iteration Protocol block is descriptive only.

When `AUTORESEARCH_PROTOCOL=1`:

### Auto-detection
If invoked on an iterative task, prompt ONCE per session: "This looks iterative. Enable autoresearch protocol? (y/n)". Cache answer for session.

### Skill-specific patterns

**Citation-drift check** (rule): flag any SKILL.md containing iteration-related keywords (`{"pass"`, `Iterations:`, `results.tsv`, `keep/revert`, `stuck detection`) WITHOUT a corresponding `autoresearch-skill/references/` citation. Also verify `metadata.protocol: autoresearch-opt-in` frontmatter is present iff `## Iteration Protocol` section is present. **Stuck detection:** 3 consecutive audits with same finding → escalate severity. See `evaluator-contract.md` + `stuck-detection.md`.

### Citations
- `autoresearch-skill/references/evaluator-contract.md`
- `autoresearch-skill/references/stuck-detection.md`

### Imperative gating
When `AUTORESEARCH_PROTOCOL` is unset, this section is descriptive only. Default behavior is documented in all sections above.
