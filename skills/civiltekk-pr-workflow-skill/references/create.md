# Create route — the 8-step pre-merge pipeline

Route `create` of `civiltekk-pr-workflow-skill` (#604; formerly the
PR-creation member skill). Any PR creation in this config — also the
engine behind `pr-workflow-subagent`. Create PRs with
framework-appropriate quality gates: detect target branch, framework,
and tracking system; run lint/build/test/typecheck per the gate memo;
generate the structured PR body; apply the semver label; link the
tracker.

## Steps

1. **Target branch**: PR base = the branch the feature was cut from (default repo default branch).
2. **Framework detection** (manifest-first): `package.json` deps → nextjs/nestjs/vue/angular/react/express/node · `pyproject.toml`/`requirements.txt` → django/fastapi/flask/python · `pom.xml`/`build.gradle*` → spring-boot/java · `*.csproj|*.sln` → dotnet · `go.mod` → go · `Cargo.toml` → rust · `composer.json` → laravel/symfony · `Gemfile` → rails.
3. **Quality checks — gate contract + memo check** (per `verification-loop-skill` §The gate contract): run the gate for the detected stack via manifest discovery — never a restated per-framework command table. Before running, check the gate memo: a `GATE <sha> tier=full …` line for the current tree SHA in the PLAN's `## Trace` section (when a PLAN is in play) or the orchestrator's green-gates assertion (pipeline mode) → skip the re-run and state it — a `tier=light` line is phase evidence and never satisfies this check; the pushed SHA's authorization is always `tier=full` (§Tiered gating). No memo for the current SHA → run the gates; skipping on absent evidence is forbidden. Fill the PR body's Quality Checks slot (step 6) from the memo/assertion — that SHA→green record drives later re-run decisions. CI (`gh pr checks`) remains the only unconditional re-run.
4. **Tracking system**: commit messages/branch naming (tracker key per `ticketing-skill`, `#123`) → GitHub Issues or tracker; include `Closes <ref>` (keep the `#` for GitHub) in the body.
5. **Git status check**: clean tree, all changes committed before creating.
6. **Create PR** (`gh pr create --assignee @me`); body template: Summary / (Tracker|Issue) Reference / Changes / Quality Checks (per-step pass results) / Files Modified / Checklist. Author = the `gh auth` user by construction — attribution rule per `ticketing-skill` §Attribution; `@me` self-assigns the same identity. If `command -v gh` fails, load `gh-cli-setup-skill`, then continue.
7. **Semver label** from the PR title: `type!:` → `major`; `feat:` → `minor`; `fix:` and everything else → `patch`. Governance: `semantic-release-convention-skill`. Apply via `gh pr edit --add-label`; if that fails with the Projects-classic GraphQL deprecation error (observed 2026-09-29 — `repository.pullRequest.projectCards`), fall back to the REST API: `gh api -X POST repos/<owner>/<repo>/issues/<n>/labels -f 'labels[]=<label>'`.
8. **Images**: any generated diagrams/visuals are committed and referenced in the body (never inlined as base64).

## Handoff

Step 8 is the route's end — the merge work that follows belongs to the
`merge` route (host SKILL.md §Route chain). The skill-wide Iteration
Protocol (opt-in) lives in the host `SKILL.md`, stated once — not
restated here.
