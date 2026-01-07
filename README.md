# ASTRA / TAWZEEF — PROD v1 (كود + نشر)

حزمة تشغيل Minimal تلتزم بـ:
- One request → one ASTRA decision → one artifact
- Low latency (single-zone)
- Fail-closed
- No retries / no async
- Real policy-driven authorization

## تشغيل محلي (Docker Compose)

```bash
cd astra_taw_prod_v1
docker compose up --build
```

## نقاط الخدمة

### ASTRA Core
- **Health:** `GET http://localhost:8000/health`
- **Authority Check:** `POST http://localhost:8000/v1/astra/authority/check`
- **Port:** 8000

### Orchestrator
- **Health:** `GET http://localhost:8001/health`
- **Execute:** `POST http://localhost:8001/v2/orchestrator/execute`
- **Port:** 8001

### Watcher
- **Health:** `GET http://localhost:8002/health`
- **Submit:** `POST http://localhost:8002/v2/watcher/submit`
- **Port:** 8002 (مقفول افتراضيًا)

## Test Payloads

### ✅ ALLOW: Interview Start (with consent)

```bash
curl -X POST http://localhost:8001/v2/orchestrator/execute \
  -H "Content-Type: application/json" \
  -d '{
    "request_id":"11111111-1111-1111-1111-111111111111",
    "actor":{"id":"recruiter-1","role":"recruiter"},
    "context":{"domain":"interview","action":"start","consent":true}
  }'
```

**Expected Response:**
```json
{
  "execution_id": "<uuid>",
  "astra_decision_id": "<uuid>",
  "outcome": "EXECUTED"
}
```

### ❌ DENY: Interview Start (without consent)

```bash
curl -X POST http://localhost:8001/v2/orchestrator/execute \
  -H "Content-Type: application/json" \
  -d '{
    "request_id":"22222222-2222-2222-2222-222222222222",
    "actor":{"id":"recruiter-1","role":"recruiter"},
    "context":{"domain":"interview","action":"start"}
  }'
```

**Expected Response:**
```json
{
  "outcome": "DENY",
  "astra_decision_id": "<uuid>"
}
```

### ❌ DENY: Watcher Submit (without delegation_token)

```bash
curl -X POST http://localhost:8002/v2/watcher/submit \
  -H "Content-Type: application/json" \
  -d '{
    "request_id":"33333333-3333-3333-3333-333333333333",
    "watcher":{"id":"watcher-1"},
    "actor":{"id":"watcher-1","role":"watcher"},
    "context":{"domain":"watcher","action":"submit"}
  }'
```

**Expected Response:**
```json
{
  "detail": "DENY"
}
```

## Policy Pack

The policy pack is defined in `services/astra_core/policy_pack.json`:

```json
{
  "version": "1.0.0",
  "domains": {
    "interview": {
      "actions": {
        "start": {
          "allow_roles": ["recruiter", "system"],
          "requires": ["consent"]
        },
        "terminate": {
          "allow_roles": ["recruiter", "system", "astra"],
          "requires": ["consent"]
        }
      }
    },
    "watcher": {
      "actions": {
        "submit": {
          "allow_roles": ["watcher"],
          "requires": ["delegation_token"]
        }
      }
    }
  }
}
```

## Database

PostgreSQL schema is initialized from `migrations/001_ddl_v2.sql`:

- `astra_decision_artifacts` — Authorization decisions
- `tawzeef_execution_artifacts` — Execution records
- `tawzeef_watcher_artifacts` — Watcher observations

## Metrics

Optional StatsD metrics (fire-and-forget):
- `astra_decision_latency_ms` — Decision latency
- `astra_requests_total` — Total requests
- `astra_outcome_total` — Outcome distribution
- `exec_requests_total` — Execution requests
- `exec_denied_total` — Denied executions
- `exec_astra_latency_ms` — ASTRA call latency
- `exec_db_insert_latency_ms` — Database insert latency
- `exec_total_latency_ms` — Total execution latency
- `watch_requests_total` — Watcher requests
- `watch_db_insert_latency_ms` — Watcher database insert latency
- `watch_total_latency_ms` — Total watcher latency

## Architecture

```
Client
  ↓
Orchestrator (Port 8001)
  ↓
ASTRA Core (Port 8000) ← Policy Pack (policy_pack.json)
  ↓
PostgreSQL (Port 5432)
  ↓
Artifacts (astra_decision_artifacts, tawzeef_execution_artifacts, tawzeef_watcher_artifacts)
```

## Deployment

1. Copy all files to production server
2. Update `docker-compose.yml` environment variables (database password, etc.)
3. Run `docker compose up -d`
4. Verify health endpoints
5. Test with provided payloads

## Guardrails

CI/CD enforces:
- No async/await
- No retries
- No threading/multiprocessing
- No Celery/RQ

See `.github/workflows/ci.yml` for details.

