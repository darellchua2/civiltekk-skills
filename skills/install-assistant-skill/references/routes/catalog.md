# Route: CATALOG

**Load when:** the task finds, installs, updates, or removes civiltekk catalog skills/subagents (or answers "is there a skill for X"). **Skip when:** MCP server enablement (Route: MCP). **Detail dir:** `catalog/` — `find.md`, `install.md`, `maintain.md` load per the route table below; never all three.



Guided front door to the civiltekk catalog (skills + subagents; plugins ship
automatically as dependency artifacts). The npx installer is the engine — I
never hand-copy files or resolve dependencies myself; I route intent to the
right installer surface and enforce its safety rails. The MCP counterpart is the `mcp` route of this router.

## Route detection (explicit > inferred > ask-once)

| Ask | Route |
|-----|-------|
| "is there a skill for X", "find a skill", "what skills exist", "recommend" | `find` — load `catalog/find.md` |
| "install skill X", "add subagent Y to this project", "use the installer" | `install` — load `catalog/install.md` |
| "what's installed", "update my skills", "remove skill X" | `maintain` — load `catalog/maintain.md` |
| "set up the whole stack", "full install", "guided setup" | **Full-stack route (#677)** — do NOT install anything: point at the deploy surface — `civiltekk-setup` (interactive TUI wizard via menu option 0, or flags like `--quick --yes --enable-pack <packs>`); only skills/subagents stay this skill's job |
| Invoked by handle (`@install-assistant-skill` / `/install-assistant-skill`) or by either former handle | fast path — run the tree immediately; classify by content; bare ask defaults to `find` |
| Ambiguous ("set me up with X") | ask once, then route — one ask per run |

Find often chains into install ("yes, add it") and install into maintain —
re-enter a route by re-reading its file; never hold all three in context.

## Side files (load rules)

| Read | When | Use |
|------|------|-----|
| `catalog/find.md` | route `find` | Catalog search: `--list` read modes, `--describe`, `--expand` presets, in-repo shortcut, ranking + offer |
| `catalog/install.md` | route `install` | The only mutating route: describe → dry-run → scope choice → add → verify; AGENTS.md wire-up block |
| `catalog/maintain.md` | route `maintain` | Inventory, `update`, `update --prune`, `remove`; honest state reporting |

The detail files carry VALUES (commands, flags, block text); the router carries the shared consent spine.

## Shared invariants (all routes)

- `--dry-run` before every write; show the resolved set (the entry + its
  transitive `requiresSkills`) to the user before the real `add` (router consent spine).
- `--no-deps` only on an explicit user ask — never proactively.
- Global (user-scope) installs require consent; project scope is the default.
- Never hand-edit an installed skill copy — fix at the source repo, then
  `update`. Installed files are deploy artifacts, not working files.
- Report exact installer errors verbatim; no blind retries, no invented flags.

## Capability bindings

Interactive prompts during route work.
- OpenCode: `question` tool (one question, 2-4 options)
- Claude Code: `AskUserQuestion` multiple-choice tool
- Other/none: number the options in a plain reply and wait for the pick

Requires bash (git-bash/WSL on Windows) for the npx/git steps; Node is
guaranteed wherever the installer runs.

## Boundaries

- MCP server enablement → the `mcp` route of this router (different config
  surface; installer `--list mcps` is read-only triage, not enabling).
- Authoring a new skill/agent → `civiltekk-opencode-creation-skill`; search
  the catalog first (this route, `find`) so nothing is authored twice.
- Harness detection / cross-harness parity setup →
  `civiltekk-coding-harness-setup-skill`; `--target` here only picks the
  install destination.
- I am a skill, invoked via the skill tool or my handles — not a subagent;
  no `task` delegation.
