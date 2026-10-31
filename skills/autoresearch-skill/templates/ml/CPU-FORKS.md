# CPU / macOS / Windows / AMD Forks

The baseline `the ml route` targets a single NVIDIA GPU (tested on H100).
For non-GPU or non-NVIDIA platforms, use one of these notable forks of
karpathy/autoresearch instead — they tune the defaults for smaller compute.

> Source: karpathy/autoresearch README §Notable forks (MIT).
> Full notice: THIRD_PARTY_LICENSES.md.

## Notable forks

| Fork | Platform | One-line install |
|------|----------|------------------|
| [miolini/autoresearch-macos](https://github.com/miolini/autoresearch-macos) | macOS | `git clone https://github.com/miolini/autoresearch-macos && uv sync` |
| [trevin-creator/autoresearch-mlx](https://github.com/trevin-creator/autoresearch-mlx) | macOS (Metal / MLX) | `git clone https://github.com/trevin-creator/autoresearch-mlx && uv sync` |
| [jsegov/autoresearch-win-rtx](https://github.com/jsegov/autoresearch-win-rtx) | Windows (NVIDIA RTX) | `git clone https://github.com/jsegov/autoresearch-win-rtx && uv sync` |
| [andyluo7/autoresearch](https://github.com/andyluo7/autoresearch) | AMD ROCm | `git clone https://github.com/andyluo7/autoresearch && uv sync` |

## Tuning guidance for smaller compute

From karpathy's README — when porting to a smaller machine, tune in this order:

1. **Dataset entropy** — use a narrower dataset (e.g. TinyStories) so small models learn something visible.
2. **`VOCAB_SIZE`** — drop from 8192 down to 4096 / 2048 / 1024, or use byte-level (256).
3. **`MAX_SEQ_LEN`** — lower from 2048 to 256–1024 depending on the machine.
4. **`EVAL_TOKENS`** — reduce so validation loss is evaluated on less data.
5. **`DEPTH`** (in `train.py`) — the primary model-complexity knob (default 8; try 4).
6. **`WINDOW_PATTERN`** — use `"L"` (plain local attention); the SSSL alternating pattern may be slow.
7. **`TOTAL_BATCH_SIZE`** — lower to ~`2**14` (~16K), keep powers of 2.

## Routing rule for the autoresearch-ml-subagent

If the GPU preflight check fails (no NVIDIA GPU), the `autoresearch-ml-subagent`
returns a structured error pointing the user at this file and suggesting a
reroute to `autoresearch-code-subagent` (if the underlying task is code-side
optimization) or to one of the forks above.
