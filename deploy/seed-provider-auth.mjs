#!/usr/bin/env node
// deploy/seed-provider-auth.mjs
//
// Provider credential seeding CLI (#677) — one node home for the writes that
// used to live in setup.sh shell heredocs:
//   resolve     preset → credential block (+ provider derivation fallback)
//   seed        merge-never-clobber write into ~/.local/share/opencode/auth.json
//   seed-codex  guarded TOML append of the Z.AI provider into ~/.codex/config.toml
//
// Zero external dependencies — Node built-ins only. Mirrors merge-packs.mjs
// conventions: ES module, async main(), camelCase arg parsing, exit codes
// 0 success / 1 bad args or IO.
//
// Secret hygiene: the key is read from the AUTH_KEY env var (never a CLI
// argument — argv is visible in `ps`), matching the #471 python heredoc it
// replaces.
//
// Usage:
//   node seed-provider-auth.mjs resolve \
//     --presets installer/provider-presets.json [--provider zai] \
//     [--models-map ~/.config/opencode/models.json] [--default-map installer/models.default.json]
//   node seed-provider-auth.mjs seed --auth-id zai [--file auth.json] [--dir dir]   # key via AUTH_KEY env
//   node seed-provider-auth.mjs seed-codex [--config ~/.codex/config.toml]          # key NOT needed (env_key indirection)

import { readFile, writeFile, mkdir, appendFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

// ─────────────────────────── arg parsing ────────────────────────────────
const camel = (s) => s.replace(/-([a-z])/g, (_, c) => c.toUpperCase());

function parseArgsCamel(argv) {
  const out = {};
  for (let i = 0; i < argv.length; i++) {
    if (!argv[i].startsWith("--")) continue;
    const key = camel(argv[i].slice(2));
    if (i + 1 < argv.length && !argv[i + 1].startsWith("--")) out[key] = argv[++i];
    else out[key] = true;
  }
  return out;
}

const readJsonMaybe = async (p) => {
  if (!p) return null;
  try {
    return JSON.parse(await readFile(p, "utf8"));
  } catch {
    return null;
  }
};

// ─────────────────────────── resolve ────────────────────────────────────
// Resolves the chosen provider (flag → models-map primary prefix → default
// map) and its credential block (preset name OR any auth_id match).
// Prints ONE JSON line: {"provider":"<name>","credential":{...}|null}
async function cmdResolve(opts) {
  let provider = opts.provider || "";
  if (!provider) {
    const map = (await readJsonMaybe(opts.modelsMap)) || (await readJsonMaybe(opts.defaultMap));
    const primary = map && (map.primary || (map.tiers && map.tiers.primary));
    if (primary) provider = String(primary).split("/")[0];
  }
  let credential = null;
  if (provider && opts.presets && existsSync(opts.presets)) {
    const pp = await readJsonMaybe(opts.presets);
    const presets = (pp && pp.presets) || pp || {};
    for (const [name, p] of Object.entries(presets)) {
      const c = p && p.credential;
      if (c && (p.primary || c.auth_ids) && (name === provider || (c.auth_ids || []).includes(provider))) {
        credential = c;
        break;
      }
    }
  }
  console.log(JSON.stringify({ provider, credential }));
}

// ─────────────────────────── seed ───────────────────────────────────────
// Merge-never-clobber auth.json write. A corrupt file is PARKED (.corrupt.bak),
// never silently replaced (#471 review). Output mode 0600 — API keys at rest.
async function cmdSeed(opts) {
  const authId = String(opts.authId || "").trim();
  const key = String(process.env.AUTH_KEY || "").trim();
  if (!authId || !key) {
    console.error("seed: --auth-id and AUTH_KEY env are required");
    process.exit(1);
  }
  const dir = opts.dir || join(process.env.XDG_DATA_HOME || join(homedir(), ".local", "share"), "opencode");
  const file = opts.file || join(dir, "auth.json");
  let auth = {};
  try {
    const loaded = JSON.parse(await readFile(file, "utf8"));
    if (loaded && typeof loaded === "object" && !Array.isArray(loaded)) auth = loaded;
    else throw new Error("auth.json is not an object");
  } catch (e) {
    if (e.code === "ENOENT") {
      // fresh install — nothing to merge
    } else {
      // Merge-never-clobber must hold even for corrupt files (#471 review):
      // park the unparseable file loudly, start fresh.
      const backup = `${file}.corrupt.bak`;
      try {
        const { rename } = await import("node:fs/promises");
        await rename(file, backup);
        console.error(`  warning: auth.json was unparseable — moved to ${backup}`);
      } catch {}
    }
  }
  auth[authId] = { type: "api", key };
  await mkdir(dir, { recursive: true });
  await writeFile(file, JSON.stringify(auth, null, 2) + "\n", { mode: 0o600 });
  try {
    const { chmod } = await import("node:fs/promises");
    await chmod(file, 0o600); // in case the file pre-existed with looser perms
  } catch {}
  console.log("  auth.json providers: " + Object.keys(auth).sort().join(", "));
}

// ─────────────────────────── seed-codex ─────────────────────────────────
// Guarded append of the Z.AI provider block — never rewrites user content,
// never sets the global default model (activation is opt-in via
// `codex --profile zai`). Appending a table that already exists is a TOML
// parse error, so BOTH section shapes skip with a note instead of corrupting
// the file.
const CODEX_BLOCK = `
# --- Z.AI provider (added by opencode setup, #573) ---
# codex supports wire_api = "responses" only, so base_url points at Z.AI's
# OpenAI Responses endpoint. Source of truth for the endpoint (verified
# 2026-09-26): Z.AI devpack docs "Coding Endpoint" table lists
#   Protocol "OpenAI Responses" -> base https://api.z.ai/api/v1
# (https://docs.z.ai/devpack/tool/others). NOT the PAAS chat-completions
# base pi uses (api/paas/v4 speaks openai-completions, not Responses).
# If Z.AI revises this, update here + tests + README together.
# env_key names the env var codex reads per invocation - the key itself is
# never stored in this file.
[model_providers.zai]
name = "Z.AI"
base_url = "https://api.z.ai/api/v1"
env_key = "ZAI_API_KEY"

# Opt-in activation: \`codex --profile zai\` (global default model untouched).
[profiles.zai]
model_provider = "zai"
model = "glm-5.3"
`;

async function cmdSeedCodex(opts) {
  const file = opts.config || join(homedir(), ".codex", "config.toml");
  let current = "";
  try {
    current = await readFile(file, "utf8");
  } catch (e) {
    if (e.code !== "ENOENT") {
      console.error(`seed-codex: cannot read ${file}: ${e.message}`);
      process.exit(1);
    }
  }
  if (/^\[model_providers\.zai\]/m.test(current) || /^model_providers\.zai\./m.test(current)) {
    console.log(`codex config already defines [model_providers.zai] - leaving ${file} untouched`);
    return;
  }
  if (/^\[profiles\.zai\]/m.test(current) || /^profiles\.zai\./m.test(current)) {
    console.log(`codex config already defines [profiles.zai] - leaving ${file} untouched`);
    return;
  }
  await mkdir(join(file, ".."), { recursive: true });
  await appendFile(file, CODEX_BLOCK);
  console.log(`codex: zai provider appended to ${file} (activate: codex --profile zai)`);
}

// ─────────────────────────── dispatch ───────────────────────────────────
async function main() {
  const cmd = process.argv[2];
  const opts = parseArgsCamel(process.argv.slice(3));
  switch (cmd) {
    case "resolve": return cmdResolve(opts);
    case "seed": return cmdSeed(opts);
    case "seed-codex": return cmdSeedCodex(opts);
    default:
      console.error("usage: seed-provider-auth.mjs <resolve|seed|seed-codex> [opts]");
      process.exit(2);
  }
}

main().catch((e) => {
  console.error(`seed-provider-auth error: ${e && e.message ? e.message : e}`);
  process.exit(1);
});
