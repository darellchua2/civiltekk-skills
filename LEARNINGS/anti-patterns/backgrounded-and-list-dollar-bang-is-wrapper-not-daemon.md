# `$!` after a backgrounded `a && b &` is the wrapper shell, not the daemon

- **Category**: anti-pattern
- **Confidence**: 0.85
- **Scope**: project
- **Date**: 2026-11-26
- **Ticket**: #703 (Step 5 sandbox verification)

## Symptom

`( cd X && env ... nohup opencode serve ... & echo $! > pid )` recorded the PID of the wrapper subshell. `kill "$pid"` followed by `kill -0 "$pid"` then reported "stopped" while all four servers kept listening for the rest of the session. They were found by listing the ports.

## Rule

Take the PID from whoever owns the listener (`ss -ltnp` on the port) and judge teardown by the port no longer listening. `kill -0` on `$!` of a compound backgrounded command proves nothing.
