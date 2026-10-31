---
name: install-assistant-skill
description: >-
  Guided install assistant — one entry point for MCP servers (inventory,
  precheck, --enable-pack or per-project enable, verify) and the civiltekk
  catalog (find, install with mandatory dry-run + consent, update, remove).
  Routes each install task to the right specialist route. Never auto-installs.
license: Apache-2.0
compatibility: opencode
metadata:
  harness: "opencode"
category: Configuration
---

# Install Assistant Router

One entry point for "install/enable X" tasks. Identify the surface, run only
the matched route's file, and follow it. Consent is the spine: dry-run → show
the resolved set → user consent → apply → verify. Never auto-install.

Provenance: consolidated from mcp-install-assistant-skill and
civiltekk-install-assistant (#691); the catalog route's find/install/maintain
values files predate it (#657 lineage in route files).

## Routes (load exactly one)

| Task | Route | Read | Skip-when |
|------|-------|------|-----------|
| Enable/diagnose MCP servers (packs, keys, browsers) | `mcp` | `references/routes/mcp.md` | catalog skills → catalog |
| Find/install/update/remove catalog skills + subagents | `catalog` | `references/routes/catalog.md` | MCP servers → mcp |

Route files open with their own **Load when / Skip when** lines; the catalog
route's detail files (`catalog/find|install|maintain.md`) load per its own
table — never all three.

## Consent spine (both routes)

- Dry-run before every write; show the resolved set (entry + transitive
  requirements) before the real add/enable.
- Global (user-scope) changes require consent; project scope is the default.
- `--no-deps` only on an explicit user ask — never proactively.
- Verify after applying (`opencode mcp list` / installer listing); report
  exact errors verbatim — no blind retries, no invented flags.
- Never hand-edit installed copies or global config — fix at the source repo,
  then `update`; the deploy script owns global config.

## Capability bindings

Interactive selection prompts: OpenCode — `question` tool (one question,
2–4 options, multiple allowed). Claude Code — `AskUserQuestion`. Other/none —
number the options in a plain reply and wait for the pick. Requires bash
(git-bash/WSL on Windows) for enable/verify steps; the inventory is plain
Node.

## Hard rules

- Atlassian ships disabled globally and must not be force-enabled globally
  (project opt-in only).
- Never advise enabling an MCP whose endpoints are not verifiable from the
  vendor's own docs (the Autodesk precedent, #554).
- Full-stack setup requests are a pointer, not an install: route to the
  deploy surface (`civiltekk-setup`); only the catalog route installs skills.
- Each route file owns its detail; this router never restates it.

## Gates

- Zero-preload: only the matched route file (+ the catalog route's named
  detail file) enters context.
- Report shape complete: what changed, where (scope), verification output,
  skipped items and why.
