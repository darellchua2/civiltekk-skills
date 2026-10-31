# Route: install — describe, preview, add, verify

The only mutating route. Sequence is fixed: describe → dry-run → scope →
add → verify. Never skip the dry-run.

## 1. Describe

```bash
npx github:darellchua2/civiltekk-opencode-claude-skills --describe <name>
```

Confirms the name resolves and shows the `requiresSkills` set the install
will pull transitively. Unknown name → route `find` first.

## 2. Dry-run (mandatory)

```bash
npx github:darellchua2/civiltekk-opencode-claude-skills add <name> --project . --dry-run
```

Show the resolved manifest — entry, dep set, target paths, warnings — and
get user confirmation before the real add. `--no-deps` only when the user
explicitly asks for it (it installs the bare entry and skips the mapped
plugin artifacts — say that when honoring it).

## 3. Scope (project is the default)

| Scope | Command | Consent |
|-------|---------|---------|
| Project (default) | `add <name> --project .` | covered by dry-run confirm |
| Project, other harness | `add <name> --project . --target claude\|agents\|kimi\|kilo\|zcode\|copilot` | same; `--target auto` probes installed harnesses |
| Global (user scope) | `add <name>` (no `--project`) | ask explicitly — touches `~/.config/opencode/skills`, `~/.claude/skills`, `~/.agents/skills` etc. per target |

Per-target project destinations: opencode `.agents/skills/` +
`.opencode/agents/`, kimi `.kimi-code/`, kilo `.kilo/`, copilot skills
`.github/skills/` (agents `.claude/agents/`). claude and zcode are
user-scope only — `--project` with them degrades to the opencode project
dirs and the installer prints a "no project destination" note. Targets with
transform modes (claude/copilot translate agents) are handled by the
installer.

## 4. Add

Run the confirmed command without `--dry-run`. Plugin artifacts mapped to the
entry's deps ship automatically — no separate step. Report the installer's
written-path output verbatim.

## 5. Verify

```bash
ls <dest-dir>/<name>/SKILL.md   # project: .agents/skills/<name>/SKILL.md (opencode target)
```

Check every path the installer printed exists. Missing file → re-run
`--dry-run`, compare, report the gap — do not hand-create files. Note that a
fresh session may be needed before the harness discovers the new entry.

## 6. AGENTS.md wire-up (optional, ask once)

Offer: "Add a 3-line routing block to this project's AGENTS.md so installs
default through this assistant?" On consent:

- Append-only, own heading, end of file — never modify, reorder, or reformat
  existing lines.
- First grep the file for an existing install-routing rule (e.g. a heading or
  line about skill installation) — found → report it and skip, don't rewrite.
- Block text (verbatim):

```markdown
## Skill & Agent Installation

Route skill/subagent lookup, install, update, and removal through the
`install-assistant-skill` skill (`.agents/skills/install-assistant-skill/`)
— dry-run first, never hand-copy from a skill repo. Before authoring a new
skill or agent, search the installed catalog first; a match may already
exist. Never hand-edit installed copies — fix at source and run the
installer's `update`.
```

Declined → done; the skill's description routing still works without it.
