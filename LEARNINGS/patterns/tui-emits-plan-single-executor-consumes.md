# TUI-only-decides: interactive UIs emit a plan file, one executor runs it

**Date**: 2026-10-31 · **Confidence**: High · **Scope**: installers, wizards, guided flows

## Summary

The #677 install wizard renders mode/provider/packs/profile pickers and a
review screen, then emits `install-plan.json` (`civiltekk-install-plan/1`);
`setup.sh --from-plan` maps it onto the same flags the CLI uses inside
`build_plan`, where the existing validation gates apply unchanged. Execution
logic exists exactly once, so TUI and CLI cannot drift — the equivalence is
test-pinned (`test_install_wizard.bats`: plan-derived build_plan ≡ explicit
flags, byte-identical step count). Applied the same consume-once pattern the
`--select` deploy plan already used (#473).

**Evidence**: deploy/tui.mjs `flowInstallWizard`/`emitPlan`; deploy/setup.sh
`apply_install_plan` (applied inside `build_plan`, before validation).

## Rule

Never let an interactive front end execute; emit a declarative plan and feed
it through the one executor behind the same gates.
