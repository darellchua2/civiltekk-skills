# Route: maintain — inventory, update, prune, remove

Installed entries are deploy artifacts with a manifest system of record —
this route keeps them current and removes them cleanly.

## Inventory ("what's installed?")

```bash
ls .agents/skills/                       # project scope (opencode target)
ls ~/.config/opencode/skills/            # user scope (opencode target)
cat ~/.config/opencode/.skill-manifest.json   # user-scope system of record (all targets)
```

Per-target user dirs: `~/.claude/skills`, `~/.agents/skills`,
`~/.kimi-code/skills`, `~/.kilo/skills`, `~/.zcode/skills`. Report per target
what exists; the manifest tracks what the installer owns.

## Update (re-sync to current source)

```bash
npx github:darellchua2/civiltekk-opencode-claude-skills update
```

Re-copies changed entries for everything the manifest tracks (content-hash
compared — unchanged entries report as such). `update --prune` also removes
manifest-tracked entries whose names left the registry. `update --no-deps`
skips the plugin refresh. A pre-manifest install reports adoption steps —
follow the installer's message, never hand-migrate.

## Remove

```bash
npx github:darellchua2/civiltekk-opencode-claude-skills remove <name>
```

User-scope removal, cleans all installed targets for that entry; required
skills the entry pulled are left alone (they may serve other entries —
remove them explicitly if truly unwanted). Project-scope removal is not a
`remove --project` flag: it rides the preset flow with `--prune` (the
installer errors with that guidance; relay it, don't improvise).

## Honest state

Report outcomes as they are: `updated` / `unchanged` / `missing` /
`registryRemoved` per entry. A failed update stays failed in the report —
never mask it as clean, and never hand-patch an installed copy to force a
green result (fix at source, re-run `update`).
