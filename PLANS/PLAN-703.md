# PLAN: Seed GPT-6.2 Astra context override through setup

**Branch**: feat/703
**Issue**: https://github.com/darellchua2/civiltekk-skills/issues/703
**Base**: dev

## Acceptance Criteria
- [ ] `deploy/opencode.json` contains the explicit GPT-6.2 Astra limits.
- [ ] The normal setup deployment seeds these limits into the generated global `opencode.json`.
- [ ] Model resolution preserves the Astra override.
- [ ] Verification covers the config and deployment behavior.
- [ ] An `openai/gpt-6.2-astra` pin passes the deploy-time exposed-model guard. (Added at Step 5 re-validation with the owner's approval; not in the ticket text.)

## Dependency & Consumer Map

_Before writing steps, list each touched file/module and who consumes it. Use `codegraph_callers` (code) or `tofu graph` + grep (IaC)._

| Node (file/module) | Depends on (must precede) | Consumers (who depends on this) | Change risk |
|---------------------|---------------------------|---------------------------------|-------------|
| `deploy/opencode.json` (`providers.openai.models["gpt-6.2-astra"].limit`) | — | `deploy/setup.sh:2926` (config copy); `installer/resolve-models.mjs:280-284,469` (`--config-src`/`--config-dest` round-trip); `deploy/apply-skill-profile.mjs:75,151`; `deploy/merge-packs.mjs:85,242`; strict-JSON parsers in `tests/test_mcp_count_consistency.bats`, `tests/skill_profiles.bats`. `installer/init.mjs` reads this file at :417,:741,:1176,:1993 but only `mcp.servers` (`grep -n '\.providers\b\|providers:' installer/init.mjs` returns nothing). | low |
| `installer/provider-models.json` (`openai[]` plus one id) | live models.dev catalog lists the id (`curl -s https://models.dev/api.json`: `openai.models["gpt-6.2-astra"].limit = {context:1050000,input:922000,output:128000}`) | `installer/resolve-models.mjs:138,349-391` (exposed-model guard); `deploy/setup.sh:3256-3258` (passes `--provider-models`); `installer/init.mjs:55,509`; `deploy/regen-provider-models.mjs:40,75,102`; `tests/test_provider_pins.bats`, `tests/test_provider_regen.bats` | low |
| `tests/test_astra_context_override.bats` (new) | the two rows above | CI loop `.github/workflows/release.yml:66-68` | low (new file) |
| `tests/test_provider_pins.bats` (two tests appended) | `installer/provider-models.json`, `installer/resolve-models.mjs` | CI loop `.github/workflows/release.yml:66-68` | low |
| `MIGRATION.md` (one subsection) | — | Readers; negative pins `tests/test_pack_permissions.bats:245-246` and `tests/test_skill_isolation.bats:37` grep it | low |

Commands behind the consumer claims (run at Step 5 in the worktree): `grep -n 'opencode\.json' deploy/setup.sh deploy/*.mjs installer/*.mjs`, `grep -rln 'provider-models' tests deploy installer`, `grep -ln 'MIGRATION\.md' tests/*.bats`.

## Implementation Phases

_Every step MUST be atomic and carry rationale. Reject any step missing a "Why"._

### Canonical step format
- [ ] **N.M** <single atomic action — verb + target + outcome>
    — **Why:** <what this unblocks / why it must precede others>
    — **Done when:** <objective, checkable completion signal>
    — **Consumers affected:** <who depends on this; none if N/A>

### Phase 1: Seed the override in the shipped config and prove the deploy pipeline keeps it
- [ ] **1.1** Add `providers.openai.models["gpt-6.2-astra"].limit = { "context": 1050000, "input": 922000, "output": 128000 }` to `deploy/opencode.json` as a new fourth entry in `providers` (after `zai-custom`, before `mcp`), leaving the three existing providers byte-untouched.
    — **Why:** This block is the ticket's deliverable and the single source the setup flow deploys from. Under ChatGPT sign-ins OpenCode's `opencode.provider.openai-context-caps` plugin pins Astra to 272,000 input tokens; a per-model `limit` is the override OpenCode applies after that plugin, and `input` must be present because the merge is per key.
    — **Done when:** `jq -e '.providers.openai.models["gpt-6.2-astra"].limit == {"context":1050000,"input":922000,"output":128000}' deploy/opencode.json` exits 0; `jq . deploy/opencode.json > /dev/null` exits 0; `git diff --numstat -- deploy/opencode.json` reports zero deleted lines.
    — **Consumers affected:** User-space deployments (`deploy/setup.sh` copy step) and OpenCode sessions signed in to OpenAI. Accepted side effect (owner decision at Step 5): the `openai` provider is listed for every deployment, signed in or not.
- [ ] **1.2** Add `tests/test_astra_context_override.bats`: assert the exact three-key limit, that `providers.openai.models` holds no other model and the cap plugin is not disabled, and that the block survives `installer/resolve-models.mjs` (fresh-copy and declined-copy paths), `deploy/apply-skill-profile.mjs` and `deploy/merge-packs.mjs` run against `mktemp -d` copies; include one induced-corruption negative test.
    — **Why:** Covers acceptance criteria 1 to 4. The block is plain data that three deploy-time rewriters pass through, so nothing else would fail if a future rewrite dropped it or an edit removed `input`.
    — **Done when:** `bats tests/test_astra_context_override.bats` reports every test ok, including the induced-corruption test.
    — **Consumers affected:** CI (`.github/workflows/release.yml:66-68` runs every `tests/*.bats`).
- [ ] **1.3** Add a short "GPT-6.2 Astra context window under ChatGPT sign-in" subsection to `MIGRATION.md` under "Choosing a provider": what the override is, why all three keys are present, that OpenAI models now appear in the picker without a sign-in, and how to remove the block.
    — **Why:** The JSON cannot carry the rationale (the bats and `jq` parsers need strict JSON, and the OpenCode schema sets `additionalProperties: false` on providers and models), and the picker change is visible to every user, so the explanation and the undo need a home.
    — **Done when:** `grep -c 'GPT-6.2 Astra context window under ChatGPT sign-in' MIGRATION.md` prints 1; `bats tests/test_pack_permissions.bats tests/test_skill_isolation.bats` pass (both carry negative pins over `MIGRATION.md`).
    — **Consumers affected:** Readers of the migration guide.

### Phase 2: Let Astra pins through the deploy-time guard
- [ ] **2.1** Add `"gpt-6.2-astra"` to the `openai` array in `installer/provider-models.json`, directly after `"gpt-6-astra"`.
    — **Why:** The resolver's exposed-model guard fails the deploy for any `openai/gpt-6.2-astra` pin (exit 1, "NOT exposed by provider openai") because the shipped list predates the model, while the live catalog serves it. That position is the one `deploy/regen-provider-models.mjs` (default `.sort()`) produces, so a regen keeps it.
    — **Done when:** `jq -e '.openai | index("gpt-6.2-astra") != null' installer/provider-models.json` exits 0; `node -e 'const a=require("./installer/provider-models.json").openai; process.exit(JSON.stringify(a) === JSON.stringify([...a].sort()) ? 0 : 1)'` exits 0; `bats tests/test_provider_pins.bats tests/test_provider_regen.bats` pass.
    — **Consumers affected:** `installer/resolve-models.mjs` guard (via `deploy/setup.sh`), `deploy/regen-provider-models.mjs`, `tests/test_provider_pins.bats`, `tests/test_provider_regen.bats`.
- [ ] **2.2** Extend `tests/test_provider_pins.bats`: one test pins `openai/gpt-6.2-astra` as `primary` and `reasoning` and expects the real resolver in `--dry-run` with `--provider-models installer/provider-models.json` to exit 0; one negative fixture removes the id from a scratch copy of the file and expects a non-zero exit whose output names the missing model.
    — **Why:** Pins the user-visible outcome (Astra selectable through setup) and proves the new test can fail, following the file's existing induced-breakage pattern.
    — **Done when:** `bats tests/test_provider_pins.bats` reports every test ok, including the two new ones.
    — **Consumers affected:** CI (`.github/workflows/release.yml:66-68`).

## Technical Notes

Facts verified at Step 5 against the installed OpenCode `v2.4.1` (the tag the ticket cites), upstream source at that tag, the live models.dev catalog and OpenAI's model page.

- **Config shape.** The current key is `providers` (plural; singular `provider` is deprecated in `https://opencode.ai/config.json`). Each model takes `limit: { context, input, output }`, integers, `additionalProperties: false`. No `$comment` key fits inside the block.
- **All three keys are required.** The config merge is per key (`model.limit = { ...model.limit, ...config.limit }`, `packages/core/src/config/plugin/provider.ts:235`), and the cap plugin writes `input` and `context` explicitly. An override carrying only `context` and `output` (the shape of the existing entries in this file) would leave `input` at 272,000.
- **Ordering.** The config plugin registers its model transform "after external model transforms" (`packages/core/src/config/plugin/provider.ts:97-99`), so the override wins over the cap plugin. Also stated in upstream PR #58194 and its review. This is source-level evidence; it was not exercised under a live ChatGPT sign-in.
- **Measured behavior** (sandboxed `opencode serve`, no OpenAI credential): a marker limit of 1049000/921000/127000 on `gpt-6.2-astra` is reported back exactly; the model keeps its catalog name and cost; `gpt-6-astra` and `gpt-5.5` still report catalog limits.
- **Accepted side effect.** Naming `openai` under `providers` sets `activation: "enabled"` (`packages/core/src/config/plugin/provider.ts:195`), and the picker has no credential filter (`packages/tui/src/component/dialog-model.tsx:124-141`). With this repo's shipped config and no OpenAI sign-in, `opencode models` goes from 14 to 113 lines (98 of them `openai/`). The owner chose to ship as specified (Step 5 question).
- **Strict JSON.** `//` comments break the bats and `jq` parsers of `deploy/opencode.json`; keep the file comment-free as it is today.
- **Guard failure reproduced.** `node installer/resolve-models.mjs --tiers installer/agent-tiers.json --default-map installer/models.default.json --user-map <map pinning openai/gpt-6.2-astra> --provider-models installer/provider-models.json --dry-run` exits 1 with `NOT exposed by provider "openai"`; the same run with `openai/gpt-6-astra` exits 0.
- **Test isolation.** Pipeline tests copy into `mktemp -d` and pass explicit `--config`/`--config-dest` paths; nothing may write under the real `$HOME`. One assertion per line in bats (`a && b && c` enforces only `c`); no backticks inside `[[ ]]` assertion strings.
- **Gate commands mirror CI** (`.github/workflows/release.yml`): `node installer/build-registry.mjs --check`; `node --check installer/init.mjs installer/source.mjs installer/build-site.mjs`; `jq . package.json`; `jq . deploy/opencode.json`; `bash -n deploy/setup.sh`; `bats tests/<file>` for each file. No typecheck or build target exists in this repo (`package.json` has no scripts).
- Suggested commit subjects: Phase 1 `feat(config): seed GPT-6.2 Astra context limit override`; Phase 2 `fix(installer): let gpt-6.2-astra pins through the exposed-model guard`.

## Dependencies
- None. Not blocked by other tickets.

## Risks & Mitigation
- **Picker change for non-OpenAI users.** Accepted by the owner. Documented in `MIGRATION.md` with the removal steps; the block is a self-contained JSON object and reverts cleanly.
- **Override efficacy is source-verified, not live-verified.** A later OpenCode release that reorders transforms would re-cap Astra with no error here. Mitigation: the test pins all three keys, and the doc tells users how to check the effective limit.
- **Cost.** OpenAI lists higher rates for requests above 272K input tokens, and the plugin's own comment calls the caps "a usage choice, not a backend requirement". Longer Astra sessions will use more of the ChatGPT plan. Noted in the doc.
- **Wider catalog drift left alone.** `installer/provider-models.json` differs from the live catalog in both directions beyond this one id. Regen and its drift rules are a separate concern; this plan adds only `gpt-6.2-astra`.

## Trace
