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
