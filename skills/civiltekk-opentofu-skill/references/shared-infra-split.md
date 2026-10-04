# Route: shared-infra-split

Provision-once shared modules vs per-env stacks, and live migrations between
the two. Reference implementations: `canvastekk-simplified-ecr-infra` (ECR),
`canvastekk-simplified-amplify-infra` (Amplify app + branches + domain),
`tofu-state-management-resource` (state locking).

## Ownership decision table

| Resource shape | Owner | Examples |
|---|---|---|
| Singleton consumed by every env; survives env teardowns | shared module (one state) | ECR repos, Amplify app + branches + domain association, OIDC provider, Route53 zone + SES identity, state bucket/lock |
| Env-scoped runtime resource; dies with the env | env stack (one state per env) | lambdas, app roles, env secrets, per-env DNS records, watchers |
| Rule of thumb | anything an `aws_amplify_*`-style service-API resource → shared module; anything IAM/secret/DNS per env → env stack | |

Consumers reference shared resources by output + SSM pointer param
(`/canvastekk/{service}/{thing-id}`), never by cross-state reads or
duplicating the resource.

## Shared-module contracts

- No `environment` variable — the module is env-agnostic. State key has NO
  `-ENV` suffix (`CANVASTEKK-<module-name>/terraform.tfstate`); env-suffixed
  keys on an env-agnostic module produce dual-claimant states.
- Workflow offers `plan`/`apply` only — no `destroy` input (state-mgmt
  pattern). Crown-jewel resources carry `prevent_destroy`; removing THAT
  lifecycle first is the deliberate teardown act.
- Per-env variation inside the shared module is `for_each` over an env map
  (branch specs, webhook per branch), env values from per-env SSM paths
  (`/canvastekk/{service}/{env}/{secret}`).
- Ordering-coupled resources (e.g. `aws_amplify_domain_association` subdomains
  → branches) MUST live in the same state so one apply creates targets before
  referents. Cross-state subdomain management is an anti-pattern.

## Migration recipe (live resource → shared module)

1. Author the shared module with the resource + its dependents.
2. Strip the resource blocks from the owning env stack; `git rm` beats
   gating — config removal plans a clean destroy of exactly those resources.
3. Apply the env stack (destroys; frees service-global names like domains).
4. Wait for async deprovision (e.g. Amplify domain detach polls to
   NotFoundException) before the shared-module apply re-claims the name.
5. Apply the shared module; create fresh (or `tofu import` when the id must
   survive). Never two states claim one resource at any point.
6. Point consumers at the new outputs/SSM pointer; bump their vars in the
   same change series.

## Traps

- `for_each` rejects sensitive-derived keys — a gate like
  `local.create = data.aws_ssm_parameter.token.value != ""` is sensitive and
  fails validate inside for_each (count tolerates it). Either use count or
  drop the gate: a bad token fails loudly at apply anyway.
- Env-keyed workflows dispatching an env-agnostic module create a second
  state claiming the same live resources — fix the state key or the gate
  before any dispatch.
