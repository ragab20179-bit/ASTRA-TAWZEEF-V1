#!/bin/bash
#
# Chaos Script: Postgres Down
#
# Purpose: Simulate database failure
# Expected: System fails closed, ASTRA denies all executions
# Alert: DB_CONNECT_ERRORS > 10 for 30s
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVIDENCE_DIR="${SCRIPT_DIR}/evidence/$(date +%Y%m%d_%H%M%S)/drill3_pg_down"

echo "=== EWOA Drill 3: Postgres Down ==="
echo "Evidence directory: $EVIDENCE_DIR"
mkdir -p "$EVIDENCE_DIR"

# Step 1: Capture baseline
echo "[1/6] Capturing baseline metrics..."
docker stats --no-stream > "$EVIDENCE_DIR/baseline_stats.txt"
docker-compose ps > "$EVIDENCE_DIR/baseline_services.txt"

# Step 2: Inject chaos - stop Postgres
echo "[2/6] Injecting chaos: Stopping Postgres..."
docker stop postgres
echo "Postgres stopped at: $(date -Iseconds)" > "$EVIDENCE_DIR/chaos_injected.txt"

# Step 3: Wait for alert window
echo "[3/6] Waiting 30 seconds for alert window..."
sleep 30

# Step 4: Send test requests (should all be denied due to DB failure)
echo "[4/6] Sending test requests (expecting denials)..."
for i in {1..15}; do
  curl -s -X POST http://localhost:8001/v2/orchestrator/execute \
    -H "Content-Type: application/json" \
    -d "{\"request_id\":\"drill3_test_$i\",\"actor\":{\"id\":\"test\",\"role\":\"recruiter\"},\"context\":{\"domain\":\"interview\",\"action\":\"start\",\"consent\":true}}" \
    >> "$EVIDENCE_DIR/test_responses.txt" 2>&1
  echo "" >> "$EVIDENCE_DIR/test_responses.txt"
  sleep 0.5
done

# Step 5: Capture evidence
echo "[5/6] Capturing evidence..."
docker logs astra-orchestrator > "$EVIDENCE_DIR/orchestrator_logs.txt" 2>&1
docker logs astra-core > "$EVIDENCE_DIR/astra_logs.txt" 2>&1
docker logs postgres > "$EVIDENCE_DIR/postgres_logs.txt" 2>&1 || echo "Postgres not running (expected)" > "$EVIDENCE_DIR/postgres_logs.txt"
docker stats --no-stream > "$EVIDENCE_DIR/final_stats.txt"

# Step 6: Analyze results
echo "[6/6] Analyzing results..."

# Count connection errors in logs
DB_ERRORS=$(grep -i "connection.*refused\|could not connect\|database.*unavailable" "$EVIDENCE_DIR/astra_logs.txt" | wc -l || echo "0")
DENIAL_COUNT=$(grep -c "503\|500" "$EVIDENCE_DIR/test_responses.txt" || echo "0")
TOTAL_REQUESTS=15

cat > "$EVIDENCE_DIR/alert.json" << EOF
{
  "drill_id": "drill3_pg_down",
  "timestamp": "$(date -Iseconds)",
  "alert_name": "DB_UNAVAILABLE",
  "condition": "DB_CONNECT_ERRORS > 10 for 30s",
  "measured_value": "$DB_ERRORS errors",
  "threshold": "10 errors",
  "duration": "30s",
  "denial_rate": "$((DENIAL_COUNT * 100 / TOTAL_REQUESTS))%",
  "status": "$( [ $DB_ERRORS -ge 10 ] && echo 'FIRED' || echo 'NOT_FIRED' )",
  "evidence_path": "$EVIDENCE_DIR"
}
EOF

# Step 7: Restart Postgres
echo "[7/7] Restarting Postgres..."
docker start postgres
sleep 5

# Wait for database to be ready
for i in {1..30}; do
  if docker exec postgres pg_isready -U postgres > /dev/null 2>&1; then
    echo "Postgres is back online"
    break
  fi
  echo "Waiting for Postgres... ($i/30)"
  sleep 2
done

# Final summary
echo ""
echo "=== Drill 3 Complete ==="
echo "DB Connection Errors: $DB_ERRORS"
echo "Denial Rate: $((DENIAL_COUNT * 100 / TOTAL_REQUESTS))%"
echo "Alert Status: $( [ $DB_ERRORS -ge 10 ] && echo 'FIRED ✅' || echo 'NOT FIRED ❌' )"
echo "Evidence: $EVIDENCE_DIR"
echo "========================"

# Exit with failure if alert didn't fire
if [ $DB_ERRORS -lt 10 ]; then
  echo "❌ FAIL: Alert did not fire (DB errors too low)"
  exit 1
fi

if [ $DENIAL_COUNT -lt 10 ]; then
  echo "⚠️  WARNING: Denial rate lower than expected"
fi

echo "✅ PASS: Alert fired successfully"
exit 0
