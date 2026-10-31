#!/usr/bin/env node
// install-assistant-skill (mcp route) — read-only MCP inventory (zero deps).
// Reports every MCP server in the deployed OpenCode config: state, type,
// install model, required env keys (and whether they are set), owning pack.
// Read-only by design: enablement is delegated to `setup.sh --enable-pack`
// (global) or a full v2 per-project entry — never hand-edit global config.
//
// Usage:
//   node inventory.mjs [--json] [--demo] [project-opencode-json]
//
// Config layering (later wins): global (~/.config/opencode/opencode.json,
// honors XDG_CONFIG_HOME) <- $OPENCODE_CONFIG <- [project arg].
//   --demo  run against a built-in fixture (self-check; includes a server
//           with an unset {env:VAR} to prove the missing-key precheck path)
//
// ponytail: static PACK_OF map with a known ceiling — derived from the pack
// files at authoring time; if packs multiply, regenerate rather than trust.

import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join, resolve } from "node:path";

const PACK_OF = {
  "playwright": "playwright",
  "alpha-vantage": "alpha-vantage",
  "nanobanana": "nanobanana",
  "markitdown": "markitdown",
  "docling": "docling",
  "next-devtools": "nextjs",
  "chrome-devtools": "chrome-devtools",
};

const DEMO = {
  mcp: { servers: {
    "playwright": { type: "local", command: ["npx", "-y", "@playwright/mcp@latest"], disabled: true },
    "alpha-vantage": { type: "remote", url: "https://mcp.alphavantage.co/mcp",
      headers: { Authorization: "Bearer {env:ALPHA_VANTAGE_API_KEY}" }, disabled: true },
    "zai-web-search": { type: "remote", url: "https://api.z.ai/api/mcp/web_search_prime/mcp",
      headers: { Authorization: "Bearer {env:ZAI_API_KEY}" }, disabled: false },
  } },
};

function loadIf(path) {
  try { return JSON.parse(readFileSync(path, "utf8")); } catch { return null; }
}

function mergeServers(base, overlay) {
  const out = { ...base };
  for (const [k, v] of Object.entries(overlay || {})) out[k] = v; // v2: atomic per-server replace
  return out;
}

function envKeys(server) {
  const { $comment, ...doc } = server; // $comment prose may cite {env:X} examples — not real refs
  return [...new Set((JSON.stringify(doc).match(/\{env:([A-Z0-9_]+)\}/g) || [])
    .map((s) => s.replace(/\{env:|\}/g, "")))];
}

function installModel(server) {
  if (server.type === "remote") return "remote";
  const cmd = (server.command || []).join(" ");
  if (cmd.includes("npx")) return "npx self-install";
  if (cmd.includes("markitdown") || cmd.includes("docling")) return "pip-hook (setup.sh)";
  return "local";
}

function row(name, s) {
  const keys = envKeys(s);
  const missing = keys.filter((k) => !process.env[k]);
  return {
    name,
    enabled: s.disabled !== true,
    type: s.type || "local",
    install: installModel(s),
    env: keys.map((k) => `${k}=${process.env[k] ? "set" : "MISSING"}`),
    missing,
    pack: PACK_OF[name] || null,
    entry: s,
  };
}

function main() {
  const args = process.argv.slice(2);
  const json = args.includes("--json");
  const demo = args.includes("--demo");
  const projectArg = args.find((a) => !a.startsWith("--"));

  let servers = {};
  if (demo) {
    servers = DEMO.mcp.servers;
  } else {
    const xdg = process.env.XDG_CONFIG_HOME || join(homedir(), ".config");
    const globalCfg = loadIf(join(xdg, "opencode", "opencode.json"));
    if (!globalCfg) {
      console.error(`No global config at ${join(xdg, "opencode", "opencode.json")} — is OpenCode deployed?`);
      process.exit(1);
    }
    servers = globalCfg.mcp?.servers ?? {};
    if (process.env.OPENCODE_CONFIG) {
      const overlayCfg = loadIf(process.env.OPENCODE_CONFIG);
      if (!overlayCfg) {
        // Explicit user override layer: a set-but-unreadable var must never
        // silently degrade to global-only states (wrong enable decisions).
        console.error(`OPENCODE_CONFIG is set but unreadable: ${process.env.OPENCODE_CONFIG}`);
        process.exit(1);
      }
      servers = mergeServers(servers, overlayCfg.mcp?.servers);
    }
    if (projectArg) {
      const proj = loadIf(resolve(projectArg));
      if (!proj) { console.error(`Unreadable project config: ${projectArg}`); process.exit(1); }
      servers = mergeServers(servers, proj.mcp?.servers);
    }
  }

  if (demo) {
    // Hermetic: judge demo keys against a fixed env, not the ambient one,
    // so the documented self-check behaves identically on every machine.
    process.env.ZAI_API_KEY = "demo-set";
    delete process.env.ALPHA_VANTAGE_API_KEY;
  }
  const rows = Object.entries(servers).map(([n, s]) => row(n, s))
    .sort((a, b) => Number(b.enabled) - Number(a.enabled) || a.name.localeCompare(b.name));

  if (json) { console.log(JSON.stringify(rows, null, 2)); return; }

  const pad = (s, n) => String(s).padEnd(n);
  console.log(pad("SERVER", 16) + pad("STATE", 10) + pad("TYPE", 8) + pad("INSTALL", 20) + pad("ENV KEYS", 34) + "PACK");
  for (const r of rows) {
    console.log(pad(r.name, 16) + pad(r.enabled ? "enabled" : "disabled", 10) + pad(r.type, 8)
      + pad(r.install, 20) + pad(r.env.join(",") || "-", 34) + (r.pack || "-"));
  }
  const warnings = rows.filter((r) => !r.enabled && r.missing.length);
  if (warnings.length) {
    console.log("\nPrecheck warnings (disabled, prerequisite missing):");
    for (const w of warnings) console.log(`  ${w.name}: missing ${w.missing.join(", ")} — set before enabling`);
  }
}

main();
