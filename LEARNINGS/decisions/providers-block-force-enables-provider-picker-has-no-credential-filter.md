# A model override under `providers` switches that provider on for every user

- **Category**: decision
- **Confidence**: 0.9
- **Scope**: project
- **Date**: 2026-11-26
- **Ticket**: #703

## Decision

`deploy/opencode.json` carries `providers.openai.models["gpt-6.2-astra"].limit` (context, input, output) so ChatGPT sign-ins stop capping Astra at 272,000 input tokens. The owner accepted the side effect: naming `openai` under `providers` lists the OpenAI catalog for every deployment, with or without credentials.

## Why

- Naming a provider under `providers` sets `activation: "enabled"` (opencode v2.4.1, `packages/core/src/config/plugin/provider.ts:195`), and an enabled provider is available without a connection (`packages/core/src/provider.ts:483`).
- The TUI picker lists the model API with no credential filter (`packages/tui/src/component/dialog-model.tsx:124-141`). Measured: the shipped config went from 14 to 113 listed models with no OpenAI sign-in.
- A conditional seed (only when setup targets OpenAI) was offered and declined. It costs more code and misses users who sign in to ChatGPT later.

## Nuance

- All three keys are required. Config merges a limit per key (`config/plugin/provider.ts:235`) and the cap plugin writes `input`, so an override without `input` leaves the cap in place.
- The override reaches fresh setups only. Re-running setup keeps an existing config by default (`deploy/setup.sh:2897-2905`), and `--models-only` never asks. Documented in `MIGRATION.md`.
- Config applying after the cap plugin is a source reading (`config/plugin/provider.ts:97-99`), not a live ChatGPT sign-in test.
