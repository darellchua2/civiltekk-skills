#!/usr/bin/env bats

# Consolidated pipeline/plan command contract guard (#656; inherits the
# #613/#617 guard for the former /run-worktree-pipeline-v2 entry). The -v2
# commands were merged into their parents with INLINE as the default and
# subagent orchestration as explicit opt-in (user request + OpenCode +
# deps resolve, else inline with a note). These tests pin that shape.

SETUP_ROOT="."
PIPE_KEY="run-worktree-pipeline"
PLAN_KEY="run-plan"
PRESET="installer/presets/pack-inline-workers.json"

pipe_template() {
  node -e "const c=require('./deploy/opencode.json').commands['${PIPE_KEY}'];console.log(c.template)"
}

plan_template() {
  node -e "const c=require('./deploy/opencode.json').commands['${PLAN_KEY}'];console.log(c.template)"
}

@test "pipeline: command entry pins subagent:false" {
  run node -e "const c=require('./deploy/opencode.json').commands['${PIPE_KEY}'];process.exit(c.subagent === false ? 0 : 1)"
  [ "$status" -eq 0 ]
}

@test "pipeline: template carries the zero-subagent directive" {
  run pipe_template
  [ "$status" -eq 0 ]
  [[ "$output" == *"spawn NO subagents anywhere in the run"* ]]
}

@test "pipeline: template carries in-session checklist mechanics for steps 7/9/10" {
  run pipe_template
  [[ "$output" == *"code-review-inline-skill"* ]]
  [[ "$output" == *"requirements-inline-skill"* ]]
  [[ "$output" == *"civiltekk-pr-workflow-skill"* ]]
  [[ "$output" == *"create route"* ]]
  [[ "$output" == *"reviewer-baseline-skill"* ]]
}

@test "pipeline: template carries the explicit opt-in arm sentence" {
  run pipe_template
  [[ "$output" == *"explicit user request"* ]]
}

@test "plan: routes inline by default with subagent opt-in" {
  run plan_template
  [[ "$output" == *"plan-execution-inline-skill"* ]]
  [[ "$output" == *"plan-execution-skill"* ]]
  [[ "$output" == *"explicit user request"* ]]
}

@test "commands: both -v2 keys are gone (hard-delete, #656)" {
  run node -e "const c=require('./deploy/opencode.json').commands;process.exit(('run-worktree-pipeline-v2' in c || 'run-plan-v2' in c) ? 1 : 0)"
  [ "$status" -eq 0 ]
}

@test "pipeline: no Docker dead-letter agent paths in any command template" {
  run grep -c "app/.opencode/agents" deploy/opencode.json
  [ "$status" -eq 1 ]
  [ "$output" = "0" ]
}

@test "pipeline: preset description carries no preflight caveat" {
  run grep -c "lack the pipeline skill" "$PRESET"
  [ "$status" -eq 1 ]
  [ "$output" = "0" ]
}

@test "pipeline: every inline-workers preset skill resolves on disk" {
  run node -e "
    const fs = require('fs');
    const skills = require('./$PRESET').skills;
    const missing = skills.filter(s => !fs.existsSync('skills/' + s + '/SKILL.md'));
    if (missing.length) { console.error('missing: ' + missing.join(', ')); process.exit(1); }
  "
  [ "$status" -eq 0 ]
}

@test "pipeline: preflight is arm-aware (both executor skills named)" {
  run grep -c "plan-execution-inline-skill" skills/worktree-pipeline-skill/SKILL.md
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
  run grep -c "resolved per arm" skills/worktree-pipeline-skill/SKILL.md
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
}

@test "arm rule: sibling executors carry routing one-liners (skill-layer pins)" {
  run grep -c "explicit user request" skills/plan-execution-inline-skill/SKILL.md
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
  run grep -c "explicit user request" skills/plan-execution-skill/SKILL.md
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
}
