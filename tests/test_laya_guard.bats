#!/usr/bin/env bats
# laya-guard guards (#671) — the air-gap + fail-closed invariants, made
# mechanical. All greps are POSIX grep (CI has no ripgrep — repo learning),
# one command per test (no && chains — repo learning), no backtick-phrase
# pins inside assertions (command-substitution trigger — repo learning).

setup() {
  cd "${BATS_TEST_DIRNAME}/.." || return 1
}

@test "laya-guard: plugin file contains no external endpoints (air-gap)" {
  ! grep -Eq 'https?://' plugins/opencode-laya-guard.ts
}

@test "laya-guard: missing answers fail closed to p=1" {
  grep -q '?? 1' plugins/opencode-laya-guard.ts
}

@test "laya-guard: shipped config defaults to shadow mode" {
  grep -q '"mode": "shadow"' plugins/laya-guard/laya-guard.config.json
}

@test "laya-guard: shipped config exists" {
  [ -f plugins/laya-guard/laya-guard.config.json ]
}

@test "laya-guard: plugin never reads process.env (no env-value surface)" {
  ! grep -q 'process\.env' plugins/opencode-laya-guard.ts
}

@test "laya-guard: sidecar never reads files (state arrives over stdio only)" {
  ! grep -q 'readFileSync' plugins/laya-guard/sidecar.mjs
}

@test "laya-guard: hard deny for git push --force ships in the deployed config" {
  grep -q 'git push --force' deploy/opencode.json
}

@test "laya-guard: enforce is not the shipped default" {
  ! grep -q '"mode": "enforce"' plugins/laya-guard/laya-guard.config.json
}

# ── v2 wiring, rule-based edits, fetched-page check, log summary ──

@test "laya-guard: shipped config gates the v2 shell action" {
  grep -q '"shell"' plugins/laya-guard/laya-guard.config.json
}

@test "laya-guard: a score never blocks by default (deny ships null)" {
  grep -q '"deny": null' plugins/laya-guard/laya-guard.config.json
}

@test "laya-guard: shipped config drops the v1 bash action name" {
  ! grep -q '"bash"' plugins/laya-guard/laya-guard.config.json
}

@test "laya-guard: plugin gates the v2 shell action in its code defaults" {
  grep -q 'const SHELL_ACTIONS = \["shell"\]' plugins/opencode-laya-guard.ts
}

@test "laya-guard: gate behaviour — shadow, enforce, path rules, fail-closed" {
  [ "$(node -p 'Number(process.versions.node.split(".")[0])')" -ge 23 ] || skip "needs Node >= 23 (TypeScript type stripping) to run the plugin tests"
  node --test tests/test_laya_guard_gate.test.ts
}

@test "laya-guard: summary script parses" {
  node --check plugins/laya-guard/summary.mjs
}

@test "laya-guard: summary reads a log file and reports the verdict mix" {
  local d
  d="$(mktemp -d)"
  printf '%s\n' '{"ts":1790000000000,"kind":"shell","action":"shell","target":"git push --force origin x","questions":{"permanent":0.91},"would_be":"deny","mode":"shadow"}' '{"ts":1790000001000,"kind":"shell","action":"shell","target":"git status","questions":{"permanent":0.10},"would_be":"pass","mode":"shadow"}' > "$d/shadow.jsonl"
  run node plugins/laya-guard/summary.mjs "$d/shadow.jsonl"
  [ "$status" -eq 0 ]
  grep -q 'pass 50.0%' <<<"$output"
  grep -q 'deny 50.0%' <<<"$output"
  rm -rf "$d"
}

@test "laya-guard: summary resolves a project dir to its log" {
  local d
  d="$(mktemp -d)"
  mkdir -p "$d/.opencode"
  printf '%s\n' '{"ts":1790000000000,"kind":"path","action":"edit","target":"AGENTS.md","questions":{},"would_be":"ask","mode":"shadow","rule":"(^|/)AGENTS"}' > "$d/.opencode/laya-guard-shadow.jsonl"
  run node plugins/laya-guard/summary.mjs "$d"
  [ "$status" -eq 0 ]
  grep -q '^path: 1 lines' <<<"$output"
  rm -rf "$d"
}

# ── provisioning moved to plugins/laya-guard/provision.sh (#677) ──

@test "laya-guard: provision.sh exists and parses" {
  bash -n plugins/laya-guard/provision.sh
}

@test "laya-guard: setup.sh no longer owns provisioning" {
  ! grep -q 'provision_laya_guard' deploy/setup.sh
}

@test "laya-guard: deploy_plugins runs provision hooks generically" {
  grep -q 'provision.sh' deploy/setup.sh
}

@test "laya-guard: provision marker covers sidecar.mjs, so a sidecar-only fix re-provisions" {
  grep -q 'cat "$src_dir/package.json" "$src_dir/sidecar.mjs"' plugins/laya-guard/provision.sh
}

@test "laya-guard: sidecar caps the model thread pool" {
  grep -q 'intraOpNumThreads: Math.min(6, availableParallelism())' plugins/laya-guard/sidecar.mjs
}

@test "laya-guard: provision hook dry-run creates nothing" {
  local d
  d="$(mktemp -d)"
  HOME="$d" DRY_RUN=true AUTO_ACCEPT=true bash plugins/laya-guard/provision.sh >/dev/null 2>&1
  [ ! -d "$d/.cache/laya-guard" ]
  rm -rf "$d"
}

@test "laya-guard: LAYA_GUARD_SKIP=1 escapes before any work" {
  local d
  d="$(mktemp -d)"
  HOME="$d" LAYA_GUARD_SKIP=1 AUTO_ACCEPT=true bash plugins/laya-guard/provision.sh >/dev/null 2>&1
  [ ! -d "$d/.cache/laya-guard" ]
  rm -rf "$d"
}

@test "laya-guard: provision.sh never reads env values into the plugin (no process.env)" {
  ! grep -q 'process\.env' plugins/laya-guard/provision.sh
}
