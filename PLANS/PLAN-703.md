# PLAN: Seed GPT-6.2 Astra context override through setup

**Branch**: feat/703
**Issue**: https://github.com/darellchua2/civiltekk-skills/issues/703
**Base**: dev

## Acceptance Criteria
- [x] `deploy/opencode.json` contains the explicit GPT-6.2 Astra limits.
- [x] The normal setup deployment seeds these limits into the generated global `opencode.json`.
- [x] Model resolution preserves the Astra override.
- [x] Verification covers the config and deployment behavior. (Meaning confirmed with the owner at the Step 7 requirements gate: "deployment behavior" is the file setup's config writers produce, asserted by repeatable bats tests in CI. The effective window under a ChatGPT sign-in is a one-time recorded check, not an automated test.)
- [x] No other model's limits change, and the OAuth context-cap plugin is not disabled. (Lifted from the ticket's Scope section at the Step 7 requirements gate.)
- [x] An `openai/gpt-6.2-astra` pin passes the deploy-time exposed-model guard. (Added at Step 5 re-validation with the owner's approval; not in the ticket text.)
- [x] A kept config is never written to: declining the config overwrite does not add the override to an existing `opencode.json`, and the doc explains how existing installs opt in. (Decided with the owner at the Step 7 Mode R relay: document only.)

## Dependency & Consumer Map

_Before writing steps, list each touched file/module and who consumes it. Use `codegraph_callers` (code) or `tofu graph` + grep (IaC)._

| Node (file/module) | Depends on (must precede) | Consumers (who depends on this) | Change risk |
|---------------------|---------------------------|---------------------------------|-------------|
| `deploy/opencode.json` (`providers.openai.models["gpt-6.2-astra"].limit`) | — | `deploy/setup.sh:2926` (config copy); `installer/resolve-models.mjs:280-284,469` (`--config-src`/`--config-dest` round-trip); `deploy/apply-skill-profile.mjs:75,109,151` (both write sites round-trip the parsed object); `deploy/merge-packs.mjs:85,242`; `installer/init.mjs:1186-1220` (`permitMerge` rewrites the deployed file on the npx `--permit` path: parses the whole object, edits only permission rules); `deploy/setup.sh:1810,2886` (restore and legacy-migrate paths carry whatever the old file holds, by design); strict-JSON parsers in `tests/test_mcp_count_consistency.bats`, `tests/skill_profiles.bats`. `installer/init.mjs` reads this file at :417,:741,:1176,:1993 but only `mcp.servers` (`grep -n '\.providers\b\|providers:' installer/init.mjs` returns nothing). | low |
| `installer/provider-models.json` (`openai[]` plus one id) | live models.dev catalog lists the id (`curl -s https://models.dev/api.json`: `openai.models["gpt-6.2-astra"].limit = {context:1050000,input:922000,output:128000}`) | `installer/resolve-models.mjs:138,349-391` (exposed-model guard); `deploy/setup.sh:3256-3258` (passes `--provider-models`); `installer/init.mjs:55,506-520` (`isModelAvailable`: an Astra pin stops raising the "may be unselectable" note); `deploy/setup.sh:4254` (`--check-catalog`, warn-only: one fewer missing-id warning); `deploy/regen-provider-models.mjs:40,75,102`; `tests/test_provider_pins.bats`, `tests/test_provider_regen.bats` | low |
| `tests/test_astra_context_override.bats` (new) | the two rows above | CI loop `.github/workflows/release.yml:66-68` | low (new file) |
| `tests/test_provider_pins.bats` (two tests appended) | `installer/provider-models.json`, `installer/resolve-models.mjs` | CI loop `.github/workflows/release.yml:66-68` | low |
| `MIGRATION.md` (one subsection) | — | Readers; negative pins `tests/test_pack_permissions.bats:245-246` and `tests/test_skill_isolation.bats:37` grep it | low |

Commands behind the consumer claims (run at Steps 5 and 7 in the worktree): `grep -n 'opencode\.json' deploy/setup.sh deploy/*.mjs installer/*.mjs`, `grep -n 'writeFile\b\|writeFileSync' deploy/*.mjs installer/*.mjs`, `grep -rn 'provider-models\|PROVIDER_MODELS\|providerModels' deploy installer`, `grep -rln 'provider-models' tests deploy installer`, `grep -ln 'MIGRATION\.md' tests/*.bats`.

## Implementation Phases

_Every step MUST be atomic and carry rationale. Reject any step missing a "Why"._

### Phase 1: Seed the override in the shipped config and prove the deploy pipeline keeps it
- [x] **1.1** Add `providers.openai.models["gpt-6.2-astra"].limit = { "context": 1050000, "input": 922000, "output": 128000 }` to `deploy/opencode.json` as a new fourth entry in `providers` (after `zai-custom`, before `mcp`), leaving the three existing providers byte-untouched.
    — **Why:** This block is the ticket's deliverable and the single source the setup flow deploys from. Under ChatGPT sign-ins OpenCode's `opencode.provider.openai-context-caps` plugin pins Astra to 272,000 input tokens; a per-model `limit` is the override OpenCode applies after that plugin, and `input` must be present because the merge is per key.
    — **Done when:** `jq -e '.providers.openai.models["gpt-6.2-astra"].limit == {"context":1050000,"input":922000,"output":128000}' deploy/opencode.json` exits 0; `jq . deploy/opencode.json > /dev/null` exits 0; `git diff --numstat -- deploy/opencode.json` reports zero deleted lines.
    — **Consumers affected:** User-space deployments (`deploy/setup.sh` copy step) and OpenCode sessions signed in to OpenAI. Accepted side effect (owner decision at Step 5): the `openai` provider is listed for every deployment, signed in or not.
    — **Done:** Added providers.openai with the single gpt-6.2-astra limit as the fourth provider; the jq limit check, jq validity and a zero-deletion numstat all pass, and the rest of the file is deep-equal to dev; files: deploy/opencode.json; fixes: none
- [x] **1.2** Add `tests/test_astra_context_override.bats`: assert the exact three-key limit, that `providers.openai.models` holds no other model and the cap plugin is not disabled, and that the block survives `installer/resolve-models.mjs` (fresh-copy and declined-copy paths), `deploy/apply-skill-profile.mjs` and `deploy/merge-packs.mjs` run against `mktemp -d` copies; assert the declined-copy path leaves a config that lacks the block free of it; include one induced-corruption negative test.
    — **Why:** Covers acceptance criteria 1 to 5 and 7. The block is plain data that three deploy-time rewriters pass through, so nothing else would fail if a future rewrite dropped it, an edit removed `input`, or the decline contract were broken by writing into a kept config.
    — **Done when:** `bats tests/test_astra_context_override.bats` reports every test ok, including the induced-corruption test.
    — **Consumers affected:** CI (`.github/workflows/release.yml:66-68` runs every `tests/*.bats`).
    — **Done:** Added 8 bats tests covering the exact limit, both resolver paths, the lean skill profile, a pack merge, the kept-config guarantee and two negative fixtures; 8 of 8 pass, and 4 mutations of the real block each turn 5 or 6 tests red; files: tests/test_astra_context_override.bats; fixes: none
- [x] **1.3** Add a short "GPT-6.2 Astra context window under ChatGPT sign-in" subsection to `MIGRATION.md` under "Choosing a provider": what the override is, why all three keys are present, that OpenAI models now appear in the picker without a sign-in, that re-running setup keeps an existing config by default so existing installs receive the override only by accepting the overwrite once or pasting the block by hand, and how to remove the block.
    — **Why:** The JSON cannot carry the rationale (the bats and `jq` parsers need strict JSON, and the OpenCode schema sets `additionalProperties: false` on providers and models), and the picker change is visible to every user, so the explanation and the undo need a home.
    — **Done when:** `grep -c 'GPT-6.2 Astra context window under ChatGPT sign-in' MIGRATION.md` prints 1; `bats tests/test_pack_permissions.bats tests/test_skill_isolation.bats` pass (both carry negative pins over `MIGRATION.md`).
    — **Consumers affected:** Readers of the migration guide.
    — **Done:** Added the Astra context-window subsection to MIGRATION.md under "Choosing a provider"; the heading count is 1 and both test files that grep this file pass (19 ok, 0 not ok); files: MIGRATION.md; fixes: none

### Phase 2: Let Astra pins through the deploy-time guard
- [x] **2.1** Add `"gpt-6.2-astra"` to the `openai` array in `installer/provider-models.json`, directly after `"gpt-6-astra"`.
    — **Why:** The resolver's exposed-model guard fails the deploy for any `openai/gpt-6.2-astra` pin (exit 1, "NOT exposed by provider openai") because the shipped list predates the model, while the live catalog serves it. That position is the one `deploy/regen-provider-models.mjs` (default `.sort()`) produces, so a regen keeps it.
    — **Done when:** `jq -e '.openai | index("gpt-6.2-astra") != null' installer/provider-models.json` exits 0; `node -e 'const a=require("./installer/provider-models.json").openai; process.exit(JSON.stringify(a) === JSON.stringify([...a].sort()) ? 0 : 1)'` exits 0; `bats tests/test_provider_pins.bats tests/test_provider_regen.bats` pass.
    — **Consumers affected:** `installer/resolve-models.mjs` guard (via `deploy/setup.sh`), `deploy/regen-provider-models.mjs`, `tests/test_provider_pins.bats`, `tests/test_provider_regen.bats`.
    — **Done:** Added gpt-6.2-astra to the openai array right after gpt-6-astra; the jq index and sort-order checks exit 0, the pins and regen tests pass (14 ok), and the file minus that id is deep-equal to dev; files: installer/provider-models.json; fixes: none
- [x] **2.2** Extend `tests/test_provider_pins.bats` with two tests: `astra_pin_passes_the_deploy_time_guard` pins `openai/gpt-6.2-astra` as `primary` and `reasoning` and expects the real resolver in `--dry-run` with `--provider-models installer/provider-models.json` to exit 0; `astra_pin_rejected_when_catalog_lacks_it` removes the id from a scratch copy of the file and expects a non-zero exit whose output names the missing model.
    — **Why:** Pins the user-visible outcome (Astra selectable through setup) and proves the new test can fail, following the file's existing induced-breakage pattern.
    — **Done when:** `bats -c tests/test_provider_pins.bats` prints 7 (it prints 5 before this step) and `bats tests/test_provider_pins.bats` reports every test ok.
    — **Consumers affected:** CI (`.github/workflows/release.yml:66-68`).
    — **Done:** Added astra_pin_passes_the_deploy_time_guard and astra_pin_rejected_when_catalog_lacks_it; bats -c prints 7 and all 7 pass, and removing the id from the real file turns the passing test into a reported "not ok"; files: tests/test_provider_pins.bats; fixes: replaced in-test EXIT traps with a file-level teardown() in the two pre-existing negative-fixture tests and the two new ones (see Trace)

## Technical Notes

Facts verified at Step 5 against the installed OpenCode `v2.4.1` (the tag the ticket cites), upstream source at that tag, the live models.dev catalog and OpenAI's model page.

- **Config shape.** The current key is `providers` (plural; singular `provider` is deprecated in `https://opencode.ai/config.json`). Each model takes `limit: { context, input, output }`, integers, `additionalProperties: false`. No `$comment` key fits inside the block.
- **All three keys are required.** The config merge is per key (`model.limit = { ...model.limit, ...config.limit }`, `packages/core/src/config/plugin/provider.ts:235`), and the cap plugin writes `input` and `context` explicitly. An override carrying only `context` and `output` (the shape of the existing entries in this file) would leave `input` at 272,000.
- **Ordering.** The config plugin registers its model transform "after external model transforms" (`packages/core/src/config/plugin/provider.ts:97-99`), so the override wins over the cap plugin. Also stated in upstream PR #58194 and its review. This is source-level evidence; it was not exercised under a live ChatGPT sign-in.
- **Measured behavior** (sandboxed `opencode serve`, no OpenAI credential): a marker limit of 1049000/921000/127000 on `gpt-6.2-astra` is reported back exactly; the model keeps its catalog name and cost; `gpt-6-astra` and `gpt-5.5` still report catalog limits.
- **Accepted side effect.** Naming `openai` under `providers` sets `activation: "enabled"` (`packages/core/src/config/plugin/provider.ts:195`), and the picker has no credential filter (`packages/tui/src/component/dialog-model.tsx:124-141`). With this repo's shipped config and no OpenAI sign-in, `opencode models` went from 14 to 113 lines (98 of them `openai/`) on the bundled catalog snapshot; the exact counts move with the catalog. The owner chose to ship as specified (Step 5 question).
- **Strict JSON.** `//` comments break the bats and `jq` parsers of `deploy/opencode.json`; keep the file comment-free as it is today.
- **Guard failure reproduced.** `node installer/resolve-models.mjs --tiers installer/agent-tiers.json --default-map installer/models.default.json --user-map <map pinning openai/gpt-6.2-astra> --provider-models installer/provider-models.json --dry-run` exits 1 with `NOT exposed by provider "openai"`; the same run with `openai/gpt-6-astra` exits 0.
- **Test isolation.** Pipeline tests copy into `mktemp -d` and pass explicit `--config`/`--config-dest` paths; nothing may write under the real `$HOME`. One assertion per line in bats (`a && b && c` enforces only `c`); no backticks inside `[[ ]]` assertion strings.
- **Gate commands mirror CI** (`.github/workflows/release.yml`): `node installer/build-registry.mjs --check`; `node --check installer/init.mjs installer/source.mjs installer/build-site.mjs`; `jq . package.json`; `jq . deploy/opencode.json`; `bash -n deploy/setup.sh`; `bats tests/<file>` for each file. No typecheck or build target exists in this repo (`package.json` has no scripts).
- **Test runner.** CI runs the vendored `tests/lib/bats-core` (submodule at `d9faff0d`, which declares version 1.13.0), the same version as the bats on PATH here. The submodule is not checked out in this worktree; local gates use the PATH bats.
- **Existing installs.** Re-running setup keeps an existing config by default: the overwrite prompt defaults to "n" and headless runs take the default (`deploy/setup.sh:2897-2905`). The override therefore reaches fresh setups only. The owner chose to document the two ways to opt in and not to write into a kept config (Step 7 Mode R relay, round 1 of 2).
- **Doc note constraint.** Describe the override and point at `deploy/opencode.json` for the values. Do not restate the three limit numbers as a config block; the JSON and the test literal are the only copies.
- Phase commits follow the executor's format, `<type>(<scope>): implement Phase N — <summary>`: Phase 1 `feat(config)`, Phase 2 `fix(installer)`. Gate commands: lint is CI's lint step scoped to the changed files; typecheck has no target (`n.a`); there is no build (`-`); unit is CI's per-file loop `for f in tests/*.bats; do bats "$f" || exit 1; done`; e2e is `n.a` (no frontend). Both phases run the full gate: each touches a config or data node with cross-module consumers.

## Dependencies
- None. Not blocked by other tickets.

## Risks & Mitigation
- **Picker change for non-OpenAI users.** Accepted by the owner. Documented in `MIGRATION.md` with the removal steps; the block is a self-contained JSON object and reverts cleanly.
- **Override efficacy is source-verified, not live-verified.** A later OpenCode release that reorders transforms would re-cap Astra with no error here. Mitigation: the test pins all three keys, and the doc states what is verified and what is not. No user-facing check for the live window ships: the only working recipe needs a hand-copied server password, and OpenCode's managed background service listens on a fixed default port that a HOME/XDG sandbox does not isolate.
- **Cost.** OpenAI lists higher rates for requests above 272K input tokens, and the plugin's own comment calls the caps "a usage choice, not a backend requirement". Longer Astra sessions will use more of the ChatGPT plan. Noted in the doc.
- **Wider catalog drift left alone.** `installer/provider-models.json` differs from the live catalog in both directions beyond this one id. Regen and its drift rules are a separate concern; this plan adds only `gpt-6.2-astra`.
- **Existing installs do not receive the override by default.** Accepted by the owner (document only). Mitigation: the doc names the two ways to opt in, and a test pins that the declined-copy path never writes the block into a kept config.

## Trace
LOG 7 plan review: requirements gate fired on AC 4 (owner chose pipeline tests in CI; two guardrail ACs lifted from the ticket's Scope); architecture review partial, 1 Major (step 2.2 done-when could not fail) and 1 Minor (consumer-map omissions) applied to the PLAN; Mode R round 1/2 resolved (existing installs: document only, added as an AC).
LOG Phase 1 escalated to full because it changes deploy/opencode.json, a deploy config node with consumers in deploy/setup.sh and in three scripts across deploy/ and installer/.
LOG No user-facing check for the effective limit is documented: opencode api against a started server needs the server password from its log and returns an empty list until plugins load, and the managed background service listens on a fixed default port that a HOME/XDG sandbox does not isolate. Step 1.3 states what is verified and what is not instead, and the Risks bullet was corrected to match.
GATE f4c66ea4 tier=full lint=t typecheck=n.a build=- unit=t e2e=n.a (59 Bats files, 735 tests; gated tree differs from this commit only in PLANS/PLAN-703.md, which no test reads)
LOG Repair: the Phase 1 GATE memo above was first appended onto the end of the previous LOG line (the file had lost its trailing newline). This commit restores the line break; neither line's text changed.
LOG Phase 2 escalated to full because it changes installer/provider-models.json, a data node read by the resolver guard, installer/init.mjs and setup.sh, and because it is the ticket exit gate.
LOG Step 2.2 deviation: tests/test_provider_pins.bats cleaned up with an EXIT trap inside each test. In bats 1.13.0 a failing test with its own EXIT trap prints no not-ok line, only the warning that fewer tests than expected ran. Added a file-level teardown() and switched the two pre-existing negative-fixture tests to it (one line each) along with the two new tests.
GATE bc7a186e tier=full lint=t typecheck=n.a build=- unit=t e2e=n.a (59 Bats files, 737 tests; gated tree differs from this commit only in PLANS/PLAN-703.md, which no test reads)
LOG Step 9 code review: 0 Critical, 0 Major, 3 Minor. Fixed M1 (the MIGRATION.md note said setup asks before overwriting, false for --models-only) in 5692f441 and M2 (one shared resolver call in the Astra tests) in 4aa3f259; M3 noted. Full gate re-run on the fixed tree.
GATE 4aa3f259 tier=full lint=t typecheck=n.a build=- unit=t e2e=n.a (59 Bats files, 737 tests; gated tree is this commit exactly)
