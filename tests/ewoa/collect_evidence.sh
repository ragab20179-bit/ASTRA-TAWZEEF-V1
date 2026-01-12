#!/bin/bash
set -euo pipefail

# Evidence Collection Script for EWOA Fire Drill
# Collects metrics from k6 summary JSON files and generates evidence bundle

BASELINE_SUMMARY="${1:-/tmp/k6-baseline-summary.json}"
OVERLOAD_SUMMARY="${2:-/tmp/k6-overload-summary.json}"
OUTPUT_FILE="${3:-/tmp/ewoa_evidence_bundle.json}"

echo "Collecting EWOA evidence..."
echo "Baseline summary: $BASELINE_SUMMARY"
echo "Overload summary: $OVERLOAD_SUMMARY"
echo "Output file: $OUTPUT_FILE"

# Check if summary files exist
if [ ! -f "$BASELINE_SUMMARY" ]; then
  echo "ERROR: Baseline summary file not found: $BASELINE_SUMMARY"
  exit 1
fi

if [ ! -f "$OVERLOAD_SUMMARY" ]; then
  echo "ERROR: Overload summary file not found: $OVERLOAD_SUMMARY"
  exit 1
fi

# Extract metrics from overload test (primary test for SLA evaluation)
P95_LATENCY=$(jq -r '.metrics.http_req_duration.values["p(95)"] // 0' "$OVERLOAD_SUMMARY")
HTTP_FAIL_RATE=$(jq -r '.metrics.http_req_failed.values.rate // 0' "$OVERLOAD_SUMMARY")

# Custom metric: denials (defensive)
DENIAL_COUNT=$(jq -r '
  .metrics.denials.values.count //
  .metrics.denials.values["count"] //
  0
' "$OVERLOAD_SUMMARY")

ITERATIONS=$(jq -r '.metrics.iterations.values.count // 1' "$OVERLOAD_SUMMARY")
DENIAL_RATE=$(jq -n --argjson d "$DENIAL_COUNT" --argjson i "$ITERATIONS" 'if $i==0 then 0 else ($d / $i) end')

# Normalize numeric formatting
P95_LATENCY=$(printf "%.6f" "$P95_LATENCY")
HTTP_FAIL_RATE=$(printf "%.6f" "$HTTP_FAIL_RATE")
DENIAL_RATE=$(printf "%.6f" "$DENIAL_RATE")

echo "Extracted metrics:"
echo "  P95 Latency (ms): $P95_LATENCY"
echo "  HTTP Fail Rate:   $HTTP_FAIL_RATE"
echo "  Denial Rate:      $DENIAL_RATE"

# Determine SLA violations
LATENCY_VIOLATED=false
ERROR_VIOLATED=false
DENIAL_VIOLATED=false

# SLA thresholds
LATENCY_THRESHOLD=100.0
ERROR_THRESHOLD=0.1
DENIAL_THRESHOLD=0.05

if (( $(echo "$P95_LATENCY > $LATENCY_THRESHOLD" | bc -l) )); then
  LATENCY_VIOLATED=true
fi

if (( $(echo "$HTTP_FAIL_RATE > $ERROR_THRESHOLD" | bc -l) )); then
  ERROR_VIOLATED=true
fi

if (( $(echo "$DENIAL_RATE > $DENIAL_THRESHOLD" | bc -l) )); then
  DENIAL_VIOLATED=true
fi

# Determine overall result
RESULT="PASS"
if [ "$LATENCY_VIOLATED" = true ] || [ "$ERROR_VIOLATED" = true ] || [ "$DENIAL_VIOLATED" = true ]; then
  RESULT="FAIL"
fi

# Generate evidence bundle in JSON format
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

cat > "$OUTPUT_FILE" << EOF
{
  "schema_version": "1.0",
  "timestamp": "$TIMESTAMP",
  "drill_id": "ewoa_fire_drill_$(date +%s)",
  "summary": {
    "result": "$RESULT",
    "latency_violated": $LATENCY_VIOLATED,
    "error_violated": $ERROR_VIOLATED,
    "denial_violated": $DENIAL_VIOLATED
  },
  "signals": [
    {
      "signal_id": "exec_latency_p95",
      "value": $P95_LATENCY,
      "unit": "ms",
      "threshold": $LATENCY_THRESHOLD,
      "violated": $LATENCY_VIOLATED
    },
    {
      "signal_id": "http_fail_rate",
      "value": $HTTP_FAIL_RATE,
      "unit": "ratio",
      "threshold": $ERROR_THRESHOLD,
      "violated": $ERROR_VIOLATED
    },
    {
      "signal_id": "denial_rate",
      "value": $DENIAL_RATE,
      "unit": "ratio",
      "threshold": $DENIAL_THRESHOLD,
      "violated": $DENIAL_VIOLATED
    }
  ],
  "alerts": [
$(if [ "$LATENCY_VIOLATED" = true ]; then
  echo "    {"
  echo "      \"alert_id\": \"LATENCY_SLA_VIOLATION\","
  echo "      \"severity\": \"HIGH\","
  echo "      \"condition\": \"p95 < ${LATENCY_THRESHOLD}ms\","
  echo "      \"actual\": $P95_LATENCY,"
  echo "      \"message\": \"P95 latency exceeded threshold\""
  echo "    }"
  [ "$ERROR_VIOLATED" = true ] || [ "$DENIAL_VIOLATED" = true ] && echo "    ,"
fi)
$(if [ "$ERROR_VIOLATED" = true ]; then
  echo "    {"
  echo "      \"alert_id\": \"ERROR_RATE_SLA_VIOLATION\","
  echo "      \"severity\": \"HIGH\","
  echo "      \"condition\": \"error_rate < ${ERROR_THRESHOLD}\","
  echo "      \"actual\": $HTTP_FAIL_RATE,"
  echo "      \"message\": \"HTTP error rate exceeded threshold\""
  echo "    }"
  [ "$DENIAL_VIOLATED" = true ] && echo "    ,"
fi)
$(if [ "$DENIAL_VIOLATED" = true ]; then
  echo "    {"
  echo "      \"alert_id\": \"DENIAL_RATE_SLA_VIOLATION\","
  echo "      \"severity\": \"MEDIUM\","
  echo "      \"condition\": \"denial_rate < ${DENIAL_THRESHOLD}\","
  echo "      \"actual\": $DENIAL_RATE,"
  echo "      \"message\": \"Denial rate exceeded threshold\""
  echo "    }"
fi)
  ]
}
EOF

echo "Evidence bundle generated: $OUTPUT_FILE"
cat "$OUTPUT_FILE"
