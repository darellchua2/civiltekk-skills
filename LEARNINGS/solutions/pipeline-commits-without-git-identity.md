# No git identity on the machine: pass the author per command and gate the push on the commit

- **Category**: solutions
- **Confidence**: 0.9
- **Scope**: project
- **Date**: 2026-11-27
- **Summary**: With no `user.name` or `user.email` in any git config scope every commit fails with "Author identity unknown", and an ungated `commit; push` chain pushes an empty branch. Pass `-c user.name=… -c user.email=…` per command (the gh account's noreply pair) and never push after a failed commit.

## Problem

This machine has no `user.name` or `user.email` in any git config scope (`git config --show-origin --get-regexp '^user\.'` prints nothing). `git commit` fails with "Author identity unknown". A `git commit …` followed by an unconditional `git push -u origin feat/<N>` in the same chain then pushed the branch anyway: `feat/705` went up pointing at `origin/dev` with no commits on it.

## Solution

- Pass the author per command and never write global config unasked: `git -c user.name="<GitHub profile name>" -c user.email="<id>+<login>@users.noreply.github.com" commit …`. Take both values from the authenticated account (`gh api user` gives `id`, `login`, `name`). The noreply address is the one GitHub puts on the account's merged commits, so history stays consistent.
- Chain with `&&`, or exit on a failed commit before any push.
- An empty remote branch is harmless but misleading: the next successful push moves it. Say so when it happens.

## Evidence

Pipeline run for #705: the first PLAN commit failed and the push created an empty `feat/705`; the re-run with the per-command author committed `464b8184`.
