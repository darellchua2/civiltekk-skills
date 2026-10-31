#!/usr/bin/env python3
"""
init_research.py — autoresearch project scaffolder.

Creates the canonical autoresearch project layout in an output directory:
  - research.md          (Goal / Scope / Metric / Verify / Guard / Iterations)
  - research_log.md      (append-only human log; seeded with header)
  - <skill>-results.tsv  (8-column machine-parseable audit trail)
  - final_report.md      (template, filled in at loop end)

Adapted from uditgoenka/autoresearch (MIT) — see THIRD_PARTY_LICENSES.md.

Usage:
    python3 init_research.py \\
        --goal "reduce val_bpb" \\
        --metric val_bpb \\
        --direction minimize \\
        --target 0.85 \\
        --evaluator "./eval_bpb.sh" \\
        --output ./my-experiment
"""
import argparse
import os
import sys
from datetime import datetime


TSV_HEADER_TEMPLATE = (
    "# metric_direction: {direction}\n"
    "# metric: {metric}\n"
    "# target: {target}\n"
    "# evaluator: {evaluator}\n"
    "# created: {timestamp}\n"
    "iteration\tcommit\tmetric\tdelta\tstatus\tdescription\ttimestamp\tevaluator_output\n"
)


RESEARCH_MD_TEMPLATE = """# Autoresearch Run: {goal}

**Created:** {timestamp}

## Goal
{goal}

## Scope
{scope}

## Metric
- **Name:** {metric}
- **Direction:** {direction}
- **Target:** {target}

## Verify (evaluator)
```
{evaluator}
```
The evaluator must emit `{{"pass":bool,"score":N}}` on its last stdout line.

## Guard (optional)
{guard}

## Iterations
{iterations}

## Protocol references
- `references/evaluator-contract.md`
- `references/stuck-detection.md`
- `references/iteration-safety.md`
- `references/audit-trail.md`
- `references/crash-recovery.md`
"""


RESEARCH_LOG_HEADER = """# Autoresearch Log: {goal}

Append-only per-iteration human log. One section per iteration.

"""


FINAL_REPORT_TEMPLATE = """# Final Report: {goal}

**Run completed:** (fill in at loop end)

## Summary
- Total iterations: __
- Kept: __ / Discarded: __ / Crashed: __
- Starting metric: __ → Final metric: __
- Improvement: __%

## Best iteration
- Commit: __
- Metric: __
- Description: __

## Top 3 most effective changes
1. __
2. __
3. __

## Recommendations for next run
-

## Full audit trail
See `{tsv_name}`.
"""


def parse_args(argv=None):
    p = argparse.ArgumentParser(
        description="Scaffold an autoresearch project directory."
    )
    p.add_argument("--goal", required=True, help="What to improve (free text).")
    p.add_argument("--metric", required=True,
                   help="Metric name (e.g. val_bpb, coverage_pct, bundle_kb).")
    p.add_argument("--direction", default="minimize",
                   choices=("minimize", "maximize",
                            "lower_is_better", "higher_is_better"),
                   help="Optimization direction (default: minimize).")
    p.add_argument("--target", default="",
                   help="Optional numeric target (e.g. 0.85, 80.0).")
    p.add_argument("--evaluator", default="./evaluator.sh",
                   help="Evaluator command emitting "
                        '{"pass":bool,"score":N} on last line.')
    p.add_argument("--guard", default="",
                   help="Optional guard command "
                        "(exit 0/nonzero, e.g. 'npm test').")
    p.add_argument("--scope", default=".",
                   help="File glob(s) in scope (default: current dir).")
    p.add_argument("--iterations", type=int, default=25,
                   help="Max iterations (default: 25). "
                        "Use 0 to mean unlimited.")
    p.add_argument("--skill", default="autoresearch",
                   help="Skill slug used to name the TSV "
                        "(default: autoresearch -> autoresearch-results.tsv).")
    p.add_argument("--output", required=True,
                   help="Output directory (created if missing).")
    return p.parse_args(argv)


def normalize_direction(direction: str) -> str:
    if direction in ("minimize", "lower_is_better"):
        return "lower_is_better"
    if direction in ("maximize", "higher_is_better"):
        return "higher_is_better"
    return direction


def main(argv=None) -> int:
    args = parse_args(argv)
    out_dir = os.path.abspath(args.output)
    os.makedirs(out_dir, exist_ok=True)

    timestamp = datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%S")
    direction = normalize_direction(args.direction)
    tsv_name = "{skill}-results.tsv".format(skill=args.skill)
    tsv_path = os.path.join(out_dir, tsv_name)
    iterations_label = (
        "unlimited" if args.iterations == 0
        else "{n} (bounded)".format(n=args.iterations)
    )

    with open(os.path.join(out_dir, "research.md"), "w") as f:
        f.write(RESEARCH_MD_TEMPLATE.format(
            goal=args.goal,
            scope=args.scope,
            metric=args.metric,
            direction=direction,
            target=args.target or "(unset)",
            evaluator=args.evaluator,
            guard=args.guard or "(none)",
            iterations=iterations_label,
            timestamp=timestamp,
        ))

    with open(os.path.join(out_dir, "research_log.md"), "w") as f:
        f.write(RESEARCH_LOG_HEADER.format(goal=args.goal))

    with open(tsv_path, "w") as f:
        f.write(TSV_HEADER_TEMPLATE.format(
            direction=direction,
            metric=args.metric,
            target=args.target or "none",
            evaluator=args.evaluator,
            timestamp=timestamp,
        ))

    with open(os.path.join(out_dir, "final_report.md"), "w") as f:
        f.write(FINAL_REPORT_TEMPLATE.format(goal=args.goal, tsv_name=tsv_name))

    sys.stdout.write(
        "Initialized autoresearch project in {dir}\n"
        "  research.md:        {p}\n"
        "  research_log.md:    {p2}\n"
        "  {tsv}: {p3}\n"
        "  final_report.md:    {p4}\n"
        .format(
            dir=out_dir,
            p=os.path.join(out_dir, "research.md"),
            p2=os.path.join(out_dir, "research_log.md"),
            tsv=tsv_name,
            p3=tsv_path,
            p4=os.path.join(out_dir, "final_report.md"),
        )
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
