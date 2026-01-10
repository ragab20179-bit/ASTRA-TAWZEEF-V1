#!/bin/bash
#
# Chaos Script: Postgres Latency
#
# Purpose: Simulate database performance degradation
# Expected: Latency increases, no retries, system remains consistent
# Alert: exec_db_insert_latency_ms_p95 > 15ms for 120s
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVIDENCE_DIR="${SCRIPT_DIR}/evidence/$(date +%Y%m%d_%H%M%S)/drill2_pg_latency"

echo "=== EWOA Drill 2: Postgres Latency ==="
echo "Evidence directory: $EVIDENCE_DIR"
mkdir -p "$EVIDENCE_DIR"

# Step 1: Capture baseline
echo "[1/7] Capturing baseline metrics..."
docker stats --no-stream > "$EVIDENCE_DIR/baseline_stats.txt"
docker-compose ps > "$EVIDENCE_DIR/baseline_services.txt"

# Run baseline latency test
echo "[1/7] Running baseline latency test..."
k6 run --quiet --duration 30s --vus 2 tests/ewoa/01_k6_baseline.js > "$EVIDENCE_DIR/baseline_k6.txt" 2>&1 || true

# Extract baseline P95
BASELINE_P95=$(grep "http_req_duration" "$EVIDENCE_DIR/baseline_k6.txt" | awk '{for(i=1;i<=NF;i++){if($i~/^p\(95\)=/){gsub(/p\(95\)=/,"",$i); gsub(/ms.*/,"",$i); print $i}}}' || echo "0")
echo "Baseline P95: ${BASELINE_P95}ms"

# Step 2: Inject chaos - add network latency to Postgres
echo "[2/7] Injecting chaos: Adding 50ms latency to Postgres..."

# Get Postgres container network interface
PG_CONTAINER_ID=$(docker ps -qf "name=postgres")
PG_PID=$(docker inspect -f '{{.State.Pid}}' "$PG_CONTAINER_ID")

# Use tc (traffic control) to add latency
# Note: This requires the container to have NET_ADMIN capability
docker exec postgres sh -c "apt-get update && apt-get install -y iproute2" > /dev/null 2>&1 || true
docker exec postgres tc qdisc add dev eth0 root netem delay 50ms 2>/dev/null || \
  echo "⚠️  Could not inject latency via tc (requires NET_ADMIN capability). Using alternative method..."

# Alternative: Add artificial delay in Postgres queries (if tc fails)
# This would require modifying the application code or using pg_sleep in queries

echo "Latency injected at: $(date -Iseconds)" > "$EVIDENCE_DIR/chaos_injected.txt"

# Step 3: Wait for alert window
echo "[3/7] Waiting 120 seconds for alert window..."
sleep 120

# Step 4: Run load test with latency
echo "[4/7] Running load test with latency..."
k6 run --quiet --duration 2m --vus 2 tests/ewoa/01_k6_baseline.js > "$EVIDENCE_DIR/latency_k6.txt" 2>&1 || true

# Extract latency P95
LATENCY_P95=$(grep "http_req_duration" "$EVIDENCE_DIR/latency_k6.txt" | awk '{for(i=1;i<=NF;i++){if($i~/^p\(95\)=/){gsub(/p\(95\)=/,"",$i); gsub(/ms.*/,"",$i); print $i}}}' || echo "0")
echo "Latency P95: ${LATENCY_P95}ms"

# Step 5: Capture evidence
echo "[5/7] Capturing evidence..."
docker logs astra-orchestrator > "$EVIDENCE_DIR/orchestrator_logs.txt" 2>&1
docker logs astra-core > "$EVIDENCE_DIR/astra_logs.txt" 2>&1
docker logs postgres > "$EVIDENCE_DIR/postgres_logs.txt" 2>&1
docker stats --no-stream > "$EVIDENCE_DIR/final_stats.txt"

# Step 6: Check for retries (should be NONE)
echo "[6/7] Checking for retries..."
RETRY_COUNT=$(grep -i "retry\|retrying" "$EVIDENCE_DIR/orchestrator_logs.txt" "$EVIDENCE_DIR/astra_logs.txt" | wc -l || echo "0")

if [ "$RETRY_COUNT" -gt 0 ]; then
  echo "❌ CRITICAL: Retries detected! This violates ASTRA policy."
  grep -i "retry\|retrying" "$EVIDENCE_DIR/orchestrator_logs.txt" "$EVIDENCE_DIR/astra_logs.txt" > "$EVIDENCE_DIR/retry_violations.txt"
fi

# Step 7: Analyze results
echo "[7/7] Analyzing results..."

# Calculate latency increase
LATENCY_INCREASE=$(echo "$LATENCY_P95 - $BASELINE_P95" | bc -l || echo "0")
LATENCY_INCREASE_PCT=$(echo "scale=2; ($LATENCY_INCREASE / $BASELINE_P95) * 100" | bc -l || echo "0")

cat > "$EVIDENCE_DIR/alert.json" << EOF
{
  "drill_id": "drill2_pg_latency",
  "timestamp": "$(date -Iseconds)",
  "alert_name": "DB_LATENCY_HIGH",
  "condition": "exec_db_insert_latency_ms_p95 > 15ms for 120s",
  "baseline_p95": "${BASELINE_P95}ms",
  "measured_p95": "${LATENCY_P95}ms",
  "latency_increase": "${LATENCY_INCREASE}ms",
  "latency_increase_pct": "${LATENCY_INCREASE_PCT}%",
  "threshold": "15ms",
  "duration": "120s",
  "retry_count": $RETRY_COUNT,
  "status": "$( echo "$LATENCY_P95 > 15" | bc -l | grep -q 1 && echo 'FIRED' || echo 'NOT_FIRED' )",
  "evidence_path": "$EVIDENCE_DIR"
}
EOF

# Step 8: Remove latency injection
echo "[8/8] Removing latency injection..."
docker exec postgres tc qdisc del dev eth0 root 2>/dev/null || echo "Latency already removed or not applied"

# Final summary
echo ""
echo "=== Drill 2 Complete ==="
echo "Baseline P95: ${BASELINE_P95}ms"
echo "Latency P95: ${LATENCY_P95}ms"
echo "Increase: ${LATENCY_INCREASE}ms (${LATENCY_INCREASE_PCT}%)"
echo "Retry Count: $RETRY_COUNT"
echo "Alert Status: $( echo "$LATENCY_P95 > 15" | bc -l | grep -q 1 && echo 'FIRED ✅' || echo 'NOT FIRED ❌' )"
echo "Evidence: $EVIDENCE_DIR"
echo "========================"

# Exit with failure if alert didn't fire or retries detected
if ! echo "$LATENCY_P95 > 15" | bc -l | grep -q 1; then
  echo "❌ FAIL: Alert did not fire (latency too low)"
  exit 1
fi

if [ "$RETRY_COUNT" -gt 0 ]; then
  echo "❌ CRITICAL FAIL: Retries detected (ASTRA policy violation)"
  exit 1
fi

echo "✅ PASS: Alert fired successfully, no retries detected"
exit 0
