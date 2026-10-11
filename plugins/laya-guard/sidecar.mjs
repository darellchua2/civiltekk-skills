// sidecar.mjs — laya-guard Node sidecar: JSONL RPC over stdio.
//
// Spawned by plugins/opencode-laya-guard.ts (the opencode plugin runs on
// opencode's embedded Bun runtime; ONNX inference needs Node-native modules,
// so the model lives here). Exits on stdin close — parent death ends it, so
// there is no daemon to manage.
//
// Protocol in:  {"id":N,"op":"ping"}
//               {"id":N,"op":"systemOne","state":<json>,"questions":{name:{type,instructions,criteria}}}
// Protocol out: {"id":N,"ok":true,...} | {"id":N,"ok":false,"error":"..."}
//
// Fail-closed posture: the sidecar reports raw laya answers or ok:false — it
// never fabricates probabilities. The CALLER (plugin) applies the p=1
// fallback for missing answers.
import readline from "node:readline"

// Pinned ONNX bundle revision (huggingface.co/receptron/laya-onnx commit).
// Keep in sync with warm.mjs and deploy/setup.sh's provisioning check.
const LAYA_REVISION = "68f27df"

let laya = null // warm model handle
let loading = null // in-flight load promise (dedup concurrent first calls)
let queue = Promise.resolve() // serializes inference — one ORT session

async function getModel() {
  if (laya) return laya
  if (!loading) {
    loading = (async () => {
      const { Laya } = await import("@receptron/laya")
      const opts = { executionProviders: ["cpu"], revision: LAYA_REVISION }
      if (process.env.LAYA_GUARD_MODEL_DIR) opts.modelDir = process.env.LAYA_GUARD_MODEL_DIR
      laya = await Laya.load(opts)
      return laya
    })().catch((err) => {
      loading = null // allow retry on a transient failure
      throw err
    })
  }
  return loading
}

function handle(msg) {
  if (msg.op === "ping") {
    return Promise.resolve({ ok: true, pong: true, model_loaded: Boolean(laya), node: process.versions.node })
  }
  if (msg.op === "systemOne") {
    if (typeof msg.state === "undefined" || !msg.questions || typeof msg.questions !== "object") {
      return Promise.resolve({ ok: false, error: "systemOne requires state and questions" })
    }
    queue = queue.then(() => getModel()).then((model) => model.systemOne(msg.state, msg.questions)).then(
      (result) => ({ ok: true, answers: result.answers, usage: result.usage ?? null }),
    )
    return queue
  }
  return Promise.resolve({ ok: false, error: `unknown op: ${String(msg.op).slice(0, 40)}` })
}

function write(obj) {
  try {
    process.stdout.write(JSON.stringify(obj) + "\n")
  } catch {
    // parent gone — stdin close will end us
  }
}

const rl = readline.createInterface({ input: process.stdin, terminal: false })
rl.on("line", (line) => {
  let msg
  try {
    msg = JSON.parse(line)
  } catch {
    write({ id: null, ok: false, error: "unparseable line" })
    return
  }
  const id = typeof msg.id === "number" ? msg.id : null
  handle(msg).then(
    (payload) => write({ id, ...payload }),
    (err) => write({ id, ok: false, error: String((err && err.message) || err).slice(0, 300) }),
  )
})
rl.on("close", () => process.exit(0))
