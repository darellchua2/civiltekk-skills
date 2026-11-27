# PLAN: Pin built-in opencode.browser plugin as enabled by default

**Branch**: feat/705
**Issue**: https://github.com/darellchua2/civiltekk-skills/issues/705
**Base**: dev

## Acceptance Criteria
- [ ] `deploy/opencode.json` has a `plugins` array containing `"opencode.browser"`, and is still valid standard JSON with no comments.
- [ ] `plugins/README.md` states that the entry pins an already-default-on built-in, changes nothing on current OpenCode, and how to turn the browser off.
- [ ] On OpenCode v2.4.2, a config carrying the entry loads with `opencode.browser` still `active` and no plugin load error for it.
- [ ] No other file needs a change for the pin (skill/agent/MCP counts, `installer/registry.json`, `deploy/setup.ps1`).
- [ ] Companion: `references/opencode.md` no longer presents "appears in the catalog with no desktop attached" as current behaviour; states the v2.4 rule with its source; keeps the probe rule.
- [ ] Existing CI guard tests that parse `deploy/opencode.json` still pass.

## Dependency & Consumer Map

_Before writing steps, list each touched file/module and who consumes it. Use `codegraph_callers` (code) or `tofu graph` + grep (IaC)._

| Node (file/module) | Depends on (must precede) | Consumers (who depends on this) | Change risk |
|---------------------|---------------------------|---------------------------------|-------------|
| `deploy/opencode.json` (`plugins`) | — | `deploy/setup.sh:2924` (config copy into the global `opencode.json`); the deploy-time writers of the deployed file, each of which parses, edits and re-serialises the same object (`installer/resolve-models.mjs:72,469`; `deploy/apply-skill-profile.mjs:75,109,151`; `deploy/merge-packs.mjs:85,242`); strict-JSON parsers in `tests/test_astra_context_override.bats`, `tests/skill_profiles.bats`, `tests/test_mcp_count_consistency.bats`; the OpenCode v2 loader at boot. `installer/init.mjs` reads this file at :417,:741,:1176,:1993 but only `mcp.servers`. | low |
| `tests/test_browser_plugin_pin.bats` (new) | the row above | CI loop `.github/workflows/release.yml:63-69` | low (new file) |
| `plugins/README.md` (one new section) | the first row | Readers; `deploy_plugins()` copies it beside the plugins into `~/.config/opencode/plugins/`. No test reads it. | low |
| `skills/browser-fallback-skill/references/opencode.md` (one entry) | — | `skills/browser-fallback-skill/SKILL.md` (load-rule table); per-skill `npx … add` installs copy the directory. `installer/registry.json` derives the skill's entry from frontmatter only (no file hashes). No test reads it. | low |

Commands behind the consumer claims (run at Steps 5 and 6 in the worktree): `grep -rnE '\.plugins\b|\["plugins"\]|plugins:\s' installer/*.mjs deploy/*.mjs deploy/*.sh deploy/*.ps1 tests/*.bats` (every hit is the selection list of local plugin *files*, a different thing that shares the name; nothing reads the config key); `grep -nE 'JSON\.parse\(|JSON\.stringify\(' installer/resolve-models.mjs deploy/apply-skill-profile.mjs deploy/merge-packs.mjs`; `grep -n 'opencode\.json' deploy/setup.ps1` (no hits: the Windows script does not deploy the template); `grep -rln 'plugins/README\|references/opencode.md' tests/` (no hits).

## Implementation Phases

_Every step MUST be atomic and carry rationale. Reject any step missing a "Why"._

### Canonical step format
- [ ] **N.M** <single atomic action — verb + target + outcome>
    — **Why:** <what this unblocks / why it must precede others>
    — **Done when:** <objective, checkable completion signal>
    — **Consumers affected:** <who depends on this; none if N/A>

### Phase 1: Pin the built-in in the shipped config and prove the deploy pipeline keeps it
- [ ] **1.1** Set `"plugins": ["opencode.browser"]` in `deploy/opencode.json` (the `plugins` line), leaving every other key byte-untouched.
    — **Why:** This is the ticket's deliverable and the single source the setup flow deploys from. The entry is an enablement directive for a built-in that is on by default today, so it changes nothing on v2.4.2 and keeps the browser on if a later release makes it opt-in.
    — **Done when:** `node -e 'const p=require("./deploy/opencode.json").plugins; process.exit(JSON.stringify(p)===JSON.stringify(["opencode.browser"])?0:1)'` exits 0; `jq . deploy/opencode.json > /dev/null` and `python3 -c 'import json; json.load(open("deploy/opencode.json"))'` exit 0; `git diff --numstat -- deploy/opencode.json` prints `1 1`.
    — **Consumers affected:** User-space deployments (`deploy/setup.sh` copy step) and the OpenCode loader. No behaviour change on current OpenCode.
- [ ] **1.2** Add `tests/test_browser_plugin_pin.bats`: assert the shipped file carries the pin and no `-opencode.browser` entry under a strict `JSON.parse`; assert the pin survives `installer/resolve-models.mjs` (fresh-copy path), `deploy/apply-skill-profile.mjs` and `deploy/merge-packs.mjs` run against `mktemp -d` copies; include the helper's negative fixture (a failing writer and a dropped pin must both fail).
    — **Why:** The pin is plain data that three deploy-time writers pass through, so nothing else would fail if a rewrite dropped it or an edit reverted it, and the ticket's point is that the default stays on. The negative fixture keeps the survival tests from passing on a no-op.
    — **Done when:** `bats tests/test_browser_plugin_pin.bats` reports 5 ok, 0 not ok; removing the pin from a scratch copy of the shipped file makes the first test report `not ok`.
    — **Consumers affected:** CI (`.github/workflows/release.yml:63-69`).
- [ ] **1.3** Verify on the installed OpenCode v2.4.2, against the running shared service and with the user's global config untouched, that the shipped file loads with `opencode.browser` active and that the directive form is honoured for this ID: copy the edited `deploy/opencode.json` into a scratch location and read `GET /api/plugin?location[directory]=<that dir>` until the list is non-empty; read the same for two control locations, `{"plugins":["-opencode.browser"]}` and an ID the build cannot know; then delete the `project` rows keyed by those directories and remove the scratch dirs.
    — **Why:** Acceptance criterion 3 is a property of the OpenCode loader, not of this repo's files, so it needs a runtime check. The controls separate "directive honoured" from "entry ignored" and record what an older build does with an unknown ID. The `project` rows are removed because OpenCode never garbage-collects them and a dangling path breaks `opencode reload`.
    — **Done when:** the shipped-file location reports `opencode.browser` with state `{"status":"active"}`; the `-opencode.browser` location has no `opencode.browser` entry (one fewer than the shipped-file location); the unknown-ID location reports the same entry count as the shipped-file location with `opencode.browser` active; the service log gains no line about a plugin load failure; `SELECT COUNT(*) FROM project` equals its value before the check; the scratch dirs are gone.
    — **Consumers affected:** None. No repo file changes; the user's global config and database end as they began.

### Phase 2: Document the pin
- [ ] **2.1** Add a short "Built-in plugin directives in `opencode.json`" section to `plugins/README.md`, between the naming-convention rules and "Plugin notes": the entry is a directive, not a package; `opencode.browser` is on by default and the entry changes nothing on current OpenCode (measured `active` on v2.4.2 with an empty array); the tools are listed only while an OpenCode desktop app (2.4.0 or later) holds the session's pane, so terminal sessions never get them; browser calls issue no per-operation prompts and the desktop browser keeps sign-ins in one profile; the two off switches (`-opencode.browser`, or a `browser` deny rule); and that the entry reaches fresh setups and re-deploys that accept the config overwrite.
    — **Why:** The JSON cannot carry the rationale (strict parsers in CI), and without it the entry reads as dead config that invites removal, or as something that gives terminal sessions a browser, which it does not.
    — **Done when:** `grep -c '^## Built-in plugin directives' plugins/README.md` prints 1; `grep -c "holds the session's pane" plugins/README.md` is at least 1; `grep -c -- '-opencode.browser' plugins/README.md` is at least 1; `grep -ci 'changes nothing' plugins/README.md` is at least 1; `bats tests/test_astra_context_override.bats` still passes.
    — **Consumers affected:** Readers of `plugins/README.md`.

### Phase 3: Companion — state the current catalog rule in the browser-fallback reference
- [ ] **3.1** Rewrite the `browser.*` entry under "Managed toolset" in `skills/browser-fallback-skill/references/opencode.md`: keep the quote and citation; replace "Appears in the session catalog even when no desktop app is attached; presence ≠ connection" with the version-dependent rule (observed 2026-09-28 on an earlier v2 build: listed with no desktop attached; since v2.4.0: listed only while a desktop app holds the session's pane, citing anomalyco/opencode#65969; observed 2026-11-27 on CLI v2.4.2: plugin active, no `browser` namespace in a terminal session) and one clause that presence is still not connection because a pane can be taken away mid-session. Leave the Probe, Mutating, Disconnect, Fallback and Interface sections byte-untouched.
    — **Why:** The current sentence is false on v2.4 and would contradict the new README section in the same repo; the file's own load rule says to re-verify on OpenCode upgrades. The probe rule stays because attachment can change mid-session.
    — **Done when:** `grep -q 'even when no desktop app is attached' skills/browser-fallback-skill/references/opencode.md` exits 1; `grep -q '65969' skills/browser-fallback-skill/references/opencode.md` exits 0; `diff <(git show HEAD:skills/browser-fallback-skill/references/opencode.md | sed -n '/^## Probe/,$p') <(sed -n '/^## Probe/,$p' skills/browser-fallback-skill/references/opencode.md)` prints nothing; `git diff --numstat` lists that one file; `node installer/build-registry.mjs --check` exits 0.
    — **Consumers affected:** Sessions that load `browser-fallback-skill`.

## Technical Notes

Facts verified at Steps 5 and 6 against the installed OpenCode CLI `v2.4.2` (2026-11-27) and the V2 docs at opencode.ai.

- **Config shape.** The current key is `plugins` (singular `plugin` is deprecated in `https://opencode.ai/config.json`). Items are package names, local directories, `{ "package", "options" }` objects, or enablement directives. Directives are processed in order; `-id` disables, a later `id` re-enables, `*` and `.*` are wildcards. Plugin arrays from the config layers apply lowest to highest precedence, so a project `plugins` entry wins over the global file (https://opencode.ai/docs/plugins/ § Control).
- **What the entry does not do.** It gives terminal sessions nothing. "An agent lists the browser tools only while a desktop holds its session's pane" (anomalyco/opencode#65969, in v2.4.2). Observed 2026-11-27: a terminal session on CLI v2.4.2 had no `browser` namespace while the plugin was `active`. The browser itself needs the desktop app 2.4.0 or later; the machine used for verification had 2.2.7 installed with a 2.3.2 update pending.
- **No prompts.** "Browser operations do not issue individual permission prompts"; "a `browser` deny rule with resource `*` removes the browser catalog" (https://opencode.ai/docs/tools/ § Browser).
- **Measured on the real service, v2.4.2, global `plugins: []`.** Scratch project locations: `["opencode.browser"]` → 109 entries, `opencode.browser` `{"status":"active"}`; `["-opencode.browser"]` → 108 entries, no `opencode.browser`. The service log gained only its standing `ignored unsupported agent fields` warnings (deployed agent files, unrelated to plugins).
- **Verification method.** `GET /api/plugin` takes an object-valued `location` (`?location[directory]=<path>`); `?directory=` is ignored and the short-lived registry of a fresh location returns `data: []` on the first call, so retry. A throwaway `opencode api --standalone` server is useless here: it answers before plugins load, so the pin, a disable directive and a non-existent package name all give an empty list and zero log lines. Booting a scratch location adds one `project` row per directory (the `worktree` column holds the directory); delete those rows in the same step.
- **Not set.** `experimental.browser_stream_tunnel` is in the published schema and occurs zero times in the v2.4.2 binary.
- **Strict JSON.** `//` comments break the bats (`JSON.parse`) and Python (`json.load`) readers of `deploy/opencode.json`; keep the file comment-free as it is today.
- **Scope.** In: the pin, its README note, the guard test, the reference entry. Out: browser permission guardrails, any npm browser package, the `browser_stream_tunnel` flag.
- **Doc note constraint.** The README states behaviour and points at `deploy/opencode.json` and the test; it does not restate the config beyond the one entry.
- **AC coverage.** AC 1 → step 1.1; AC 2 → step 2.1; AC 3 → step 1.3; AC 5 → step 3.1; AC 6 → step 1.2 plus the ticket exit gate's bats loop. AC 4 is a nothing-else-changes criterion: it follows from 1.1 being a single-key edit and is checked at the ticket exit gate, where `git diff --name-only origin/dev...feat/705` must list only the four planned files plus this PLAN and `node installer/build-registry.mjs --check` must exit 0.
- **Test isolation.** Tests copy into `mktemp -d` and pass explicit `--config`/`--config-dest` paths; nothing may write under the real `$HOME`. One assertion per line in bats (`a && b && c` enforces only `c`); no backticks inside `[[ ]]` assertion strings.
- **Gate commands mirror CI** (`.github/workflows/release.yml`): `node installer/build-registry.mjs --check`; `node --check installer/init.mjs installer/source.mjs installer/build-site.mjs`; `jq . package.json`; `jq . deploy/opencode.json`; `bash -n deploy/setup.sh`; `bats tests/<file>` for each file. No typecheck or build target exists in this repo (`package.json` has no scripts).
- **Test runner.** CI runs the vendored `tests/lib/bats-core` (version 1.13.0), the same version as the bats on PATH here. The submodule is not checked out in this worktree; local gates use the PATH bats.
- **Commits.** Phase commits follow the executor's format, `<type>(<scope>): implement Phase N — <summary>`: Phase 1 `feat(config)`, Phase 2 `docs(plugins)`, Phase 3 `docs(browser-fallback)`. Phase 1 runs the full gate because it changes `deploy/opencode.json`, a deploy config node with consumers in `deploy/setup.sh` and in three writers across `deploy/` and `installer/`, and adds a test; the ticket exit gate is full.
- **Existing installs.** Re-running setup keeps an existing config by default (overwrite prompt defaults to "n"; `deploy/setup.sh:2897-2905`), so the entry reaches fresh setups and re-deploys that accept the overwrite. A kept config loses nothing: the built-in is on by default.

## Dependencies
- None. Not blocked by other tickets.

## Risks & Mitigation
- **The entry is redundant today and reads as dead config.** Mitigation: the README section states what it is for, and `tests/test_browser_plugin_pin.bats` fails if the pin is removed or a deploy-time writer drops it.
- **Mistaken for a terminal browser.** It is not one. Mitigation: the README and the reference both state the desktop-pane rule.
- **Security posture.** This ticket does not change it: the browser is already on by default upstream and browser calls do not prompt. The README names both off switches so an operator who wants it off in a project has the one-liner.
- **Desktop app version.** Operators on a desktop app older than 2.4.0 see no browser tools with or without the pin. Documented; not this repo's to fix.
- **Older OpenCode builds without the built-in.** Step 1.3 records what the loader does with an ID it cannot know; the result is written into this section at execution time.

## Trace
LOG Step 5: ticket re-validated against origin/dev 1d6505c1. The `plugins` line is still deploy/opencode.json:444 after #704 (which touched only the providers block). deploy/setup.ps1 never references opencode.json. installer/registry.json holds frontmatter-derived fields only for browser-fallback-skill. No adoptable PLAN draft; no BRD/SRS draft.
LOG Step 5: runtime check method established on the real v2.4.2 service with scratch project locations (pin: 109 entries, browser active; -opencode.browser: 108 entries, browser absent). The two project rows the check created were deleted (dependents 0; project table back to 70 rows). Throwaway --standalone servers were found inconclusive and are not used.
LOG CodeGraph init skipped: .codegraph/ is not ignored on feat/705.
