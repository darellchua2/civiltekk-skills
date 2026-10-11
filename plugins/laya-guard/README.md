# laya-guard

Local Laya decision-model gate for opencode: a shadow/enforce permission hook
for `bash`/`edit` actions plus the `laya_classify` tool for skill decision
trees. Runs fully offline after provisioning — no API keys, no telemetry.

## Architecture

The opencode v2 plugin runtime is the runtime opencode ships (embedded in its
binary) — it is not Node, and ONNX inference needs Node-native modules
(`onnxruntime-node`). So the model lives in a **Node sidecar**:

```
opencode (plugin host)
└── plugins/opencode-laya-guard.ts      zero npm imports — hook + tool registration
    └── spawns:  node ~/.cache/laya-guard/sidecar.mjs   (Node >= 24)
                  └── @receptron/laya + onnxruntime-node  (own node_modules)
                      └── Laya 421M ONNX (CPU, ~2 GB RAM when warm)
```

The sidecar speaks one JSON object per line over stdio and exits when its
stdin closes — when opencode goes away, the sidecar and the ~2 GB model go
with it. No daemon, no systemd unit, no Python.

## What it gates

| Decision | Mechanism | Default |
|----------|-----------|---------|
| `bash`/`edit` permission | `permission evaluate` hook — scores destructive / exfiltration / injection p(yes) | `shadow` (log only) |
| Skill decision trees | `laya_classify` tool — advisory p(yes) per question | always available |

Hard-configured permission denies (e.g. the `git push --force` rules in
`deploy/opencode.json`) are final upstream — they never reach this hook.
Laya handles the gray zone; config handles the certainties.

## Deploy

```sh
./deploy/setup.sh                       # provisions sidecar deps (Linux; small)
./deploy/setup.sh --enable-pack laya    # + pre-pulls the ~1.7 GB model bundle
LAYA_GUARD_SKIP=1 ./deploy/setup.sh     # skip laya-guard provisioning entirely
```

Provisioning is idempotent (marker + version check). Without `--enable-pack
laya`, the model downloads on first classify instead (same pinned revision).
Windows deploys skip provisioning with a notice — the plugin file deploys but
stays inert without `~/.cache/laya-guard`.

Requirements: Linux, Node >= 24 on PATH (the sidecar refuses older majors),
~1.7 GB disk for the model, ~2 GB RAM while the model is warm (loaded lazily
on first classify, freed when opencode exits).

## Config

First match wins: `<project>/laya-guard.config.json`, then
`<project>/.opencode/laya-guard.config.json`, then the shipped default at
`~/.config/opencode/plugins/laya-guard/laya-guard.config.json`.

```jsonc
{
  "mode": "shadow",        // "shadow" = log only | "enforce" = change effects
  "deny": 0.8,             // p(yes) at or above this => deny (enforce mode)
  "ask": 0.3,              // p(yes) at or above this => ask
  "actions": ["bash", "edit"],
  "timeout_ms": 60000,     // per-request; covers a cold model load
  "shadow_log": ".opencode/laya-guard-shadow.jsonl",
  "model_dir": null        // local bundle path (air-gap); null = managed cache
}
```

Fail-closed by construction: a missing answer counts as p(yes)=1, an
inference failure becomes `ask` in enforce mode (never a silent allow).

Shadow logs carry **metadata only**: action name, truncated resource strings
(200 chars), question probabilities. Never file contents, never env values.

## Calibration (shadow → enforce)

1. Run in shadow for 1–2 weeks of real work.
2. Compare each entry's `would_be` against what you actually allowed/denied.
3. Tune `deny`/`ask` so that **false deny ≈ 0** — denying safe work is the
   expensive error; `ask` should catch almost everything you would have
   wanted reviewed.
4. Flip per-project first (project `laya-guard.config.json` with `"mode":
   "enforce"`), verify for a few days, then flip the global config.

Known caveat: the base checkpoints score near chance on public typed-decision
benchmarks. Your own shadow labels are the only calibration that matters.

Truncate or delete the shadow log whenever you like — it is gitignored and
recreated on demand.

## Air-gap / offline

Provision once on a connected machine (`--enable-pack laya`), or point
`model_dir` at a locally exported ONNX bundle (see `export/export_onnx.py` in
the receptron/laya repo). After that, classification never touches the
network — the plugin itself contains zero endpoints.

## Skill wiring

`laya_classify` is advisory: three skills (requirements-inline,
architecture-review, markitdown routing) consult it when a decision-tree
branch is judgment-shaped. The agent weighs the probabilities and decides;
deterministic branches (config exists? file type?) stay in code.
