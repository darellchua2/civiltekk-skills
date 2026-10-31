# Patterns route (values)

Battle-tested patterns for FastAPI + Pydantic v2 + SQLAlchemy/asyncpg backends, extracted from production incidents across multiple repos. Each pattern caused a real bug and has a concrete fix. The host SKILL.md carries the METHOD (detect → route → load); this file carries the VALUES for the `patterns` route.

<!-- Provenance: canvastekk-workflow-engine + canvastekk-defect-service LEARNINGS. PLAN-GIT-312. Excludes 12 patterns already in the scaffold route, code-principles-skill route `design-patterns`, code-principles-skill route `object-design`. -->

**Scope:** writing or reviewing FastAPI endpoints (especially async sessions); configuring Pydantic v2 models, validators, serializers; writing Alembic migrations (especially asyncpg + JSONB); auditing multi-tenant isolation or auth flows; debugging race conditions in state transitions; reviewing error handling in service-to-service calls.

**Related:** project scaffolding → `references/scaffold.md` in this skill · `database-migration-skill` (migration workflow patterns; this file covers the asyncpg-specific pitfalls) · `security-audit-skill` (security auditing; this file covers the FastAPI-specific auth/encryption patterns).

## A. Pydantic v2 Conventions

### A1. Canonical Checklist

Use V2 APIs exclusively — the V1 compatibility layer is deprecated and hides bugs.

| Concern | V2 Correct | V1 Legacy (reject) |
|---------|-----------|-------------------|
| Config | `model_config = ConfigDict(...)` | `class Config:` |
| Extra fields | `extra="forbid"` on API boundary, `"ignore"` on embedded spec | `Extra.ignore` |
| Validators | `@field_validator`, `@model_validator` | `@validator` |
| Serialization | `.model_dump()`, `.model_validate()` | `.dict()`, `.parse_obj()` |
| Computed | `@computed_field` | `@property` only |
| Immutable | `model_config = ConfigDict(frozen=True)` | custom `__setattr__` |
| Serializer | `@field_serializer` / `@model_serializer` | `json_encoders` |
| Type adapter | `TypeAdapter[T]` for non-model validation | custom `parse_*` |
| Polymorphism | `SerializeAsAny[Base]` | manual discriminated unions |
| Rebuild | `model_rebuild()` after forward refs | silent failure |
| Name mode | `validate_by_name=True` (v2.11+) | `Config.allow_population_by_field_name` |
| Init hook | `model_post_init()` | `__init__` override |

### A2. Annotated Type Aliases for Reusable Constraints

```python
from typing import Annotated
from pydantic import Field, AfterValidator

Slug = Annotated[str, Field(min_length=1, max_length=128, pattern=r'^[a-z0-9-]+$')]
UuidStr = Annotated[str, Field(pattern=r'^[0-9a-f]{8}-[0-9a-f]{4}')]
PositiveInt = Annotated[int, Field(gt=0)]

# Composable with AfterValidator
TrimmedSlug = Annotated[Slug, AfterValidator(lambda s: s.strip())]
```

### A3. Drop `Field(...)` Ellipsis

```python
# BAD — ellipsis confuses type checkers, adds nothing
name: str = Field(..., min_length=1)

# GOOD — field without default is already required
name: str = Field(min_length=1)
```

---

## B. FastAPI Architecture

### B1. Layered Architecture (API → Service → Domain → Infra)

Routers must NEVER import DB or Temporal directly.

```
api/routers/     → request parsing, response serialization, HTTP status
services/        → business logic, orchestration, transactions
domain/          → pure models, no I/O, no framework deps
infrastructure/  → DB sessions, external API clients, Temporal workers
```

**Violation signal:** a router file imports `sqlalchemy` or `temporal`.

### B2. Multi-Source Response Schema Drift

When a response schema is constructed from multiple code paths (DB fast path + async slow path), a field added to one path but not the other causes silent `None` in production.

**Fix:** Use a factory/builder that accepts ALL data sources, or enforce a single construction path.

---

## C. ORM & Migration Pitfalls

### C1. Migration Syntax Errors Invisible to pytest

Alembic loads migration files dynamically — `SyntaxError` passes all tests and crashes at deploy.

```python
# tests/test_migrations_compile.py
import py_compile, glob

def test_all_migrations_compile():
    for path in glob.glob("alembic/versions/*.py"):
        py_compile.compile(path, doraise=True)
```

### C2. N+1 Enrichment Queries

```python
# BAD — one query per item
for defect in defects:
    defect.files = await get_files(defect.id)

# GOOD — batch fetch with IN clause
all_files = await get_files_for_ids([d.id for d in defects])
files_by_defect = defaultdict(list)
for f in all_files:
    files_by_defect[f.defect_id].append(f)
for d in defects:
    d.files = files_by_defect.get(d.id, [])
```

### C3. Two-Step Lookup (UUID then slug+is_latest)

Versioned tables with both UUID PK and natural-key slug need a two-step query to avoid `MultipleResultsFound`:

```python
# Step 1: exact ID match (any version)
definition = await session.get(Definition, definition_id)
if not definition:
    # Step 2: slug + is_latest=True fallback
    definition = await session.scalar(
        select(Definition).where(
            Definition.slug == slug, Definition.is_latest.is_(True)
        )
    )
```

---

## D. Defensive Coding

### D1. Broad `except Exception` Masks Bugs

```python
# BAD — swallows programming errors as "unreachable"
try:
    result = await service.call()
except Exception:
    pass  # hides bugs

# GOOD — narrow catches, let bugs propagate
from httpx import ConnectError, TimeoutException
try:
    result = await service.call()
except (ConnectError, TimeoutException):
    retry()
# Programming errors (KeyError, AttributeError) propagate to Sentry
```

**Rule:** Never swallow unexpected exceptions in auth/security paths — fail closed.

### D2. Auth Early-Return on NULL Optional Input

```python
# BAD — skips auth check when account_id is missing
async def handler(account_id: str | None = Header(None)):
    if account_id:
        account = await validate_account(account_id)
    # proceeds without validation if account_id is None

# GOOD — separate null-resource-allow from null-caller-skip
async def handler(account_id: str | None = Header(None)):
    caller = await get_caller()
    if account_id is None:
        return await list_public_resources(caller)
    account = await validate_account(account_id, caller)
    # always validates ownership
```

### D3. Encryption Key Length Validation at Config Time

```python
# BAD — base64-valid but wrong byte length; crashes at first encrypt()
key = base64.b64decode(settings.encryption_key_b64)

# GOOD — validate decoded length at startup
key = base64.b64decode(settings.encryption_key_b64)
if len(key) != 32:
    raise ValueError(f"Expected 32-byte AES-256 key, got {len(key)}")
```

### D4. Fail-Closed/Fail-Open via Single Config Toggle

```python
# One boolean governs the fail branch
if not settings.STRICT_ACCOUNT_VALIDATION:
    # Fail-open: log and proceed (dev/staging)
    logger.warning("Auth service unavailable, failing open")
else:
    # Fail-closed: deny request (production)
    raise HTTPException(403)
```

Reinforce with circuit breaker + positive cache on the external auth service.

---

## E. Multi-Tenant Security

### E1. Missing Tenant Isolation

Every multi-tenant table MUST have `tenant_id` with filtered queries. Metadata leak is still a breach.

```python
# BAD — no tenant filter on a shared table
definitions = await session.execute(select(Definition))

# GOOD — always filter by tenant
definitions = await session.execute(
    select(Definition).where(Definition.tenant_id == caller.tenant_id)
)
```

---

## F. Concurrency & Caching

### F1. Claim-Check Pattern for Ephemeral Secret Caching

When secrets cross durable workflow history (Temporal, Celery), never pass the raw secret. Store in a TTL cache keyed by opaque UUID; pass only the claim ID; `pop()` for single-read semantics.

```python
_secret_cache: dict[str, tuple[bytes, float]] = {}

def store_secret(secret: bytes, ttl: float = 300) -> str:
    claim_id = str(uuid4())
    _secret_cache[claim_id] = (secret, time.monotonic() + ttl)
    return claim_id

def claim_secret(claim_id: str) -> bytes | None:
    entry = _secret_cache.pop(claim_id, None)
    if entry and entry[1] > time.monotonic():
        return entry[0]
    return None
```

**Caveat:** `_secret_cache` is not thread-safe. For multi-worker deployments, wrap access in `threading.Lock` or use a TTL'd Redis key.

### F2. Placeholder Swap for Transport Value Validation

When validating inputs containing URI/ref values (s3://, CDS) that strict JSON Schema rejects:

```python
PLACEHOLDER = "__SCHEMA_PLACEHOLDER__"

def validate_with_swap(data: dict) -> dict:
    originals = {}
    try:
        for key, val in data.items():
            if isinstance(val, str) and "://" in val:
                originals[key] = val
                data[key] = PLACEHOLDER
        validate(data)  # strict schema
        return data
    finally:
        data.update(originals)  # restore originals
```

---

## G. Operational Patterns

### G1. Hardcoded Magic Timeout

```python
# BAD — hardcoded, can't tune per-environment
result = await client.get(url, timeout=30.0)

# GOOD — configurable, per-entity override
result = await client.get(url, timeout=settings.http_timeout)
```

### G2. Inline Imports — Fix Architecture, Don't Hide

```python
# BAD — hides circular dependency
def process(data):
    from app.services import HeavyService  # inline import = smell
    return HeavyService().run(data)

# GOOD — fix the cycle, use TYPE_CHECKING for type-only imports
from typing import TYPE_CHECKING
if TYPE_CHECKING:
    from app.services import HeavyService
```
