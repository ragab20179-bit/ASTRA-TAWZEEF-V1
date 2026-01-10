#!/bin/bash
#
# Evidence Bundle Packaging Script
#
# Purpose: Package all EWOA drill evidence into a single archive
# Usage: ./package_evidence.sh
#

set -e

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVIDENCE_BASE_DIR="${SCRIPT_DIR}/evidence"
BUNDLE_NAME="ewoa_evidence_${TIMESTAMP}.tar.gz"

echo "=== Packaging EWOA Evidence Bundle ==="
echo "Timestamp: $TIMESTAMP"
echo "Bundle name: $BUNDLE_NAME"

# Check if evidence directory exists
if [ ! -d "$EVIDENCE_BASE_DIR" ]; then
  echo "❌ ERROR: Evidence directory not found: $EVIDENCE_BASE_DIR"
  exit 1
fi

# Count drill directories
DRILL_COUNT=$(find "$EVIDENCE_BASE_DIR" -maxdepth 2 -type d -name "drill*" | wc -l)
echo "Found $DRILL_COUNT drill evidence directories"

# Create summary report
SUMMARY_FILE="${EVIDENCE_BASE_DIR}/summary.json"
echo "Creating summary report: $SUMMARY_FILE"

# Initialize summary
cat > "$SUMMARY_FILE" << EOF
{
  "timestamp": "$(date -Iseconds)",
  "bundle_name": "$BUNDLE_NAME",
  "drills_executed": $DRILL_COUNT,
  "drills": []
}
EOF

# Collect drill results
DRILLS_JSON="[]"
PASSED_COUNT=0
FAILED_COUNT=0

for DRILL_DIR in $(find "$EVIDENCE_BASE_DIR" -maxdepth 2 -type d -name "drill*" | sort); do
  DRILL_NAME=$(basename "$DRILL_DIR")
  ALERT_FILE="$DRILL_DIR/alert.json"
  
  if [ -f "$ALERT_FILE" ]; then
    # Extract alert status
    ALERT_STATUS=$(jq -r '.status' "$ALERT_FILE" 2>/dev/null || echo "UNKNOWN")
    DRILL_ID=$(jq -r '.drill_id' "$ALERT_FILE" 2>/dev/null || echo "$DRILL_NAME")
    
    if [ "$ALERT_STATUS" == "FIRED" ]; then
      PASSED_COUNT=$((PASSED_COUNT + 1))
      STATUS="PASS"
    else
      FAILED_COUNT=$((FAILED_COUNT + 1))
      STATUS="FAIL"
    fi
    
    # Add to drills array
    DRILL_JSON=$(cat "$ALERT_FILE")
    DRILL_JSON=$(echo "$DRILL_JSON" | jq ". + {\"status\": \"$STATUS\"}")
    DRILLS_JSON=$(echo "$DRILLS_JSON" | jq ". + [$DRILL_JSON]")
  else
    echo "⚠️  WARNING: No alert.json found for $DRILL_NAME"
    FAILED_COUNT=$((FAILED_COUNT + 1))
  fi
done

# Update summary with drill results
jq ".drills = $DRILLS_JSON | .drills_passed = $PASSED_COUNT | .drills_failed = $FAILED_COUNT | .evidence_complete = true" "$SUMMARY_FILE" > "${SUMMARY_FILE}.tmp"
mv "${SUMMARY_FILE}.tmp" "$SUMMARY_FILE"

# Create archive
echo "Creating archive: $BUNDLE_NAME"
cd "$EVIDENCE_BASE_DIR/.."
tar -czf "$BUNDLE_NAME" -C "$EVIDENCE_BASE_DIR/.." "$(basename "$EVIDENCE_BASE_DIR")"

BUNDLE_PATH="${EVIDENCE_BASE_DIR}/../${BUNDLE_NAME}"
BUNDLE_SIZE=$(du -h "$BUNDLE_PATH" | cut -f1)

echo ""
echo "=== Evidence Bundle Complete ==="
echo "Bundle: $BUNDLE_PATH"
echo "Size: $BUNDLE_SIZE"
echo "Drills Executed: $DRILL_COUNT"
echo "Drills Passed: $PASSED_COUNT"
echo "Drills Failed: $FAILED_COUNT"
echo "================================"

# Print summary
echo ""
echo "=== Summary Report ==="
jq '.' "$SUMMARY_FILE"
echo "======================"

# Exit with failure if any drills failed
if [ $FAILED_COUNT -gt 0 ]; then
  echo ""
  echo "❌ FAIL: $FAILED_COUNT drill(s) failed"
  exit 1
fi

echo ""
echo "✅ PASS: All drills passed successfully"
exit 0
