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

## CI/CD Guardrails

This repository contains the implementation of CI/CD guardrails for the ASTRA TAWZEEF production system. The primary objective of this system is to ensure the stability and reliability of the production environment by automatically preventing deployments that violate the defined Service Level Agreements (SLAs).

### System Overview

The CI/CD guardrail system is implemented as a set of GitHub Actions workflows that are triggered on every push to the `main` branch. The system performs the following actions:

1.  **Static Code Analysis:** A static analysis of the code is performed to identify any potential issues or vulnerabilities.
2.  **Service Deployment:** The ASTRA TAWZEEF services are deployed to a clean environment using Docker Compose.
3.  **Latency Load Testing:** A latency load test is performed using k6 to measure the p95 latency of the system.
4.  **SLA Violation Check:** The p95 latency is compared against the defined SLA of 100ms. If the latency exceeds the SLA, the deployment is blocked.
5.  **NCR/CAPA Generation:** In the event of an SLA violation, a Non-Conformance Report (NCR) and a Corrective and Preventive Action (CAPA) report are automatically generated and committed to the repository.

### EWOA Fire Drill

An Emergency Workaround Authorization (EWOA) fire drill has been implemented to validate the failure detection and response mechanisms of the CI/CD guardrail system. The fire drill simulates a production incident by intentionally introducing a latency regression into the system. The fire drill performs the following actions:

1.  **Baseline Test:** A baseline k6 load test is executed to establish the normal performance of the system.
2.  **Overload Test:** An overload k6 load test is executed to simulate a production incident and trigger the latency SLA violation.
3.  **Chaos Tests:** A series of chaos tests are performed to validate the resilience of the system to various failure modes, including:
    *   ASTRA Core service failure
    *   PostgreSQL database failure
    *   PostgreSQL database latency
4.  **Evidence Packaging:** The logs and other evidence from the fire drill are packaged into a bundle for analysis.
5.  **Evidence Commit:** The evidence bundle is committed to the repository for future reference.

#### EWOA Fire Drill Validation

The EWOA fire drill was successfully validated, and the system performed as expected. The overload test successfully triggered the latency SLA violation, and the system automatically generated the NCR and CAPA reports. The chaos tests also demonstrated the resilience of the system to various failure modes.

### How to Use

To use the CI/CD guardrail system, simply push your changes to the `main` branch. The system will automatically perform the necessary checks and block the deployment if any issues are detected.

To run the EWOA fire drill, navigate to the "Actions" tab in the GitHub repository, select the "EWOA Fire Drill" workflow, and click "Run workflow".
