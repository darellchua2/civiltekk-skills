# PLAN: civiltekk-side betekk org split — skill removals + versioned installer

**Branch**: feat/667
**Issue**: https://github.com/darellchua2/civiltekk-skills/issues/667
**Base**: main

## Acceptance Criteria
- [x] The three org skills (dev-uat-promotion-skill, version-bump-standard-skill, git-branch-workflow-setup-skill) and skills/civiltekk-opentofu-skill/references/ecr.md are removed; org-marker grep over skills/ returns provenance-only hits
- [x] registry.json, dependency-map.json, presets, README counts and setup.sh banner consistent; `node installer/build-registry.mjs` green
- [x] repo-ops-specialist-subagent skips with an install note when git-branch-workflow-setup-skill is absent
- [x] `npx github:darellchua2/civiltekk-skills add <skill>` installs from the latest vX.Y.Z tag; `#main` opt-in works
- [x] Every installed skill dir carries `.skill-source.json` with source/ref/version/installedAt/files
- [x] `list` verb prints installed vs latest per skill; contract tests updated and green

## Dependency & Consumer Map

| Node (file/module) | Depends on (must precede) | Consumers (who depends on this) | Change risk |
|---------------------|---------------------------|---------------------------------|-------------|
| `skills/dev-uat-promotion-skill/` | — | installer/registry.json, installer/presets/pack-devops.json, deploy/skill-profiles.json, deploy/opencode.json permissions (:80), README table/category | med |
| `skills/version-bump-standard-skill/` | — | same consumer set (opencode.json :170) + agents/pr-workflow-subagent.md:69 (permissions allow rule) | med |
| `skills/git-branch-workflow-setup-skill/` | version-bump-standard (content ref) | same consumer set (opencode.json :75) + agents/repo-ops-specialist-subagent.md delegation spec + agents/nextjs-specialist-subagent.md:94 (detection delegation, NEEDS_GIT_BRANCH_SETUP signal) | med |
| `skills/civiltekk-opentofu-skill/references/ecr.md` | — | civiltekk-opentofu-skill SKILL.md route+references tables, agents/opentofu-explorer-subagent.md:67, skills/aws-iac-safety-skill/SKILL.md:29, registry description | med |
| `installer/init.mjs` | registry.json | npx users (add/remove verbs), deploy/setup.sh single-install path, contract tests | high |
| `installer/registry.json` (generated) | skills/ dir tree | installer/init.mjs, deploy/setup.sh, README counts, registry description consumers | med |

## Implementation Phases

### Phase 1: Org-skill removals + route extraction (WS1, civiltekk side)
- [x] **1.1** `git rm -r` the three org skill dirs (dev-uat-promotion-skill, version-bump-standard-skill, git-branch-workflow-setup-skill)
    — **Why:** these implement the betekk dev→uat→main branch model — org workflow, moving to betekk-skills (betekk/betekk-skills#9); removal is the ticket's core AC
    — **Done when:** `ls skills/ | grep -E "dev-uat-promotion|version-bump-standard|git-branch-workflow"` is empty and `git status` shows the three deletions staged
    — **Consumers affected:** registry.json, pack-devops.json, skill-profiles.json, opencode.json permissions, README — synced in 1.3–1.5
    — **Done:** three skill dirs removed via git rm; grep over skills/ empty; files: skills/dev-uat-promotion-skill/, skills/version-bump-standard-skill/, skills/git-branch-workflow-setup-skill/; fixes: none
- [x] **1.2** `git rm` skills/civiltekk-opentofu-skill/references/ecr.md and strip its route row + references-table row + BETEKK description mentions from skills/civiltekk-opentofu-skill/SKILL.md
    — **Why:** the BETEKK ECR/OIDC standard is org content; it is recreated as betekk-ecr-oidc-skill in betekk/betekk-skills#9 (content preserved in that ticket's scope)
    — **Done when:** grep BETEKK in skills/civiltekk-opentofu-skill/ returns zero hits; `ecr-provision` absent from the skill's route table
    — **Consumers affected:** agents/opentofu-explorer-subagent.md and aws-iac-safety-skill links — fixed in 1.4
    — **Done:** ecr.md removed; SKILL.md four routes, all BETEKK/ecr-provision mentions stripped (consolidation-provenance alias retained per 1.2 done-when); files: skills/civiltekk-opentofu-skill/SKILL.md, references/ecr.md; fixes: none
- [x] **1.3** Sync machine registries: remove the three skills from installer/presets/pack-devops.json, deploy/skill-profiles.json, and the three `permissions` skill rules in deploy/opencode.json (:75, :80, :170); delete the ecr-provision references from the civiltekk-opentofu-skill registry entry source (SKILL.md frontmatter description) if present
    — **Why:** installer/setup read these at deploy time; dangling entries fail the isolation/count guards
    — **Done when:** grep for the three skill names across installer/ and deploy/ returns zero hits (excluding PLANS/ and LEARNINGS/)
    — **Consumers affected:** none beyond the files themselves
    — **Done:** pack-devops.json, skill-profiles.json (2 entries), opencode.json (3 permission rule blocks) synced; JSON valid; files: installer/presets/pack-devops.json, deploy/skill-profiles.json, deploy/opencode.json; fixes: none
- [x] **1.4** Update agent + skill cross-references: agents/opentofu-explorer-subagent.md (drop `ecr-provision` route row + description mention), skills/aws-iac-safety-skill/SKILL.md:29 (Related-Skills link), agents/repo-ops-specialist-subagent.md (git-branch-workflow-setup-skill delegation → org-scope marker: resolve the skill, absent → report unavailable + print the betekk install hint `npx github:betekk/betekk-skills add git-branch-workflow-setup-skill` and continue the flow with setup skipped), agents/pr-workflow-subagent.md:69 (drop the version-bump-standard-skill permissions allow rule — resource no longer in this catalog), agents/nextjs-specialist-subagent.md:94 (rewrite Mode 1 step 8 to the org-scope skip-with-note form: skill absent → print the betekk install hint, skip branch-workflow detection, never emit NEEDS_GIT_BRANCH_SETUP; drop the signal from the Return Contract and align repo-ops-specialist's trigger wording)
    — **Why:** cross-references must resolve (house cross-reference audit rule); the skip-with-note pattern is the decided public-repo behavior for org-scope deps; review traversal found the two extra agent consumers the original step missed
    — **Done when:** grep git-branch-workflow-setup in agents/ shows only org-scope skip-with-note forms; grep version-bump-standard in agents/ is zero; grep ecr-provision in agents/ and skills/ is zero
    — **Consumers affected:** pipeline Step 7 reviewers read these files
    — **Done:** explorer route row dropped, aws-iac link dropped, repo-ops frontmatter rule removed + step 1 + skills table now org-scope with betekk install hint, pr-workflow dangling allow rule removed, nextjs-specialist step 8 + Return Contract org-scope skip-with-note; files: agents/opentofu-explorer-subagent.md, agents/repo-ops-specialist-subagent.md, agents/pr-workflow-subagent.md, agents/nextjs-specialist-subagent.md, skills/aws-iac-safety-skill/SKILL.md; fixes: review Major finding folded (the latter two agent files were unmapped in the original step)
- [x] **1.5** README sync: remove the three skill rows + category mentions (Git/Workflow category line, skill table), update the civiltekk-opentofu-skill description row (drop BETEKK/ECR-route phrasing)
    — **Why:** README is the catalog face; counts and listings must match reality (repo sync rules)
    — **Done when:** grep for the three names + "BETEKK" in README.md returns zero hits
    — **Consumers affected:** registry.json description (regenerated next)
    — **Done:** count 125→122 (5 derived literals), category row 12→9, tofu description row de-BETEKK'd, migration-history pointer added; files: README.md; fixes: transient zai_media typo introduced+reverted in the same session (verified byte-equal to original)
- [x] **1.6** Regenerate and commit installer/registry.json via `node installer/build-registry.mjs`; run the contract tests (bats tests/) and fix any count/membership pins that reference removed entries
    — **Why:** registry.json is generated and must be committed with its source changes (repo rule)
    — **Done when:** build-registry exits 0, `git diff installer/registry.json` reflects only the removals, bats suite green
    — **Consumers affected:** installer/init.mjs, deploy/setup.sh
    — **Done:** registry regenerated (count 122, four-route tofu description, timestamp only); full bats suite green; files: installer/registry.json, tests/skill_profiles.bats; fixes: 4 count-pin failures on first run — README 5 derived literals stale (125→122, lean 70→68) + skill_profiles.bats two lean pins 70→68 (both removed skills were lean members)

### Phase 2: Versioned installer (WS3, civiltekk side)
- [x] **2.1** Add ref resolution to installer/init.mjs: helper that resolves the latest semver tag via `git ls-remote --tags <repo-url>` (sort -V, ignore `^{}`), honors `--ref <ref>` flag (`#main` opt-in = `--ref main`), and `--source .` dev mode that installs from the running tree without fetching
    — **Why:** AC requires latest-tag default install with main opt-in; the running npx tree may be ahead of the last release
    — **Done when:** a unit-callable node check resolves `v12.19.1` (or newer) from the live repo and `--ref main`/`--source .` parse
    — **Consumers affected:** 2.2, 2.3
    — **Done:** parseTagLines (exported, pure) + resolveLatestTag + repoUrl() from new package.json repository field; --ref/--source flow through the generic parser; files: installer/init.mjs, package.json; fixes: none
- [x] **2.2** Rework the `add` verb: fetch the selected ref's tree (`git clone --depth 1 --branch <ref>` into a temp dir; `--source .` skips the fetch), copy the skill dir plus its declared dependency-map prerequisites from that tree, write `.skill-source.json` (`{source, ref, version, installedAt, files[]}`) into each installed skill dir, and record ref+version in the `.skill-manifest.json` entries
    — **Why:** delivers pinned/provenance-stamped installs; the sidecar is the rollback/upgrade surface for `list` and users
    — **Done when:** `node installer/init.mjs add <skill> --source .` into a scratch HOME installs the dir with a populated `.skill-source.json` and a manifest entry carrying ref
    — **Consumers affected:** list verb (2.3), README docs (2.4), manifest consumers
    — **Done:** version router in main() (latest-tag default, local shortcut when tree==tag, shallow-clone + re-exec of the tagged installer otherwise, old-installer post-stamp sweep via stampMissingRef); writeSkillSidecar on both scope paths; manifest entries carry ref/version; SIDECAR excluded from hashSkillDir so update stays idempotent; files: installer/init.mjs; fixes: router re-exec initially produced unstamped installs (tagged installers predate the sidecar) — outer post-stamp pass added
- [x] **2.3** Add the `list` verb: enumerate installed skills (manifest entries / dirs carrying `.skill-source.json`), print each with its installed ref/version and the remote latest tag (single `git ls-remote --tags` call), flagging update-available
    — **Why:** AC requires installed-vs-latest visibility; upgrade is then "re-run add"
    — **Done when:** `node installer/init.mjs list` prints name, installed ref, latest tag, and an update marker in a scratch HOME with one installed skill
    — **Consumers affected:** README docs (2.4)
    — **Done:** cmdList kind `installed` (JSON rows: name/installedRef/installedVersion/latest/updateAvailable; sidecar-or-manifest provenance, single ls-remote, offline-degradable with note); files: installer/init.mjs; fixes: die-guard lost its conditional during edit — caught and restored pre-gate
- [x] **2.4** README: add a "Versioning & rollback" section documenting latest-tag default, `#vX.Y.Z` pinned install, `--ref main`, upgrade-by-rerun, and the sidecar; update the install section to match
    — **Why:** the versioning capability is invisible to end users until documented (audit finding)
    — **Done when:** README documents all four flows with copy-paste commands
    — **Consumers affected:** none
    — **Done:** Versioning & rollback subsection under the one-skill install path: latest default, #vX.Y.Z pinned, --ref main, list installed, upgrade-by-rerun, post-stamp + --source notes; files: README.md; fixes: none
- [x] **2.5** Update/extend contract tests for the new verbs + sidecar + manifest ref; run the full bats suite
    — **Why:** behavior change without a pinned test regresses silently; ticket exit gate is full
    — **Done when:** bats tests/ green including new installer-verb pins
    — **Consumers affected:** CI
    — **Done:** tests/test_installer_versions.bats (5 tests: parseTagLines unit, sidecar+manifest stamp, hash-transparency/update idempotency, list installed rows, live --ref v12.18.0 rollback pin with network skip guard); full suite 662/662; files: tests/test_installer_versions.bats; fixes: none

## Technical Notes
- The ECR route content moves to betekk/betekk-skills#9 (betekk-ecr-oidc-skill) — this ticket only removes; no content is lost (full text preserved in that ticket's work).
- Latest-tag install clones the tag tree fresh each `add` (npx already required network; determinism over micro-optimization).
- setup.sh/setup.ps1 skill counts are computed dynamically (count_skills) — no banner edit needed; verified by grep.
- installer/dependency-map.json has no edges for the three skills (verified) — no dep-map edit.

## Dependencies
- Umbrella epic: betekk/canvastekk-tracker#3736
- Sibling ticket: betekk/betekk-skills#9 (betekk-side imports — independent repo, no ordering constraint)
- blocks: #668 (generalizer sweep)

## Risks & Mitigation
- Registry regeneration churn beyond the removals → review `git diff installer/registry.json` in 1.6; anything unrelated is a build-registry bug to fix, not to hand-patch
- opencode.json permission-rule removal breaking gating tests → tests/ has no pins on the three names (verified); 1.6's suite run catches surprises
- Shallow-clone install fails behind restricted network → clear error naming the ref; `--source .` remains the offline escape hatch

## Trace

- LOG: architecture review (inline arm, recovered after skill-permission allow) — Major finding applied: two unmapped agent consumers (agents/pr-workflow-subagent.md:69 permissions rule, agents/nextjs-specialist-subagent.md:94 detection delegation) folded into step 1.4 + Consumer Map; root-docs sweep keep-justified (CHANGELOG historical). Atomicity re-check: 11/11 steps well-formed.
- LOG: Phase 1 gate fix-on-fail (1 attempt) — first full-suite run exit 1: 4 count-pin failures (readme_skill_total_and_lean_match_derived, skill_count_consistent_across_docs, 2× skill_profiles lean pins). Fixed: README 5 derived literals (125→122 disk, 70→68 lean), tests/skill_profiles.bats 70→68 ×2. Re-run: exit 0, 657/657.
- GATE 2e6d940 tier=light lint=n.a typecheck=n.a build=n.a unit=t (bats tests/ 657/657, exit 0) e2e=n.a
- LOG: Phase 2 docstrings skipped deliberately — init.mjs house style is inline comments, not JSDoc; new helpers carry explanatory comments matching the surrounding code.
- GATE 6ab6e17 tier=full lint=n.a typecheck=n.a build=n.a unit=t (bats tests/ 662/662 incl. 5 new installer-version pins, exit 0 — ticket exit gate) e2e=n.a
