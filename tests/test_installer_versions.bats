#!/usr/bin/env bats

# Installer versioning contract (#667): latest-tag default install,
# --ref pinning, .skill-source.json provenance sidecar, manifest ref,
# `list installed` rows, sidecar-transparent hashing.

setup() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    TEST_HOME="$(mktemp -d)"
}

teardown() {
    [ -n "${TEST_HOME:-}" ] && rm -rf "$TEST_HOME"
}

inst() {
    HOME="$TEST_HOME" node "${PROJECT_ROOT}/installer/init.mjs" "$@"
}

tag_probe_ok() {
    git ls-remote --tags https://github.com/darellchua2/civiltekk-skills.git > /dev/null 2>&1
}

@test "parseTagLines: highest semver wins, peeled refs and non-semver ignored" {
    run node --input-type=module -e "
import { parseTagLines } from '${PROJECT_ROOT}/installer/init.mjs';
const out = ['abc123\trefs/tags/v1.2.3', 'abc124\trefs/tags/v10.0.0', 'abc124\trefs/tags/v10.0.0^{}', 'abc125\trefs/tags/v2.0.0', 'abc126\trefs/heads/main', 'abc127\trefs/tags/release-9'].join('\n');
const empty = parseTagLines('abc123\trefs/heads/main\n');
console.log(parseTagLines(out) + ' ' + empty);"
    [ "$output" = "v10.0.0 null" ]
}

@test "add --source . stamps .skill-source.json + manifest ref" {
    local ver
    ver="$(cat "${PROJECT_ROOT}/VERSION")"
    run inst add code-principles-skill --source . --target opencode --yes --no-deps
    [ "$status" -eq 0 ]
    local sc="${TEST_HOME}/.config/opencode/skills/code-principles-skill/.skill-source.json"
    [ -f "$sc" ]
    run node -e "
const m = JSON.parse(require('fs').readFileSync('${sc}', 'utf8'));
console.log([m.source.startsWith('github:'), m.ref === 'v${ver}', m.version === '${ver}', !!m.installedAt, Array.isArray(m.files) && m.files.includes('SKILL.md')].join(' '));"
    [ "$output" = "true true true true true" ]
    run node -e "
const m = JSON.parse(require('fs').readFileSync('${TEST_HOME}/.config/opencode/.skill-manifest.json', 'utf8'));
const e = m.entries['code-principles-skill'];
console.log(e.ref === 'v${ver}' && e.version === '${ver}');"
    [ "$output" = "true" ]
}

@test "sidecar is hash-transparent: update reports unchanged after add" {
    inst add code-principles-skill --source . --target opencode --yes --no-deps > /dev/null
    run inst update
    [ "$status" -eq 0 ]
    [[ "$output" != *"updated: code-principles-skill"* ]]
}

@test "list installed prints installed-vs-latest rows" {
    inst add code-principles-skill --source . --target opencode --yes --no-deps > /dev/null
    run inst list installed
    [ "$status" -eq 0 ]
    run node -e "
const rows = JSON.parse(require('child_process').execSync(
    'HOME=${TEST_HOME} node ${PROJECT_ROOT}/installer/init.mjs list installed 2>/dev/null').toString());
const r = rows.find((x) => x.name === 'code-principles-skill');
console.log(r && r.installedRef && typeof r.updateAvailable === 'boolean' ? 'row-ok' : 'row-missing');"
    [ "$output" = "row-ok" ]
}

@test "--ref <older-tag> pins the installed ref exactly" {
    tag_probe_ok || skip "network unreachable — ls-remote probe failed"
    run inst add ticketing-skill --ref v12.18.0 --target opencode --yes --no-deps
    [ "$status" -eq 0 ]
    local sc="${TEST_HOME}/.config/opencode/skills/ticketing-skill/.skill-source.json"
    [ -f "$sc" ]
    run node -e "
const m = JSON.parse(require('fs').readFileSync('${sc}', 'utf8'));
console.log(m.ref === 'v12.18.0' && m.version === '12.18.0');"
    [ "$output" = "true" ]
}
