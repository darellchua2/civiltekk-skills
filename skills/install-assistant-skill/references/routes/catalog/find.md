# Route: find — catalog search and ranking

Resolve "is there a skill for X?" against the live catalog. Read-only until
the user asks to install.

## 1. Pull the catalog

```bash
# Any project (network round-trip):
npx github:darellchua2/civiltekk-opencode-claude-skills --list categories   # categories + counts
npx github:darellchua2/civiltekk-opencode-claude-skills --list skills       # JSON: name + description (+category)
npx github:darellchua2/civiltekk-opencode-claude-skills --list agents       # JSON: stem + description (+category, tier)
# Inside the configurator repo (no network):
node installer/init.mjs --list skills
node installer/init.mjs --list agents
```

Start from `--list categories` when the ask is broad ("something for
review"), else search the full `--list skills` / `--list agents` JSON.

## 2. Match by intent, not substring

Grep/scan the JSON `description` fields for the user's task vocabulary
("review before commit" → review/quality categories; "write tests" →
testing). Keywords are intent signals: match meaning, reject accidental
substrings. Weight agents by `category` and `tier` when the ask is about
who does the work rather than what knowledge applies.

## 3. Inspect candidates

```bash
npx github:darellchua2/civiltekk-opencode-claude-skills --describe <name>   # full entry + requiresSkills + requiredBy
npx github:darellchua2/civiltekk-opencode-claude-skills --expand <preset>   # full resolved install set for a bundle
```

`--describe` shows the dependency set the install will pull — surface it in
the offer so the user sees the blast radius before anything runs.

## 4. Rank and offer

Present the top 2–3 matches: name, one-line "why this fits", and (from
`--describe`) the dep set each pulls. Then offer the install:

- OpenCode: `question` tool — "Install `<name>` into this project?" (Install
  project / Install global / Just showing options)
- Claude Code: `AskUserQuestion`, same options
- Other/none: number the options in a plain reply

"Yes" → route `install` (`references/install.md`). Headless/CI: present the
matches and stop — never install without an explicit ask.

## Output contract

Every find run reports: query interpretation, matches considered, top picks
with fit rationale, dep sets, and the offer made (or the headless stop).
