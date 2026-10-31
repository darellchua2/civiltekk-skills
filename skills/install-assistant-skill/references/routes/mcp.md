# Route: MCP

**Load when:** the task enables or diagnoses OpenCode MCP servers — inventory, precheck, `--enable-pack` or per-project enable, verify. **Skip when:** installing catalog skills/subagents (Route: CATALOG).



Interactive assistant for turning OpenCode MCP servers on — safely. I never
guess: I inventory what ships, precheck what each server needs to actually
start, guide the enable, and verify it connected. I am the guided front door;
`opencode-repo-setup-skill` is the per-project plumbing reference underneath (external sibling).

## What I do (4 steps — never skip step 2)

### Step 1 — Inventory

Run the bundled read-only inventory (zero deps, Node):

```bash
node scripts/inventory.mjs            # human table
node scripts/inventory.mjs --json    # machine output
```

It reads the **deployed global config** (`~/.config/opencode/opencode.json`,
honoring `$XDG_CONFIG_HOME`), overlays `$OPENCODE_CONFIG` when set (it layers
between global and project per v2 docs), plus an optional project
`opencode.json` path argument. For every MCP server it reports: enabled state,
type (local/remote), install model (npx self-install / remote / pip-hook),
referenced `{env:VAR}` keys and whether they are set, and the owning provider
pack (static map; ceiling noted in the script).

Present the table to the user before touching anything.

### Step 2 — Precheck (warn, don't enable, on a missing prerequisite)

| Server(s) | Needs before enable |
|-----------|---------------------|
| `playwright`, `chrome-devtools` | Chrome/Chromium installed (`google-chrome`/`chromium` on PATH; else advise `npx playwright install chromium` for playwright) |
| `alpha-vantage` | `ALPHA_VANTAGE_API_KEY` env var (free tier exists) |
| `nanobanana` | `GEMINI_API_KEY` env var (free tier exists) |
| `zai-web-reader`, `zai-web-search` | `ZAI_API_KEY` env var |
| `markitdown` | python3 + pip (setup.sh pip-installs `markitdown-mcp`; small) |
| `docling` | python3 + pip + ~3-4 GB model deps — ask consent first |
| `atlassian` | a browser for first-use OAuth; headless/CI: skip |
| `codegraph`, `next-devtools` | nothing beyond node/npx |

The inventory already flags missing `{env:VAR}` keys — surface them as the
reason NOT to enable, and offer to proceed anyway only if the user insists.

### Step 3 — Enable (two scopes; pick by where the user wants it)

- **Global** (only when cwd is the configurator repo
  `civiltekk-opencode-claude-skills`): run
  `./deploy/setup.sh --enable-pack <pack>` — the deploy script owns the global
  config; never hand-edit `~/.config/opencode/opencode.json`. (#677: each
  pack's JSON `install` block drives the runtime install too — new packs are
  data-only. Interactive alternative: the `civiltekk-setup` TUI wizard's packs
  step shows each pack's install command before anything runs.)
- **Per-project** (any project): write a **full v2 entry** into the project's
  `opencode.json` — v2 replaces `mcp.servers.<name>` atomically, so a bare
  `{"disabled": false}` stub is inert. Copy the full entry from the deployed
  global config (inventory shows it with `--json`), set `"disabled": false`,
  keep `type`/`command`/`url`/`headers`/`environment` intact.

### Step 4 — Verify

```bash
opencode mcp list
```

The server must appear connected. If it fails to start: re-run the inventory,
re-check the precheck table (a missing key or missing browser is the usual
cause), and report the exact gap — do not iterate blind edits on config.

## Capability bindings

Interactive prompts to the user during selection.
- OpenCode: `question` tool (one question, 2-4 options, multiple allowed)
- Claude Code: `AskUserQuestion` multiple-choice tool
- Other/none: number the options in a plain reply and wait for the user's pick

Requires bash (git-bash/WSL on Windows) for the enable/verify shell steps; the
inventory itself is plain Node and runs anywhere Node runs.

## House rules this skill enforces

- Atlassian is **disabled globally by default** and must not be force-enabled
  globally (project opt-in only — AGENTS.md MCP routing).
- Remote servers with OAuth-primary upstreams (e.g. alpha-vantage) ship
  `"oauth": false` + static Bearer headers; if the upstream rejects the key,
  report it — pilot-verify note lives in the pack `$comment`.
- The Autodesk precedent (#554): never advise enabling an MCP whose endpoints
  are not verifiable from the vendor's own docs.

## Self-check

```bash
node scripts/inventory.mjs --demo
```

Runs the inventory against a built-in 3-server fixture (includes one server
with an `{env:...}` key treated as unset — the demo pins its own env, so the
result is identical on every machine) and must flag the missing key as a
precheck warning. No external paths needed.
