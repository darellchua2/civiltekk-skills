# A provisioning marker that hashes only the manifest never re-copies fixed scripts

- **Category**: anti-pattern
- **Confidence**: 0.95
- **Scope**: project
- **Date**: 2026-11-26

`plugins/laya-guard/provision.sh` keyed its `.provisioned` marker on `sha256(package.json)` alone, so a sidecar-only fix hit "already provisioned" and the old `sidecar.mjs` stayed on disk. Rule: an idempotency marker must cover every file the step copies (now `package.json` + `sidecar.mjs` + `warm.mjs`). Guard: `tests/test_laya_guard.bats` pins the hashed file list.
