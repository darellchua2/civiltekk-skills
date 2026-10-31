# Rename sweeps must skip deployed-artifact filenames

**Date**: 2026-10-31 · **Confidence**: High · **Scope**: CLI renames, branding sweeps

## Summary

The opencode-init → civiltekk-init sweep renamed ALL occurrences in
installer/init.mjs — including the manifest FILENAME it writes
(`.opencode-init.manifest.json` → `.civiltekk-init.manifest.json`). That name
is a deployed-artifact contract: existing installs carry the old file, five
tests pin it, and `update`/`prune` must keep reading it. A branding sweep is
for identifiers and prose, never for data filenames, config keys, or paths
users already have on disk. Inverse of
`directory-scoped-rename-sweep-misses-root-docs` (that one under-sweeps; this
one over-sweeps).

**Evidence**: installer/init.mjs:558/858 (reverted in #677); tests/init.bats,
tests/test_ships_plugins.bats.

## Rule

Grep the symbol list before a sweep and whitelist: manifest filenames, config
paths, state-file names, DB rows — anything persisted outside the repo.
