# Rewiring N snippets into one helper call must carry forward every input

**Date**: 2026-10-31 · **Confidence**: High · **Scope**: any extract-to-helper refactor

## Summary

Replacing several inline snippets with a single helper call silently drops
per-call-site inputs. `setup_provider_credentials` used five `node -e`
snippets; the rewire to one `seed-provider-auth.mjs resolve` call passed
presets/maps but forgot `--provider "$PROVIDER"` — so an explicitly chosen
provider (anthropic oauth hint, openrouter env seed) resolved the derived
default instead. Every snippet removed had inputs the helper must receive;
enumerate them per call site before deleting.

**Evidence**: deploy/setup.sh `setup_provider_credentials` (the resolve call);
caught by tests/test_provider_credentials.bats (oauth + env-seed cases).

## Signal

- The helper's flag surface has fewer args than the removed snippets' total
  distinct inputs.
- Only the happy/default path was exercised after the rewire.

## Rule

Before deleting replaced snippets, list each snippet's arguments verbatim and
check the helper call carries all of them.
