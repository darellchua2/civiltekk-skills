# laya-guard

Local Laya decision-model gate for opencode: a shadow/enforce permission hook
for shell commands and file edits, plus the `laya_classify` tool for skill
decision trees. Runs fully offline after provisioning — no API keys, no telemetry.

## Architecture

The opencode v2 plugin runtime is the runtime opencode ships (embedded in its
binary) — it is not Node, and ONNX inference needs Node-native modules
(`onnxruntime-node`). So the model lives in a **Node sidecar**:

```
opencode (plugin host)
└── plugins/opencode-laya-guard.ts      zero npm imports — hook + tool registration
    └── spawns:  node ~/.cache/laya-guard/sidecar.mjs   (Node >= 24)
                  └── @receptron/laya + onnxruntime-node  (own node_modules)
                      └── Laya 421M ONNX (CPU, ~2 GB RAM when warm, at most 6 threads)
```

The sidecar speaks one JSON object per line over stdio and exits when its
stdin closes — when opencode goes away, the sidecar and the ~2 GB model go
with it. No daemon, no systemd unit, no Python. Every OpenCode session runs
its own sidecar, so five open sessions hold five copies of the model.

## What it decides

| Action | How it is decided | Default |
|--------|-------------------|---------|
| `shell` command | The model reads the first 1,200 characters of the command and answers one question: "The action could delete, overwrite, or irreversibly change data, git history, or system state." | `shadow` (log only) |
| File edit (`edit`, `write`, `patch`) | Path rule, no model. Edits that match `ask_paths` (agent instructions, agent/permission config, plugin code, CI workflows) ask; every other edit is ignored. | `shadow` |
| Skill decision trees | `laya_classify` tool — advisory p(yes) per question | always available |

Hard-configured permission denies are final upstream — they never reach this
hook. laya-guard handles the gray zone; config handles the certainties.

A score can only raise a prompt. Blocking stays off (`"deny": null`) until your
own log justifies a number; the reason is under "Evidence".

In shadow mode nothing is ever blocked or prompted. Scoring also runs in the
background, so no action waits for the model; each line appears in the log
when its score is ready. A session that exits within a few seconds of its last
command (a one-shot `opencode run`) logs that command as `skipped`.

Two more questions ride along in the same pass and are logged but never gate:
`exfiltration` (sends local files or credentials to an external destination)
and `permanent` (read-only / undoable / permanent). Only `destructive` sets
the verdict. The log is what shows whether another question deserves to gate.

## Reading the log

Each scored action is one JSON line in the shadow log:

```json
{"ts":1795642969486,"kind":"shell","action":"shell","target":"git push --force origin feat/1","questions":{"destructive":0.91,"exfiltration":0.12,"permanent":0.57},"would_be":"ask","mode":"shadow","gates":["destructive"]}
```

| Field | Meaning |
|-------|---------|
| `kind` | `shell` (model-scored command), `path` (edit matched an `ask_paths` rule) or `error` |
| `target` | The command or path, first 200 characters only. A compound command arrives as one line per sub-command |
| `questions` | The model's probability that each statement is true |
| `would_be` | What enforce mode would have done: `ask` at `ask` or above, `deny` only when `deny` is set, otherwise `pass`. `skipped` means it was not scored (sidecar busy or failed) |
| `rule` | `path` lines only: the `ask_paths` pattern that matched |
| `gates` | `shell` lines only: the questions the verdict is based on (`destructive`) |

Turn any log into a one-screen report (verdict mix, per-question hit rates at
the thresholds, the highest-scoring commands):

```sh
node ~/.config/opencode/plugins/laya-guard/summary.mjs ~/code/my-project
```

Pass several project directories to combine them, `--top 30` for a longer
list, `--ask 0.6` to see another prompt line, or `--deny 0.95` to see what a
block line would catch. The same text always gets the same score, so read the
top list rather than the volume.

## Deploy

```sh
./deploy/setup.sh                       # provisions sidecar deps (Linux; small)
LAYA_GUARD_WARM=1 ./deploy/setup.sh     # + pre-pulls the ~1.7 GB model bundle
                                         #   (interactive deploys: just answer y)
LAYA_GUARD_SKIP=1 ./deploy/setup.sh     # skip laya-guard provisioning entirely
```

Provisioning is idempotent: the marker hashes `package.json`, `sidecar.mjs`
and `warm.mjs`, so a change to any of them re-copies on the next deploy.
Without the pre-pull, the model downloads on first classify instead (same
pinned revision). Windows deploys skip provisioning with a notice — the
plugin file deploys but stays inert without `~/.cache/laya-guard`.

Requirements: Linux, Node >= 24 on PATH (the sidecar refuses older majors),
~1.7 GB disk for the model, ~2 GB RAM per OpenCode session while the model is
warm (loaded on first classify, freed when that session exits).

## Config

First match wins: `<project>/laya-guard.config.json`, then
`<project>/.opencode/laya-guard.config.json`, then the shipped default at
`~/.config/opencode/plugins/laya-guard/laya-guard.config.json`.

```jsonc
{
  "mode": "shadow",        // "shadow" = log only | "enforce" = change effects
  "ask": 0.8,              // destructive p(yes) at or above this => ask
  "deny": null,            // a number => block at or above it; keep null until calibrated
  "actions": ["shell", "edit"],
  "timeout_ms": 60000,     // per-request; covers a cold model load
  "shadow_log": ".opencode/laya-guard-shadow.jsonl",
  "model_chars": 1200,     // characters of a command the model reads
  "max_pending": 8,        // shadow calls allowed to wait; beyond this => "skipped"
  "ask_paths": [ /* regexes; replaces the default list when set */ ],
  "model_dir": null        // local bundle path (air-gap); null = managed cache
}
```

Fail-closed by construction: a missing answer counts as p(yes)=1, an
inference failure becomes `ask` in enforce mode (never a silent allow).

Shadow logs carry **metadata only**: action name, truncated resource strings
(200 chars), question probabilities. Never file contents, never env values.

Scoring costs about one to three seconds of background CPU per command (six
threads at most). To stop scoring commands, set `"actions": ["edit"]`.

`ask_paths` defaults (case-insensitive):

```
(^|/)(AGENTS|CLAUDE|GEMINI)\.md$          (^|/)\.opencode/(agents|plugins|commands|skills|rules)/
(^|/)SKILL\.md$                           (^|/)plugins/[^/]*\.(ts|js|mjs)$
(^|/)\.?opencode\.jsonc?$                 (^|/)\.github/workflows/
(^|/)\.mcp\.json$      (^|/)cli\.json$
```

## Calibration (shadow → enforce)

1. Run in shadow for a week or two of real work.
2. `node ~/.config/opencode/plugins/laya-guard/summary.mjs <project>` and read
   the top of the list against your own judgement of those commands.
3. Tune `ask` for the false-prompt rate you will tolerate; the summary shows
   what each line catches and flags. Leave `deny` null: on real traffic the
   model's highest scores go to routine deletions (see "Evidence"), so a block
   line interrupts normal work.
4. Flip per-project first (project `laya-guard.config.json` with `"mode":
   "enforce"`), verify for a few days, then flip the global config.

Known caveat: the base checkpoint scores near chance on public typed-decision
benchmarks and is "a fast base to specialise, not a zero-shot decision
engine" (its authors). Your own shadow log is the only calibration that
matters.

Truncate or delete the shadow log whenever you like — it is gitignored and
recreated on demand.

## Evidence

Measured on one machine's OpenCode session history (about 1,300 own
sessions across 54 project folders, August to November 2026) before each
choice was made. Samples are small (30 to 160 commands per comparison), so
treat the numbers as direction, not guarantees.

- **Edits were never scoreable.** The model was shown only the file *name*.
  Over six weeks it logged 35,764 edits: each of the 11,030 distinct paths
  always got the same score, the `injection` score followed the file type
  (0.5 or more on 67% of source files, 9% of Markdown), and enforce mode
  would have blocked 35% of all edits. Edits are now decided by path rule.
- **Commands need more than 200 characters.** With the first 200 characters
  the model ranked force/delete commands (`rm -rf`, `git push --force`,
  `git reset --hard`, `git worktree remove --force`, `DROP`/`DELETE FROM`…)
  against harmless ones at 0.66–0.84 on a 0.5-to-1.0 scale where 0.5 is a coin
  flip, and the dangerous token was visible in 6 of 30. With 1,200 characters
  it ranked them at 0.92, the token was visible in 71 of 80, and the median
  force/delete score was 0.82. At 0.8 it flags 55% of force/delete commands
  and about 4% of harmless ones; at 0.6, 85% and about 12%; at the old 0.3
  line, nearly everything.
- **So a score only prompts.** Of the 44 commands scored 0.8 or more, nearly
  all are deletions the agent meant to make: temp-folder cleanups (0.95–0.98),
  cache and venv removals, `git worktree remove --force` at the end of a PR
  pipeline. The highest-scoring harmless commands include a plain `du -h`
  (0.84). A block line at any threshold interrupts that work, so `deny` ships
  null and hard blocks belong in permission rules.
- **The `injection` question is meaningless on commands**: median 0.99 on
  dangerous and 0.97 on harmless ones. Removed.
- **Fetched-page injection check: tested, not shipped.** A check on text
  fetched by `webfetch` flagged 14 of 15 real fetched pages and missed 2 of 12
  planted instructions, because pages about AI tooling are full of prompt
  vocabulary. Removed rather than shipped as noise.
- **Thread pool**: with the default pool (every core) one call cost 66
  CPU-seconds; capped at 6 threads it costs 17 for the same latency.
- **Path rules** match 3.3% of the edits in the old log (CI workflows 2.5%,
  instruction files 0.8%).

## Air-gap / offline

Provision once on a connected machine (`LAYA_GUARD_WARM=1`, or answer y at the provisioning prompt), or point
`model_dir` at a locally exported ONNX bundle (see `export/export_onnx.py` in
the receptron/laya repo). After that, classification never touches the
network — the plugin itself contains zero endpoints.

## Skill wiring

`laya_classify` is advisory: three skills (requirements-inline,
architecture-review, markitdown routing) consult it when a decision-tree
branch is judgment-shaped. The agent weighs the probabilities and decides;
deterministic branches (config exists? file type?) stay in code.
