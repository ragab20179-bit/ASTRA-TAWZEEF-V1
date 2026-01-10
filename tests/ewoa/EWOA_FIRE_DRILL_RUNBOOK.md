# EWOA Fire Drill Runbook
## Early Warning & Operation Alarm Testing

**Version:** 1.0  
**Date:** January 10, 2026  
**Status:** OPERATIONAL  
**Author:** Manus AI

---

## 1. Purpose

This runbook defines the complete process for executing EWOA (Early Warning & Operation Alarm) fire drills and chaos tests to validate that the ASTRA TAWZEEF system can **detect, alert, and provide evidence** for failure scenarios before they impact users.

**Core Principle:** EWOA is a smoke detector, not a firefighter. It measures signals and triggers alarms.

---

## 2. What We're Testing

**Every drill must produce:**
1. ✅ **Observable metrics** (captured in logs/StatsD)
2. ✅ **Alert condition hit** (verified threshold breach)
3. ✅ **Evidence artifact** (JSON report + logs committed to repo)

**We are NOT testing:**
- System recovery (that's a different test)
- Manual intervention procedures
- Production deployment

**We ARE testing:**
- Detection accuracy
- Alert timing
- Evidence completeness

---

## 3. Drill Scenarios

### Drill 1: ASTRA Down (Fail-Closed)

**Objective:** Verify system fails closed when ASTRA Core is unavailable

**Inject:**
```bash
docker stop astra-core
```

**Expected Behavior:**
- ✅ Orchestrator returns `503 ASTRA_UNAVAILABLE`
- ✅ No execution artifacts inserted into database
- ✅ Metrics spike: `exec_denied_total` and `exec_astra_latency_ms` (timeouts)
- ✅ EWOA alert: `ASTRA_UNAVAILABLE_RATE > threshold` for 60s

**Pass Criteria:**
- Alert fires within 60 seconds
- No successful executions recorded
- Evidence bundle contains: alert timestamp, denial count, timeout metrics

**Fail Criteria:**
- System continues executing without ASTRA
- No alert fires
- Silent failures (200 OK but no artifact)

---

### Drill 2: Postgres Latency (Hot Path Regression)

**Objective:** Verify system detects database performance degradation

**Inject:**
```bash
# Add 50ms delay to Postgres network
tc qdisc add dev eth0 root netem delay 50ms
```

**Expected Behavior:**
- ✅ P95/P99 insert latency rises
- ✅ Total request P95 rises
- ✅ NO retries introduced (important!)
- ✅ System remains consistent (but slower)
- ✅ EWOA alert: `exec_db_insert_latency_ms_p95 > budget` (10-15ms local) for 120s

**Pass Criteria:**
- Alert fires within 120 seconds
- Latency increase measured and recorded
- No retries detected in logs
- All transactions remain consistent

**Fail Criteria:**
- No alert despite latency increase
- Retries introduced (violates ASTRA policy)
- Data corruption or inconsistency

---

### Drill 3: Postgres Down (Hard Failure)

**Objective:** Verify system fails closed when database is unavailable

**Inject:**
```bash
docker stop postgres
```

**Expected Behavior:**
- ✅ ASTRA inserts fail → ASTRA must deny (fail-closed)
- ✅ Orchestrator execution must stop
- ✅ Errors visible in logs
- ✅ EWOA alert: `DB_CONNECT_ERRORS > threshold` for 30s

**Pass Criteria:**
- Alert fires within 30 seconds
- All execution requests denied
- No partial writes or orphaned artifacts
- Evidence bundle contains: connection error logs, denial count

**Fail Criteria:**
- System continues without database
- Partial writes occur
- No alert fires

---

### Drill 4: Orchestrator Overload (Capacity)

**Objective:** Verify system handles load beyond designed capacity gracefully

**Inject:**
```bash
# k6 load test exceeding designed QPS
k6 run --vus 50 --duration 2m tests/ewoa/02_k6_overload.js
```

**Expected Behavior:**
- ✅ Latency increases gradually
- ✅ Denials may increase if ASTRA timeout triggers
- ✅ NO meltdown (no cascading retries)
- ✅ EWOA alert: `exec_total_latency_ms_p95 > budget` + `error_rate > threshold`

**Pass Criteria:**
- Alert fires when latency exceeds budget
- System remains stable (no crash)
- No cascading failures
- Graceful degradation observed

**Fail Criteria:**
- System crashes or becomes unresponsive
- Cascading retries introduced
- No alert despite overload

---

### Drill 5: Watcher Abuse (Rate Limit / Throttling)

**Objective:** Verify watcher endpoint can handle abuse without impacting orchestrator

**Inject:**
```bash
# Spam watcher submit endpoint
ab -n 10000 -c 100 http://localhost:8002/v2/watcher/submit
```

**Expected Behavior:**
- ✅ Throttle kicks in (when enabled)
- ✅ Denials recorded
- ✅ No cross-service leak into orchestrator
- ✅ EWOA alert: `watch_requests_total` spike + `watch_denied_total` spike

**Pass Criteria:**
- Alert fires when rate limit exceeded
- Orchestrator performance unaffected
- Throttling mechanism works
- Evidence bundle contains: request rate, denial rate, throttle config

**Fail Criteria:**
- Watcher abuse impacts orchestrator
- No throttling occurs
- No alert fires

---

## 4. Metrics to Capture

**Minimum Required Metrics:**

| Metric | Description | Source |
|--------|-------------|--------|
| `astra_decision_latency_ms` | P50/P95/P99 ASTRA decision time | StatsD |
| `exec_astra_latency_ms` | Orchestrator → ASTRA latency | StatsD |
| `exec_db_insert_latency_ms` | Database insert latency | StatsD |
| `exec_total_latency_ms` | End-to-end execution latency | StatsD |
| `astra_requests_total` | Total ASTRA requests | StatsD |
| `astra_outcome_total` | ASTRA outcomes (ALLOW/DENY) | StatsD |
| `exec_requests_total` | Total execution requests | StatsD |
| `exec_denied_total` | Total execution denials | StatsD |
| `service_health` | Service up/down status | Docker |

**Capture Methods:**
1. **Container logs** (cheap, always available)
2. **StatsD + collector** (better, structured)
3. **k6 output** (for load tests)

---

## 5. Pass/Fail Criteria

### PASS means:

✅ Each drill triggers at least one EWOA alarm condition  
✅ Alarm contains: scenario ID, timestamp, measured value, threshold, affected service  
✅ No "success" recorded without artifacts  
✅ No retries introduced  
✅ Evidence bundle complete and committed  

### FAIL means:

❌ No alarm when failure is obvious  
❌ Alarm fires but no evidence bundle  
❌ Drill causes silent data corruption (worst)  
❌ Someone "fixed" it by adding retries (also worst)  
❌ System crashes or becomes unresponsive  

---

## 6. Execution Procedure

### Pre-Flight Checklist

- [ ] All services running (`docker-compose ps`)
- [ ] Baseline metrics captured
- [ ] Evidence directory created (`tests/ewoa/evidence/`)
- [ ] k6 installed and tested
- [ ] Chaos scripts tested in isolation

### Execution Steps

1. **Start services**
   ```bash
   docker-compose up -d
   ```

2. **Capture baseline**
   ```bash
   ./tests/ewoa/capture_metrics.sh baseline
   ```

3. **Run Drill 1: ASTRA Down**
   ```bash
   ./tests/ewoa/chaos_astra_down.sh
   ```

4. **Collect evidence**
   ```bash
   ./tests/ewoa/capture_metrics.sh drill1_astra_down
   ```

5. **Restart services**
   ```bash
   docker-compose restart
   ```

6. **Repeat for Drills 2-5**

7. **Package evidence bundle**
   ```bash
   ./tests/ewoa/package_evidence.sh
   ```

8. **Commit evidence to repo**
   ```bash
   git add tests/ewoa/evidence/
   git commit -m "EWOA: Fire drill evidence $(date +%Y%m%d)"
   git push origin main
   ```

---

## 7. Evidence Bundle Structure

**Each drill produces:**

```
tests/ewoa/evidence/YYYYMMDD_HHMMSS/
├── summary.json          # High-level results
├── drill1_astra_down/
│   ├── metrics.json      # Captured metrics
│   ├── logs.txt          # Container logs
│   ├── alert.json        # Alert details
│   └── k6_output.txt     # Load test results (if applicable)
├── drill2_pg_latency/
│   └── ...
└── ...
```

**summary.json format:**
```json
{
  "timestamp": "2026-01-10T00:00:00Z",
  "drills_executed": 5,
  "drills_passed": 5,
  "drills_failed": 0,
  "alerts_triggered": 5,
  "evidence_complete": true,
  "drills": [
    {
      "id": "drill1_astra_down",
      "status": "PASS",
      "alert_fired": true,
      "alert_timestamp": "2026-01-10T00:01:15Z",
      "measured_value": "100% denial rate",
      "threshold": "> 50% for 60s",
      "evidence_path": "tests/ewoa/evidence/20260110_000000/drill1_astra_down/"
    }
  ]
}
```

---

## 8. Alert Rules

**EWOA Alert Configuration:**

| Alert | Condition | Threshold | Duration | Severity |
|-------|-----------|-----------|----------|----------|
| `ASTRA_UNAVAILABLE` | `exec_denied_total / exec_requests_total` | > 50% | 60s | CRITICAL |
| `DB_LATENCY_HIGH` | `exec_db_insert_latency_ms_p95` | > 15ms | 120s | WARNING |
| `DB_UNAVAILABLE` | `DB_CONNECT_ERRORS` | > 10 | 30s | CRITICAL |
| `ORCHESTRATOR_OVERLOAD` | `exec_total_latency_ms_p95` | > 100ms | 60s | WARNING |
| `WATCHER_ABUSE` | `watch_requests_total` | > 1000/s | 30s | WARNING |

---

## 9. Troubleshooting

### Alert didn't fire

**Possible causes:**
- Threshold too high
- Duration too long
- Metrics not being captured
- Alert rule not configured

**Debug steps:**
1. Check metrics are being emitted: `docker logs astra-core | grep metrics`
2. Verify threshold: `cat tests/ewoa/EWOA_ALERT_RULES_v1.md`
3. Check alert evaluation: `docker logs ewoa-alertmanager`

### Drill failed unexpectedly

**Possible causes:**
- Services not fully started
- Network issues
- Resource constraints

**Debug steps:**
1. Check service health: `docker-compose ps`
2. Check logs: `docker-compose logs`
3. Check resources: `docker stats`

### Evidence bundle incomplete

**Possible causes:**
- Metrics capture script failed
- Insufficient disk space
- Permissions issue

**Debug steps:**
1. Check script output: `./tests/ewoa/capture_metrics.sh --debug`
2. Check disk space: `df -h`
3. Check permissions: `ls -la tests/ewoa/evidence/`

---

## 10. Continuous Integration

**GitHub Actions Workflow:**

The EWOA fire drill is automated via `.github/workflows/ewoa_fire_drill.yml`:

- **Trigger:** Manual (`workflow_dispatch`) or scheduled (weekly)
- **Duration:** ~15 minutes
- **Artifacts:** Evidence bundle uploaded as GitHub Actions artifact
- **Failure:** Opens NCR if any drill fails

**To run manually:**
```bash
gh workflow run ewoa_fire_drill.yml
```

---

## 11. Reporting

**After each fire drill:**

1. ✅ Evidence bundle committed to repo
2. ✅ Summary report generated
3. ✅ NCR opened if any drill failed
4. ✅ Results documented in vault: `01_Governance_and_QMS/Active/002-ASTRA/04-Failure_and_Abuse/`

**Monthly Review:**
- Analyze trends in alert timing
- Adjust thresholds if needed
- Update drill scenarios based on new failure modes

---

## 12. Success Metrics

**EWOA system is healthy when:**

- ✅ 100% of drills trigger alerts
- ✅ Alert timing < expected duration
- ✅ Evidence bundle complete for all drills
- ✅ No false positives in production
- ✅ No false negatives in drills

**EWOA system needs improvement when:**

- ❌ Drills don't trigger alerts
- ❌ Alert timing exceeds expected duration
- ❌ Evidence bundle incomplete
- ❌ False positives in production
- ❌ False negatives in drills

---

**Document End**
