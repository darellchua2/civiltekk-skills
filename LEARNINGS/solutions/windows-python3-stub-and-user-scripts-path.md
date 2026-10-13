# Windows python3: command-exists is not a works-probe; --user scripts land off PATH

Date: 2026-10-13
Category: solution
Confidence: High (verified live on Win11 26300 + Python 3.12.10)
Scope: any bash installer that pip-installs console scripts on Windows

## Summary

Two independent Windows traps break `python3`-based installers that pass a
naive `command_exists python3` check:

1. **The Store stub.** `python3` on PATH can be the Microsoft Store app-execution
   alias: it exists (so `command -v` succeeds) but any real invocation prints
   "Python was not found" and exits 49/9009, while the REAL interpreter sits
   one name over as `python`/`py`. `command_exists python3` therefore reports
   a working Python that cannot run pip.
2. **The scripts dir.** `pip install --user` on Windows puts console scripts in
   `%APPDATA%\Python\PythonXY\Scripts` (query it portably via
   `python -m site --user-base` + `/Scripts`), which is NOT on PATH by
   default. The Unix habit of checking `~/.local/bin` warns about the wrong
   directory. Until that dir is on PATH (and the host process restarted),
   spawned servers using bare script names (`markitdown-mcp`) fail to start
   even though the pip install succeeded.

Fix pattern (deploy/setup.sh #673): probe candidates `python3 → python → py`
with a functional check —
`$cand -c 'import sys; sys.exit(0 if sys.version_info >= (3,8) else 1)'` —
accepting the first that executes; keep a `py -3` two-word form (expand
UNQUOTED at call sites); then warn with the exact scripts dir, never mutate
PATH (setx truncates >1024 chars).
