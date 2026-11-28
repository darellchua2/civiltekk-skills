// summary.mjs — turn laya-guard shadow logs into a one-screen report.
//
// Usage:
//   node summary.mjs <log-file | project-dir>... [--top N] [--ask P] [--deny P]
//
// A project dir resolves to <dir>/.opencode/laya-guard-shadow.jsonl. Reads
// only the logs you name; writes nothing. Works on logs written by older
// plugin versions (they carry `action` but no `kind`).
//
// Requires Node (any version with ESM). No dependencies.
import { existsSync, readFileSync, statSync } from "node:fs"
import { join } from "node:path"

const argv = process.argv.slice(2)
const flagIndex = (name) => argv.indexOf(name)
const numberFlag = (name, fallback) => {
  const i = flagIndex(name)
  return i >= 0 ? Number(argv[i + 1]) : fallback
}
const skip = new Set()
for (const name of ["--top", "--ask", "--deny"]) {
  const i = flagIndex(name)
  if (i >= 0) {
    skip.add(i)
    skip.add(i + 1)
  }
}
const top = numberFlag("--top", 10)
const ask = numberFlag("--ask", 0.8)
const deny = flagIndex("--deny") >= 0 ? Number(argv[flagIndex("--deny") + 1]) : null

const inputs = argv.filter((_, i) => !skip.has(i))
if (inputs.length === 0) inputs.push(".")
const files = inputs.flatMap((p) => {
  let file
  try {
    file = statSync(p).isDirectory() ? join(p, ".opencode", "laya-guard-shadow.jsonl") : p
  } catch {
    process.stderr.write(`not found: ${p}\n`)
    return []
  }
  if (!existsSync(file)) {
    process.stderr.write(`no log yet: ${file}\n`)
    return []
  }
  return [file]
})

const rows = []
for (const file of files) {
  let text
  try {
    text = readFileSync(file, "utf8")
  } catch {
    process.stderr.write(`unreadable: ${file}\n`)
    continue
  }
  for (const line of text.split("\n")) {
    if (!line.trim()) continue
    try {
      rows.push(JSON.parse(line))
    } catch {
      // a half-written last line while the plugin is logging — ignore
    }
  }
}

if (rows.length === 0) {
  process.stderr.write("no log lines found — pass a project dir or a laya-guard-shadow.jsonl file\n")
  process.exit(1)
}

const pct = (n, d) => (d ? `${((100 * n) / d).toFixed(1)}%` : "0.0%")
const day = (ts) => new Date(ts).toISOString().slice(0, 10)
const median = (values) => {
  if (values.length === 0) return NaN
  const sorted = [...values].sort((a, b) => a - b)
  const mid = sorted.length >> 1
  return sorted.length % 2 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2
}
// Ranks by the questions that set the verdict (`gates`, newer lines); older
// lines gated on every question, so the highest of them all stands in.
const highest = (row) => Math.max(...(row.gates ?? Object.keys(row.questions)).map((name) => row.questions[name] ?? 1))

console.log(`laya-guard shadow log: ${rows.length} lines from ${files.length} file(s), ${day(Math.min(...rows.map((r) => r.ts)))} to ${day(Math.max(...rows.map((r) => r.ts)))}`)
console.log(`thresholds: ask at ${ask}${deny === null ? ', deny off (a score never blocks)' : `, deny at ${deny}`}`)
console.log("pass = would run freely | ask = would prompt you | deny = would block | skipped = not scored (sidecar busy or failed)")

const kinds = new Map()
for (const row of rows) {
  const kind = row.kind ?? row.action ?? "unknown"
  if (!kinds.has(kind)) kinds.set(kind, [])
  kinds.get(kind).push(row)
}

for (const [kind, all] of kinds) {
  const count = (verdict) => all.filter((r) => r.would_be === verdict).length
  console.log(`\n${kind}: ${all.length} lines`)

  console.log(
    `  verdict when logged:  pass ${pct(count("pass"), all.length)}   ask ${pct(count("ask"), all.length)}   deny ${pct(count("deny"), all.length)}   skipped ${pct(count("skipped"), all.length)}`,
  )

  const rules = new Map()
  for (const row of all) if (row.rule) rules.set(row.rule, (rules.get(row.rule) ?? 0) + 1)
  for (const [rule, n] of [...rules].sort((a, b) => b[1] - a[1])) console.log(`  ${String(n).padStart(7)}  ${rule}`)

  const scored = all.filter((r) => Object.keys(r.questions ?? {}).length > 0)
  if (scored.length === 0) continue

  for (const name of new Set(scored.flatMap((r) => Object.keys(r.questions)))) {
    const values = scored.map((r) => r.questions[name] ?? 1)
    const row = `  ${name.padEnd(12)} median ${median(values).toFixed(2)}   >= ${ask}: ${pct(values.filter((v) => v >= ask).length, values.length).padStart(6)}`
    console.log(deny === null ? row : `${row}   >= ${deny}: ${pct(values.filter((v) => v >= deny).length, values.length).padStart(6)}`)
  }

  const distinct = new Set(scored.map((r) => r.target)).size
  console.log(`  top ${top} by highest score (${distinct} distinct texts; the same text always gets the same score):`)
  const shown = new Set()
  for (const row of [...scored].sort((a, b) => highest(b) - highest(a))) {
    if (shown.has(row.target)) continue
    shown.add(row.target)
    console.log(`    ${String(row.would_be).padEnd(6)} ${highest(row).toFixed(2)}  ${String(row.target).replace(/\s+/g, " ").slice(0, 100)}`)
    if (shown.size >= top) break
  }
}
