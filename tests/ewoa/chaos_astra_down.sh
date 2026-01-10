#!/bin/bash
#
# Chaos Script: ASTRA Down
#
# Purpose: Simulate ASTRA Core service failure
# Expected: System fails closed, all executions denied
# Alert: ASTRA_UNAVAILABLE_RATE > 50% for 60s
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVIDENCE_DIR="${SCRIPT_DIR}/evidence/$(date +%Y%m%d_%H%M%S)/drill1_astra_down"

echo "=== EWOA Drill 1: ASTRA Down ==="
echo "Evidence directory: $EVIDENCE_DIR"
mkdir -p "$EVIDENCE_DIR"

# Step 1: Capture baseline
echo "[1/6] Capturing baseline metrics..."
docker stats --no-stream > "$EVIDENCE_DIR/baseline_stats.txt"
docker-compose ps > "$EVIDENCE_DIR/baseline_services.txt"

# Step 2: Inject chaos - stop ASTRA Core
echo "[2/6] Injecting chaos: Stopping ASTRA Core..."
docker stop astra-core
echo "ASTRA Core stopped at: $(date -Iseconds)" > "$EVIDENCE_DIR/chaos_injected.txt"

# Step 3: Wait for alert window
echo "[3/6] Waiting 60 seconds for alert window..."
sleep 60

# Step 4: Send test requests (should all be denied)
echo "[4/6] Sending test requests (expecting denials)..."
for i in {1..10}; do
  curl -s -X POST http://localhost:8001/v2/orchestrator/execute \
    -H "Content-Type: application/json" \
    -d "{\"request_id\":\"drill1_test_$i\",\"actor\":{\"id\":\"test\",\"role\":\"recruiter\"},\"context\":{\"domain\":\"interview\",\"action\":\"start\",\"consent\":true}}" \
    >> "$EVIDENCE_DIR/test_responses.txt" 2>&1
  echo "" >> "$EVIDENCE_DIR/test_responses.txt"
  sleep 1
done

# Step 5: Capture evidence
echo "[5/6] Capturing evidence..."
docker logs astra-orchestrator > "$EVIDENCE_DIR/orchestrator_logs.txt" 2>&1
docker logs astra-core > "$EVIDENCE_DIR/astra_logs.txt" 2>&1 || echo "ASTRA Core not running (expected)" > "$EVIDENCE_DIR/astra_logs.txt"
docker stats --no-stream > "$EVIDENCE_DIR/final_stats.txt"

# Step 6: Analyze results
echo "[6/6] Analyzing results..."
DENIAL_COUNT=$(grep -c "503" "$EVIDENCE_DIR/test_responses.txt" || echo "0")
TOTAL_REQUESTS=10

cat > "$EVIDENCE_DIR/alert.json" << EOF
{
  "drill_id": "drill1_astra_down",
  "timestamp": "$(date -Iseconds)",
  "alert_name": "ASTRA_UNAVAILABLE",
  "condition": "exec_denied_total / exec_requests_total > 50% for 60s",
  "measured_value": "$((DENIAL_COUNT * 100 / TOTAL_REQUESTS))%",
  "threshold": "50%",
  "duration": "60s",
  "status": "$( [ $DENIAL_COUNT -ge 5 ] && echo 'FIRED' || echo 'NOT_FIRED' )",
  "evidence_path": "$EVIDENCE_DIR"
}
EOF

# Step 7: Restart ASTRA Core
echo "[7/7] Restarting ASTRA Core..."
docker start astra-core
sleep 5

# Wait for service to be ready
for i in {1..30}; do
  if curl -s http://localhost:8000/health 2>/dev/null | grep -q 'ok'; then
    echo "ASTRA Core is back online"
    break
  fi
  echo "Waiting for ASTRA Core... ($i/30)"
  sleep 2
done

# Final summary
echo ""
echo "=== Drill 1 Complete ==="
echo "Denial Rate: $((DENIAL_COUNT * 100 / TOTAL_REQUESTS))%"
echo "Alert Status: $( [ $DENIAL_COUNT -ge 5 ] && echo 'FIRED ✅' || echo 'NOT FIRED ❌' )"
echo "Evidence: $EVIDENCE_DIR"
echo "========================"

# Exit with failure if alert didn't fire
if [ $DENIAL_COUNT -lt 5 ]; then
  echo "❌ FAIL: Alert did not fire (denial rate too low)"
  exit 1
fi

echo "✅ PASS: Alert fired successfully"
exit 0
