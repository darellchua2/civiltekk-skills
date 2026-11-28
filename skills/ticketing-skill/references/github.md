# GitHub Issues — platform values for ticketing-skill

> **Load rule:** read this file when the resolved platform is `github` (per
> SKILL.md §Platform Detection). It carries the VALUES — commands, label
> vocabulary, key formats, endpoints. The METHOD (decision gates, lifecycle
> routing, idempotency contracts) lives in SKILL.md and never here. Cite this
> file's values in your output; anything marked *verify locally* must be
> confirmed against the target repo/org before use.
>
> **Contributors:** copying this file's skeleton is the extension path for a
> new tracker platform (`references/<platform>.md`) — values only, no method.

## Tooling fallback (3 tiers)

Resolve the tier BEFORE any GitHub operation. `command -v gh` decides tier 1
vs deeper; tiers 2–3 involve the user — see SKILL.md §Platform Detection for
the ask-don't-invent rule.

| Tier | Condition | Capability |
|------|-----------|------------|
| 1 | `command -v gh` succeeds and `gh auth status` valid | Full CRUD: create, label, comment, close, read |
| 2 | `gh` missing or unauthenticated | Prompt the end user to install; on yes → load `gh-cli-setup-skill` (per-OS install + `gh auth login`), then re-enter tier 1 |
| 3 | User declines install | Git-only fallback — capability matrix below |

### Tier 3 capability matrix (git protocol only — honest limits)

| Operation | Possible via git? | Behavior |
|-----------|-------------------|----------|
| Create issue | **No** — issues live in GitHub's database, unreachable via git protocol | Emit a paste-ready issue body (rendering schema: `references/phases/create.md` §Rendering schema) to a local file + print the repo's New-issue web URL (`https://github.com/<owner>/<repo>/issues/new`) for the user to submit manually |
| Label / classify | **No** | Report skipped with a note; include the detected label names in the emitted body for manual application |
| Progress comment | **No** | Report skipped with a note |
| Close ticket | **Yes, indirectly** | `Closes #<num>` / `Fixes #<num>` / `Resolves #<num>` in a commit message closes the issue server-side when the commit lands on the default branch (GitHub parses keywords on push — no `gh` needed) |
| Ticket-key plumbing (branches/commits) | **Yes, fully** | Key formats below work in branch names and commit footers with plain git |

## Commands (tier 1)

> Requires bash (git-bash/WSL on Windows).

```bash
# Create (single) — author = gh auth user; @me self-assigns the same identity
ISSUE_URL=$(gh issue create --title "$TITLE" --body "$FORMATTED_BODY" \
  --label "$LABELS" --assignee @me)
ISSUE_NUMBER=$(echo "$ISSUE_URL" | grep -oE '[0-9]+$')

# Create (parent + sub-issues): repeat, appending "Parent: #$PARENT_NUMBER"
# to each sub-issue body (no native hierarchy — body refs / task lists only).

# Read for classification
gh issue view <issue-number> --json title,body,labels

# Assign labels
gh issue edit <issue-number> --add-label "<label1>,<label2>"

# Progress comment (house template per references/phases/update.md)
gh issue comment <num> --body-file <file>

# Verify
gh issue view <issue-number> --jq '.labels[].name'
```

Prerequisite: `gh` authenticated with write access to the repository.

## Label vocabulary

**Type labels** — `bug` #d73a4a · `enhancement` #a2eeef · `documentation` #0075ca · `duplicate` #cfd3d7 · `good first issue` #7057ff · `help wanted` #008672 · `invalid` #e4e669 · `question` #d876e3 · `wontfix` #ffffff

**Priority labels** — `priority: critical` #b60205 (system down, data loss, security) · `priority: high` #d93f0b (major feature broken) · `priority: medium` #fbca04 (workaround exists; default) · `priority: low` #0e8a16 (cosmetic, minor)

**Semver labels (PRs ONLY)** — `major` #d73a4a (breaking) · `minor` #fbca04 (features) · `patch` #0e8a16 (fixes/docs/refactoring)

### Keyword signals (intent signals, not substring matches)

- **bug**: fix, error, broken, crash, fail, doesn't work, incorrect, regression
- **enhancement**: add, implement, create, new, feature, support, request
- **documentation**: document, readme, docs, guide, tutorial, manual
- **duplicate**: duplicate, same as, already exists, already reported
- **good first issue**: beginner, simple, easy, small, straightforward, newcomer
- **help wanted**: help wanted, need help, assistance, collaboration
- **invalid**: not an issue, wrong repo, user error, misunderstanding
- **question**: question, how, what, why, clarification
- **wontfix**: wontfix, out of scope, not feasible, declined
- **priority: critical**: system down, data loss, security, vulnerability, outage
- **priority: high**: blocking, unusable, major broken, regression (severity)
- **priority: medium**: default when no other priority matches
- **priority: low**: minor, cosmetic, nice to have, nit, typo

> **In-skill sync contract:** the priority keyword list mirrors
> `references/jira.md` §Vocabulary (JIRA priority detection). Update both
> together — they live in one skill now, drift is still possible.

### Auto-create missing labels (machine-readable source)

> Requires bash (git-bash/WSL on Windows).

```bash
declare -A LABELS=(
  ["bug"]="d73a4a,Something isn't working"
  ["enhancement"]="a2eeef,New feature or request"
  ["documentation"]="0075ca,Improvements or additions to documentation"
  ["duplicate"]="cfd3d7,This issue or pull request already exists"
  ["good first issue"]="7057ff,Good for newcomers"
  ["help wanted"]="008672,Extra attention is needed"
  ["invalid"]="e4e669,This doesn't seem right"
  ["question"]="d876e3,Further information is requested"
  ["wontfix"]="ffffff,This will not be worked on"
  ["priority: critical"]="b60205,System down, data loss, security vulnerability"
  ["priority: high"]="d93f0b,Major feature broken, significant user impact"
  ["priority: medium"]="fbca04,Functional issue with workaround"
  ["priority: low"]="0e8a16,Minor inconvenience, cosmetic issue"
  ["major"]="d73a4a,Breaking change (X.0.0)"
  ["minor"]="fbca04,New feature (0.X.0)"
  ["patch"]="0e8a16,Bug fix (0.0.X)"
)
existing_labels=$(gh label list --json name --jq '.[].name')
for label in "${!LABELS[@]}"; do
  if ! echo "$existing_labels" | grep -qx "$label"; then
    IFS=',' read -r color desc <<< "${LABELS[$label]}"
    gh label create "$label" --color "$color" --description "$desc" 2>/dev/null || true
  fi
done
```

Intended behavior: seeds this fixed 16-label taxonomy into any repo it runs
in — the consistent baseline. Existing custom labels coexist untouched.

### Semver label rule (PRs only — structural, not content)

Governance: definitions follow `semantic-release-convention-skill` (single
source of truth for version-bump conventions) — cited here, never redefined.

> Requires bash (git-bash/WSL on Windows).

```bash
if [[ "$pr_title" =~ ^[^:]+\! ]]; then labels+=("major")
elif [[ "$pr_title" =~ ^feat ]];     then labels+=("minor")
else                                      labels+=("patch")
fi
```

## Epic / parent grouping

- **Portable floor**: children carry a `Parent: #N` body line (SKILL.md
  §Create) — works on every plan, parses with plain gh.
- **Native sub-issues**: GitHub tracks parent/child natively via the
  sub-issue API (GraphQL `addSubIssue`). *Verify locally: confirm the
  org's plan supports sub-issues before relying on the API — the body-ref
  link is the floor that always works.*
- An epic is a normal parent issue — no special type or label required;
  keep the epic's Acceptance Criteria as the union of its children's.

## Attribution (author/assignee)

- The issue author is the `gh auth` user by construction (token owner —
  GitHub does not allow spoofing); `--assignee @me` self-assigns the same
  identity.
- `git config user.name`/`user.email` are NOT valid assignee sources
  (display name, not a login; email may be a private noreply address).

## Ticket key format

- Issue ref: `#123`; cross-repo `owner/repo#123`
- Commit message reference: `#123` (GitHub auto-links), closing keywords `Closes #123` / `Fixes #123` / `Resolves #123`
- Branch: `feat/123` or `feat/GIT-123` (bare number or `GIT-` prefix; PLAN resolution per `plan-execution-skill` normalizes both to `PLANS/PLAN-<num>.md`) — *verify locally: this repo's convention is `feat/<num>`*

## Issue templates

`templates/` (shipped with this skill): `bug_report.yml`, `feature_request.yml`,
`config.yml`. Field labels in SKILL.md §Create match these files verbatim —
agent-created and form-created tickets are structurally identical.
`opencode-repo-setup-skill` copies them into `<repo>/.github/ISSUE_TEMPLATE/`
on request (create-if-absent only).
