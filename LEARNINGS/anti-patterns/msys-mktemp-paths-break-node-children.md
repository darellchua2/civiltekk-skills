# MSYS mktemp -d paths break node children with C:\tmp ENOENT

Date: 2026-10-13
Category: anti-pattern
Confidence: High (A/B-proven: identical failure counts on untouched main)
Scope: bats/CI-style tests that sandbox HOME via mktemp and call node CLIs

## Summary

Under Git Bash (MSYS), `mktemp -d` returns a POSIX-style path (`/tmp/tmp.XXX`)
that MSYS tools resolve fine — but a node child receives it as a literal
argument and resolves it against the current drive: `C:\tmp\tmp.XXX`, which
does not exist. Every test that does `HOME=$(mktemp -d)` (or mktemps a config
file) and then runs a node CLI that reads/writes under that path fails with
`Error: ENOENT ... open 'C:\tmp\tmp.XXX\...'` — seen 2026-10-13 in
test_pack_permissions (`node -e` reading the sandboxed opencode.json),
test_deploy_delegate and the target/installer suites.

The failures look like product regressions but are pure environment:
A/B runs on the base tree reproduce identical counts. Remedy options:
convert with `cygpath -w` (or `pwd -W`) before handing the path to node, or
mktemp under a Windows-native dir (`${TMPDIR:-/tmp}` is still POSIX under
MSYS — prefer `$(cygpath -m "$TMP")`), or run the suite on Linux CI only and
treat these files as env-INCONCLUSIVE locally. Anti-pattern shape: mixing
MSYS path semantics with a child process that does not speak them.
