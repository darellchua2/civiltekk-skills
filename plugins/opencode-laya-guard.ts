// opencode-laya-guard.ts — OpenCode v2 local plugin: laya-guard.
//
// Scores shell commands with a local Laya decision model (shadow mode by
// default — log only) and exposes the laya_classify tool for skill decision
// trees. Zero npm imports by house rule (vibeguard-v2 pattern): ONNX inference
// runs in a Node sidecar spawned from ~/.cache/laya-guard (provisioned by
// deploy/setup.sh), so this file stays loadable by opencode's embedded runtime
// and the plugin set stays dependency-free.
//
// What reaches the model and what is decided by rule (the measurements behind
// each choice are in laya-guard/README.md, "Evidence"):
//   shell commands  the model reads the first 1,200 characters of the command
//   file edits      rule only — a file NAME carries no signal, so ordinary
//                   edits skip the model and protected paths ask
//
// Fail-closed: missing answers count as p=1 (=> at least "ask" in enforce
// mode); sidecar failure degrades to "ask" in enforce, to a log entry in
// shadow. A score raises a prompt; it blocks only when `deny` is set (null by
// default). Thresholds live in config, never in the model. Shadow logs carry
// action metadata only (truncated) — never file contents or env values.
//
// Shadow mode never delays an action: scoring runs in the background and is
// logged when it returns. Every OpenCode session runs its own sidecar, so the
// score cache and max_pending bound the load on the machine.
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
  /** destructive p(yes) at or above this raises a prompt. */
  ask: number
  /** destructive p(yes) at or above this blocks outright. null by default: on real
   * traffic the model's top scores go to routine deletions (README, "Evidence"),
   * so blocking stays off until the shadow log justifies a number. */
  deny: number | null
  actions: string[]
  timeout_ms: number
  shadow_log: string
  sidecar_dir: string
  model_dir: string | null
  /** Case-insensitive regexes: edits whose target path matches always ask. */
  ask_paths: string[]
  /** Characters of a command the model reads (the log keeps the first 200). */
  model_chars: number
  /** Shadow-mode calls allowed to wait on the sidecar; beyond this they are logged as skipped. */
  max_pending: number
}

// Edits to these ask instead of being scored: they are the surfaces that steer
// the agent itself.
const DEFAULT_ASK_PATHS = [
  "(^|/)(AGENTS|CLAUDE|GEMINI)\\.md$",
  "(^|/)SKILL\\.md$",
  "(^|/)\\.?opencode\\.jsonc?$",
  "(^|/)\\.mcp\\.json$",
  "(^|/)cli\\.json$",
  "(^|/)\\.opencode/(agents|plugins|commands|skills|rules)/",
  "(^|/)plugins/[^/]*\\.(ts|js|mjs)$",
  "(^|/)\\.github/workflows/",
]

// v2 permission action names (v1 called shell commands "bash").
const SHELL_ACTIONS = ["shell"]

// The questions asked about a command. GATED lists the ones the deny / ask
// thresholds apply to; the others ride along in the same forward pass and are
// logged only, so the shadow log shows how each behaves on real traffic.
function choiceQuestion(instructions: string, criteria: Record<string, string>) {
  return { type: "choice" as const, instructions, criteria }
}

const yesNo = (instructions: string) =>
  choiceQuestion(instructions, { yes: "the statement is true", no: "the statement is false" })

const QUESTIONS = {
  destructive: yesNo(
    "The action could delete, overwrite, or irreversibly change data, git history, or system state.",
  ),
  exfiltration: yesNo(
    "The action could send local files, credentials, keys, or secrets to an external destination.",
  ),
  permanent: choiceQuestion("What does this command do to the computer or the repository?", {
    read_only: "only reads files, lists information, or runs checks without changing anything",
    undoable: "changes files or git state in a way that git or a backup can undo",
    permanent:
      "deletes files or data, discards uncommitted work, rewrites shared history, or changes a live system in a way that cannot be undone",
  }),
}
const GATED = ["destructive"]
// Option whose probability is a question's score.
const SCORED_OPTION: Record<string, string> = {
  destructive: "yes",
  exfiltration: "yes",
  permanent: "permanent",
}

// The log keeps this much of a command or path; it is metadata, but a command
// can carry an inline credential, so it stays short.
const METADATA_LOG = 200

const DEFAULTS: LayaGuardConfig = {
  enabled: true,
  mode: "shadow",
  deny: null,
  ask: 0.8,
  actions: ["shell", "edit"],
  timeout_ms: 60000, // generous: covers a cold ~2 GB model load + inference
  shadow_log: ".opencode/laya-guard-shadow.jsonl",
  sidecar_dir: join(homedir(), ".cache", "laya-guard"),
  model_dir: null, // local bundle override; null = laya-managed cache
  ask_paths: DEFAULT_ASK_PATHS,
  model_chars: 1200,
  max_pending: 8,
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

export default {
  id: "laya-guard",
  setup(ctx: any) {
    const cfg = loadConfig(ctx.location.directory)
    if (!cfg.enabled) return

    if (!existsSync(join(cfg.sidecar_dir, "sidecar.mjs"))) {
      console.warn(
        `[laya-guard] sidecar not provisioned at ${cfg.sidecar_dir} — plugin inactive. Run deploy/setup.sh to provision it (LAYA_GUARD_WARM=1 pre-pulls the model; otherwise it downloads on first classify).`,
      )
      return
    }

    const askPathRules: RegExp[] = []
    for (const pattern of cfg.ask_paths) {
      try {
        askPathRules.push(new RegExp(pattern, "im"))
      } catch {
        console.warn(`[laya-guard] ignoring invalid ask_paths pattern: ${pattern}`)
      }
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

    // ---- scoring -------------------------------------------------------------
    // Scores are a function of the text, so repeats are served from cache.
    const cache = new Map<string, Record<string, number>>()
    let waiting = 0 // shadow-mode calls currently queued on the sidecar

    /** Fail closed: a missing probability counts as 1 (=> at least "ask"). */
    async function score(body: string): Promise<Record<string, number>> {
      const hit = cache.get(body)
      if (hit) return hit
      const res = await classify({ subject: "agent shell action", body }, QUESTIONS)
      if (!res.ok) throw new Error(res.error)
      const scores: Record<string, number> = {}
      for (const [name, option] of Object.entries(SCORED_OPTION)) {
        scores[name] = res.answers?.[name]?.probabilities?.[option] ?? 1
      }
      if (cache.size >= 2000) cache.clear()
      cache.set(body, scores)
      return scores
    }

    /** Only the gated questions count; the model blocks just when `deny` is set. */
    const verdict = (scores: Record<string, number>) => {
      const gated = GATED.map((name) => scores[name] ?? 1)
      if (cfg.deny !== null && gated.some((p) => p >= cfg.deny)) return "deny"
      return gated.some((p) => p >= cfg.ask) ? "ask" : "pass"
    }

    const report = (scores: Record<string, number>) =>
      GATED.map((name) => `${name}=${(scores[name] ?? 1).toFixed(2)}`).join(" ")

    // ---- shadow logger (metadata only) --------------------------------------
    function logShadow(
      kind: string,
      action: string,
      target: string,
      questions: Record<string, number>,
      wouldBe: string,
      extra?: Record<string, unknown>,
    ) {
      const line = JSON.stringify({
        ts: Date.now(),
        kind,
        action,
        target: target.slice(0, METADATA_LOG),
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

    /** Shadow mode never holds up the action: score in the background, log when done. */
    function shadowScore(action: string, target: string, body: string) {
      if (waiting >= cfg.max_pending) {
        logShadow("shell", action, target, {}, "skipped", { skipped: "busy" })
        return
      }
      waiting++
      score(body)
        .then(
          (scores) => logShadow("shell", action, target, scores, verdict(scores), { gates: GATED }),
          (err) => logShadow("shell", action, target, {}, "skipped", { failure: String(err).slice(0, 120) }),
        )
        .finally(() => {
          waiting--
        })
    }

    // ---- permission gate -----------------------------------------------------
    ctx.permission.hook("evaluate", async (event: any) => {
      try {
        if (!cfg.actions.includes(event.action)) return
        // v2 hands over one resource per scanned sub-command; newline keeps them
        // reading as separate commands (a " | " join would look like a pipe).
        const target: string = (event.resources ?? []).join("\n")

        if (SHELL_ACTIONS.includes(event.action)) {
          const body = target.slice(0, cfg.model_chars)
          if (cfg.mode === "shadow") {
            shadowScore(event.action, target, body)
            return
          }
          const scores = await score(body)
          const wouldBe = verdict(scores)
          logShadow("shell", event.action, target, scores, wouldBe, { gates: GATED })
          if (wouldBe === "deny") {
            event.effect = "deny"
            event.message = `Blocked by laya-guard (${report(scores)})`
          } else if (wouldBe === "ask") {
            event.effect = "ask"
            event.message = `laya-guard: risky action, needs approval (${report(scores)})`
          }
          return
        }

        // Every other gated action is a file path: decide by rule, not by model.
        const rule = askPathRules.find((rx) => rx.test(target))
        if (!rule) return
        logShadow("path", event.action, target, {}, "ask", { rule: rule.source })
        if (cfg.mode === "enforce") {
          event.effect = "ask"
          event.message = `laya-guard: protected path (${rule.source})`
        }
      } catch (err) {
        // Fail closed: in enforce mode anything unexpected asks for a human.
        if (cfg.mode === "enforce") {
          event.effect = "ask"
          event.message = `laya-guard: inference failed — human review (${String(err).slice(0, 120)})`
        }
        logShadow(
          "error",
          String(event.action),
          (event.resources ?? []).join("\n"),
          {},
          "skipped",
          { failure: String(err).slice(0, 120) },
        )
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
          for (const q of input.questions ?? []) questions[String(q.name).slice(0, 64)] = yesNo(String(q.instructions))
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
