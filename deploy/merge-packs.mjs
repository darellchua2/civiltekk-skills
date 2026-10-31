#!/usr/bin/env node
// deploy/merge-packs.mjs
//
// Provider-pack merger. Deep-merges one or more pack partials
// (deploy/packs/pack-<name>.json) into a target opencode.json (v2 shape),
// flipping `mcp.servers.<server>.disabled` (packs carry `disabled: false`),
// appending `permissions` array rules.
//
// Companion to installer/resolve-models.mjs. Zero external dependencies — Node
// built-ins only (fs, path). Mirrors resolve-models.mjs conventions:
//   - ES modules, async main(), camelCase arg parsing
//   - readJsonMaybe / stripJsonComments helpers
//   - $comment keys tolerated in pack JSON
//
// Semantics (per PLAN-374 Phase 2, v2 shape):
//   - Pack `mcp` fragments are v2-shaped ({ servers: { name: { disabled: false } } })
//     and deep-merge into config.mcp.servers (inversion already applied in the
//     pack data; the merger does not translate).
//   - Pack `permissions` fragments are v2 rule arrays and are APPENDED to
//     config.permissions — never wholesale-replacing the shipped array. A rule
//     with the same action+resource replaces its prior entry in place
//     (idempotent re-runs).
//   - Deep-merge: last-wins on scalars; objects merged recursively; arrays
//     left untouched (except permissions, handled explicitly above).
//   - Empty/whitespace --packs => true no-op (exit 0, no read, no write).
//     This is the Docker `ARG OPENCODE_PACKS=""` default path. Implemented
//     via split(",").map(trim).filter(Boolean) so "" never becomes [""].
//   - Unknown pack => exit non-zero, clear error listing available packs,
//     write nothing.
//   - Malformed pack JSON => exit non-zero with file path + parse error
//     (mirrors resolve-models.mjs line 73).
//   - --dry-run => print a summary of what WOULD change; do not write.
//   - Idempotent: running the same pack list twice yields identical output.
//
// Usage:
//   node merge-packs.mjs \
//     --config <opencode.json> \
//     --packs-dir <deploy/packs> \
//     --packs markitdown \
//     [--dry-run] [--verbose]
//
// Exit codes: 0 success/no-op, 1 bad args / unknown pack / parse error / IO.

import { readFile, writeFile, readdir } from "node:fs/promises";
import { existsSync } from "node:fs";
import { join } from "node:path";

// ─────────────────────────── arg parsing ────────────────────────────────
const camel = (s) => s.replace(/-([a-z])/g, (_, c) => c.toUpperCase());

function parseArgsCamel(argv) {
  const out = {
    config: null,
    packsDir: null,
    packs: "",
    dryRun: false,
    verbose: false,
  };
  const boolKeys = new Set(["dryRun", "verbose"]);
  for (let i = 0; i < argv.length; i++) {
    let a = argv[i];
    if (!a.startsWith("--")) continue;
    let key = camel(a.slice(2));
    if (boolKeys.has(key)) {
      out[key] = true;
    } else {
      out[key] = argv[++i];
    }
  }
  return out;
}
const O = parseArgsCamel(process.argv.slice(2));

// ─────────────────────────── helpers ────────────────────────────────────

// tolerate $comment keys + trailing commas minimally (our pack files use $comment)
function stripJsonComments(txt) {
  return txt.replace(/^[ \t]*"\$comment"[ \t]*:.*$(\r?\n)?/gm, "");
}

async function readJsonMaybe(p) {
  if (!p) return null;
  try {
    const txt = await readFile(p, "utf8");
    return JSON.parse(stripJsonComments(txt));
  } catch (e) {
    if (e.code === "ENOENT") return null;
    throw new Error(`Failed to parse JSON ${p}: ${e.message}`);
  }
}

// Deep-merge `src` into `dst` in place. Scalars: last-wins (src overwrites).
// Objects: recurse. Arrays: replaced wholesale (documented limitation —
// permissions arrays are merged explicitly in main(), never via this).
function deepMerge(dst, src) {
  for (const [k, v] of Object.entries(src)) {
    if (
      v !== null &&
      typeof v === "object" &&
      !Array.isArray(v) &&
      dst[k] !== null &&
      typeof dst[k] === "object" &&
      !Array.isArray(dst[k])
    ) {
      deepMerge(dst[k], v);
    } else {
      dst[k] = v;
    }
  }
  return dst;
}

function log(...a)   { console.log(...a); }
function verbose(...a){ if (O.verbose) console.error("[verbose]", ...a); }
function die(msg, code = 1) {
  console.error(`error: ${msg}`);
  process.exit(code);
}

// ─────────────────────────── main ───────────────────────────────────────
async function main() {
  // required args
  if (!O.config)    die("--config <path> is required");
  if (!O.packsDir)  die("--packs-dir <path> is required");
  // --packs is optional (empty = no-op); default "" is handled below.

  // M2: empty/whitespace packs => true no-op. split+trim+filter so "" => [].
  const requested = (O.packs || "")
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean);

  if (requested.length === 0) {
    log("No packs requested (--packs empty) — no-op, config untouched.");
    return;
  }

  // discover available packs in packs-dir
  if (!existsSync(O.packsDir)) {
    die(`--packs-dir not found: ${O.packsDir}`);
  }
  const entries = await readdir(O.packsDir);
  const available = entries
    .filter((f) => /^pack-(.+)\.json$/.test(f))
    .map((f) => f.replace(/^pack-/, "").replace(/\.json$/, ""))
    .sort();

  // validate requested against available
  const unknown = requested.filter((n) => !available.includes(n));
  if (unknown.length > 0) {
    die(
      `Unknown pack(s): ${unknown.join(", ")}\n` +
        `Available packs in ${O.packsDir}: ${available.join(", ")}`
    );
  }

  // load target config
  if (!existsSync(O.config)) {
    die(`--config file not found: ${O.config}`);
  }
  const config = await readJsonMaybe(O.config);
  if (!config || typeof config !== "object") {
    die(`Could not parse config as JSON object: ${O.config}`);
  }

  // snapshot for changed-detection (only the keys packs may touch)
  const before = JSON.stringify({
    mcp: config.mcp || {},
    permissions: config.permissions || [],
  });

  // load + merge each requested pack in order.
  verbose(`Merging ${requested.length} pack(s) into ${O.config}:`);
  for (const name of requested) {
    const file = join(O.packsDir, `pack-${name}.json`);
    verbose(`  - ${name} (${file})`);
    const pack = await readJsonMaybe(file); // throws on malformed JSON (parse error)
    if (!pack || typeof pack !== "object") {
      die(`Pack ${name} is not a JSON object: ${file}`);
    }
    // $comment / $* are pack metadata and `install` is the runtime-installer
    // spec (#677) — pack metadata is never merged into the deployed config.
    const reserved = (k) => k === "install" || k.startsWith("$");
    const { mcp, permissions, ...restPack } = Object.fromEntries(
      Object.entries(pack).filter(([k]) => !reserved(k))
    );
    if (Object.keys(restPack).length > 0) deepMerge(config, restPack);
    if (mcp && typeof mcp === "object") {
      // v2 pack fragments are { servers: { name: {...} } }; merge into config.mcp.
      config.mcp = config.mcp || {};
      // Fail-closed (#558): a flip-only pack presumes the base definition
      // exists in the TARGET config. Flipping into a definition-less config
      // creates an inert v2 stub ({disabled:false}, no command/url) that
      // opencode silently ignores. die() here = exit before the single
      // final write, so the target stays byte-unchanged.
      for (const [srv, def] of Object.entries(mcp.servers ?? {})) {
        if (!def || def.disabled !== false) continue;
        const cur = config.mcp?.servers?.[srv];
        const hasCmd = Array.isArray(cur?.command) && cur.command.length > 0;
        const hasUrl = typeof cur?.url === "string" && cur.url.trim() !== "";
        if (!cur || typeof cur !== "object" || (!hasCmd && !hasUrl)) {
          die(`ERROR: pack '${name}' enables '${srv}', but the target config has no full definition for it (missing command/url). The deployed config predates this pack. Re-run setup.sh and answer 'y' to refresh the config, or re-copy deploy/opencode.json.`);
        }
      }
      deepMerge(config.mcp, mcp);
    }
    if (Array.isArray(permissions)) {
      if (!Array.isArray(config.permissions)) config.permissions = [];
      for (const rule of permissions) {
        const idx = config.permissions.findIndex(
          (r) => r && r.action === rule.action && r.resource === rule.resource
        );
        if (idx >= 0) config.permissions[idx] = rule;
        else config.permissions.push(rule);
      }
    }
  }


  const after = JSON.stringify({
    mcp: config.mcp || {},
    permissions: config.permissions || [],
  });

  if (O.dryRun) {
    log(`[DRY-RUN] Would merge ${requested.length} pack(s) into ${O.config}:`);
    log(`  packs: ${requested.join(", ")}`);
    log(`  changed: ${before === after ? "nothing (already merged)" : "yes"}`);
    // list the servers that would be enabled (packs carry disabled: false)
    const enabling = [];
    for (const name of requested) {
      const p = await readJsonMaybe(join(O.packsDir, `pack-${name}.json`));
      for (const [srv, def] of Object.entries(p.mcp?.servers ?? {})) {
        if (def && def.disabled === false) enabling.push(srv);
      }
    }
    log(`  servers that would be enabled: ${enabling.join(", ")}`);
    return;
  }

  // write merged config (2-space indent matches opencode.json style)
  await writeFile(O.config, JSON.stringify(config, null, 2) + "\n", "utf8");
  log(`Merged ${requested.length} pack(s) into ${O.config}:`);
  log(`  packs: ${requested.join(", ")}`);
  log(`  changed: ${before === after ? "nothing (already merged)" : "yes"}`);
}

main().catch((e) => die(e.message || String(e)));
