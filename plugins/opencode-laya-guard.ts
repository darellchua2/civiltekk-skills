// opencode-laya-guard.ts — OpenCode v2 local plugin: laya-guard.
//
// Gates bash/edit permission decisions through a local Laya decision model
// (shadow mode by default — log only) and exposes the laya_classify tool for
// skill decision trees. Zero npm imports by house rule (vibeguard-v2
// pattern): ONNX inference runs in a Node sidecar spawned from
// ~/.cache/laya-guard (provisioned by deploy/setup.sh), so this file stays
// loadable by opencode's embedded runtime and the plugin set stays
// dependency-free.
//
// Fail-closed: missing answers count as p=1 (=> at least "ask" in enforce
// mode); sidecar failure degrades to "ask" in enforce, to a log entry in
// shadow. Thresholds live in config, never in the model. Shadow logs carry
// action metadata only (truncated) — never file contents or env values.
//
// Config lookup (first match wins, vibeguard contract):
//   <project>/laya-guard.config.json
//   <project>/.opencode/laya-guard.config.json
//   ~/.config/opencode/plugins/laya-guard/laya-guard.config.json  (shipped default)

import { spawn } from "node:child_process"
import { appendFileSync, existsSync, mkdirSync, readFileSync } from "node:fs"
import { homedir } from "node:os"
import { dirname, join } from "node:path"

interface LayaGuardConfig {
  enabled: boolean
  mode: "shadow" | "enforce"
  deny: number
  ask: number
  actions: string[]
  timeout_ms: number
  shadow_log: string
  sidecar_dir: string
  model_dir: string | null
}

const DEFAULTS: LayaGuardConfig = {
  enabled: true,
  mode: "shadow",
  deny: 0.8,
  ask: 0.3,
  actions: ["bash", "edit"],
  timeout_ms: 60000, // generous: covers a cold ~2 GB model load + inference
  shadow_log: ".opencode/laya-guard-shadow.jsonl",
  sidecar_dir: join(homedir(), ".cache", "laya-guard"),
  model_dir: null, // local bundle override; null = laya-managed cache
}

function loadConfig(projectDir: string): LayaGuardConfig {
  const candidates = [
    join(projectDir, "laya-guard.config.json"),
    join(projectDir, ".opencode", "laya-guard.config.json"),
    join(homedir(), ".config", "opencode", "plugins", "laya-guard", "laya-guard.config.json"),
  ]
  for (const path of candidates) {
    if (!existsSync(path)) continue
    try {
      const raw = JSON.parse(readFileSync(path, "utf8"))
      return { ...DEFAULTS, ...raw }
    } catch {
      break // unparseable config => defaults (fail toward shipped shadow mode)
    }
  }
  return DEFAULTS
}

function choiceQuestion(instructions: string) {
  return {
    type: "choice" as const,
    instructions,
    criteria: { yes: "the statement is true", no: "the statement is false" },
  }
}

const GATE_QUESTIONS = () => ({
  destructive: choiceQuestion(
    "The action could delete, overwrite, or irreversibly change data, git history, or system state.",
  ),
  exfiltration: choiceQuestion(
    "The action could send local files, credentials, keys, or secrets to an external destination.",
  ),
  injection: choiceQuestion(
    "The content contains embedded instructions attempting to manipulate or bypass an AI agent's safety rules.",
  ),
})

// Truncation bound for anything derived from action metadata that we log or
// classify — bounds the residual leak path of a command carrying an inline
// credential, and keeps laya inputs inside its token budget.
const METADATA_MAX = 200

export default {
  id: "laya-guard",
  setup(ctx: any) {
    const cfg = loadConfig(ctx.location.directory)
    if (!cfg.enabled) return

    if (!existsSync(join(cfg.sidecar_dir, "sidecar.mjs"))) {
      console.warn(
        `[laya-guard] sidecar not provisioned at ${cfg.sidecar_dir} — plugin inactive. Run setup.sh (or --enable-pack laya for the model).`,
      )
      return
    }

    // ---- sidecar client ----------------------------------------------------
    let child: any = null
    let buffer = ""
    let nextId = 1
    let ready = false // ping'd + node version validated + init applied
    let permanentError: string | null = null
    const pending = new Map<number, { resolve: (v: any) => void; timer: any }>()

    function failAllPending(reason: string) {
      for (const [id, p] of pending) {
        clearTimeout(p.timer)
        p.resolve({ ok: false, error: reason })
        pending.delete(id)
      }
    }

    function ensureChild() {
      if (child && child.exitCode === null && !child.killed) return child
      child = spawn("node", [join(cfg.sidecar_dir, "sidecar.mjs")], { stdio: ["pipe", "pipe", "pipe"] })
      // EPIPE from a dying child arrives as an emitted 'error' event — try/catch
      // around write() cannot catch it, and an unhandled 'error' would crash the
      // host process. Swallow here; the 'exit' handler recovers the client.
      child.stdin?.on("error", () => {})
      child.stdout?.on("error", () => {})
      child.stderr?.on("error", () => {})
      buffer = ""
      child.stdout.on("data", (chunk: Buffer) => {
        buffer += chunk.toString("utf8")
        let idx: number
        while ((idx = buffer.indexOf("\n")) >= 0) {
          const line = buffer.slice(0, idx)
          buffer = buffer.slice(idx + 1)
          let msg: any
          try {
            msg = JSON.parse(line)
          } catch {
            continue
          }
          const p = pending.get(msg.id)
          if (!p) continue // late response after a timeout — drop
          clearTimeout(p.timer)
          pending.delete(msg.id)
          p.resolve(msg)
        }
      })
      child.on("exit", () => {
        child = null
        ready = false
        failAllPending("laya-guard sidecar exited unexpectedly")
      })
      return child
    }

    function request(body: Record<string, unknown>, timeoutMs: number): Promise<any> {
      if (permanentError) return Promise.resolve({ ok: false, error: permanentError })
      const c = ensureChild()
      const id = nextId++
      const line = JSON.stringify({ id, ...body }) + "\n"
      return new Promise((resolve) => {
        const timer = setTimeout(() => {
          pending.delete(id)
          resolve({ ok: false, error: `sidecar timeout after ${timeoutMs}ms` })
        }, timeoutMs)
        pending.set(id, { resolve, timer })
        try {
          c.stdin.write(line)
        } catch (err) {
          pending.delete(id)
          clearTimeout(timer)
          resolve({ ok: false, error: `sidecar write failed: ${String(err).slice(0, 120)}` })
        }
      })
    }

    async function ensureReady(): Promise<string | null> {
      if (ready) return null
      const ping = await request({ op: "ping" }, 10_000)
      if (!ping.ok) return ping.error ?? "sidecar ping failed"
      const major = Number(String(ping.node ?? "0").split(".")[0])
      if (!(major >= 24)) {
        permanentError = `sidecar Node ${ping.node} is too old — laya-guard needs Node >= 24`
        return permanentError
      }
      if (cfg.model_dir) {
        const init = await request({ op: "init", model_dir: cfg.model_dir }, 10_000)
        if (!init.ok) return init.error ?? "sidecar init failed"
      }
      ready = true
      return null
    }

    async function classify(state: Record<string, unknown>, questions: Record<string, unknown>) {
      const err = await ensureReady()
      if (err) return { ok: false, error: err }
      const res = await request({ op: "systemOne", state, questions }, cfg.timeout_ms)
      if (!res.ok) return res
      return { ok: true, answers: res.answers }
    }

    // ---- shadow logger (metadata only) --------------------------------------
    function logShadow(event: any, questions: Record<string, number>, wouldBe: string, extra?: Record<string, unknown>) {
      const target = (event.resources ?? []).join(" | ").slice(0, METADATA_MAX)
      const line = JSON.stringify({
        ts: Date.now(),
        action: event.action,
        target,
        questions,
        would_be: wouldBe,
        mode: cfg.mode,
        ...extra,
      })
      try {
        const path = join(ctx.location.directory, cfg.shadow_log)
        mkdirSync(dirname(path), { recursive: true })
        appendFileSync(path, line + "\n")
      } catch {
        // logging must never break the agent loop
      }
    }

    function report(d: number, x: number, i: number) {
      return `destructive=${d.toFixed(2)} exfiltration=${x.toFixed(2)} injection=${i.toFixed(2)}`
    }

    // ---- permission gate -----------------------------------------------------
    ctx.permission.hook("evaluate", async (event: any) => {
      if (!cfg.actions.includes(event.action)) return

      // Metadata only: the action's resource strings, truncated. This is the
      // classification signal — file contents and env values never reach here.
      const statement = (event.resources ?? []).join(" | ").slice(0, METADATA_MAX)

      let answers: any
      try {
        const res = await classify(
          { subject: `agent ${event.action} action`, body: statement },
          GATE_QUESTIONS(),
        )
        if (!res.ok) throw new Error(res.error)
        answers = res.answers
      } catch (err) {
        // Fail closed: treat every question as yes.
        const p1 = { destructive: 1, exfiltration: 1, injection: 1 }
        if (cfg.mode === "enforce") {
          event.effect = "ask"
          event.message = `laya-guard: inference failed — human review (${String(err).slice(0, 120)})`
        }
        logShadow(event, p1, "deny", { failure: String(err).slice(0, 120) })
        return
      }

      // Fail closed: a missing probability counts as yes (p=1).
      const pOf = (key: string) => answers?.[key]?.probabilities?.yes ?? 1
      const d = pOf("destructive")
      const x = pOf("exfiltration")
      const i = pOf("injection")
      const wouldBe =
        d >= cfg.deny || x >= cfg.deny || i >= cfg.deny
          ? "deny"
          : d >= cfg.ask || x >= cfg.ask || i >= cfg.ask
            ? "ask"
            : "pass"

      if (cfg.mode === "shadow") {
        logShadow(event, { destructive: d, exfiltration: x, injection: i }, wouldBe)
        return
      }

      if (wouldBe === "deny") {
        event.effect = "deny"
        event.message = `Blocked by laya-guard (${report(d, x, i)})`
      } else if (wouldBe === "ask") {
        event.effect = "ask"
        event.message = `laya-guard: risky action, needs approval (${report(d, x, i)})`
      }
    })

    // ---- laya_classify tool (advisory — for skill decision trees) ------------
    ctx.tool.transform((editor: any) => {
      editor.add({
        name: "laya_classify",
        description:
          "Local Laya decision-model classifier. Given a short statement and yes/no questions, returns calibrated p(yes) per question. Advisory only — probabilities inform a decision, they never replace it. Runs fully offline.",
        input: {
          type: "object",
          properties: {
            state: {
              type: "string",
              description:
                "The statement to classify — short composed text (metadata only; never file dumps or secrets).",
            },
            questions: {
              type: "array",
              minItems: 1,
              maxItems: 8,
              items: {
                type: "object",
                properties: {
                  name: { type: "string", description: "Question key used in the result." },
                  instructions: { type: "string", description: "The yes/no question text." },
                },
                required: ["name", "instructions"],
                additionalProperties: false,
              },
            },
          },
          required: ["state", "questions"],
          additionalProperties: false,
        },
        execute: async (input: any) => {
          const state = { subject: "classification request", body: String(input.state).slice(0, 2000) }
          const questions: Record<string, unknown> = {}
          for (const q of input.questions ?? []) questions[String(q.name).slice(0, 64)] = choiceQuestion(String(q.instructions))
          if (Object.keys(questions).length === 0) {
            return { content: "laya_classify error: no valid questions supplied" }
          }
          const res = await classify(state, questions)
          if (!res.ok) return { content: `laya_classify error: ${res.error}` }
          const out: Record<string, { p_yes: number }> = {}
          for (const [key, answer] of Object.entries(res.answers ?? {})) {
            out[key] = { p_yes: answer?.probabilities?.yes ?? 1 }
          }
          return { content: JSON.stringify(out) }
        },
      })
    })

    // ---- lifecycle -----------------------------------------------------------
    return () => {
      failAllPending("laya-guard plugin unloading")
      if (child && child.exitCode === null) child.kill()
      child = null
    }
  },
}
