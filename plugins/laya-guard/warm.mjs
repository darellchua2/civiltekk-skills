// warm.mjs — one-shot model pre-pull for laya-guard.
//
// Run by deploy/setup.sh's provision_laya_guard (interactive prompt, or
// LAYA_GUARD_WARM=1 headless). Uses laya's
// own downloader (correct bundle file names and cache layout — hand-listed
// curl filenames drift; the original brief's list was already wrong about
// the tokenizer/ subfolder). After this completes, the sidecar's first
// classify is warm and the host is fully offline for laya traffic.
const LAYA_REVISION = "68f27df" // keep in sync with sidecar.mjs

const opts = { executionProviders: ["cpu"], revision: LAYA_REVISION }
if (process.env.LAYA_GUARD_MODEL_DIR) opts.modelDir = process.env.LAYA_GUARD_MODEL_DIR

const { Laya } = await import("@receptron/laya")
const laya = await Laya.load(opts)
console.log("laya model ready:", process.env.LAYA_GUARD_MODEL_DIR || "laya-managed cache (~/.cache/receptron-laya)")
await laya.close()
