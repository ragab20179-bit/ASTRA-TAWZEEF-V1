#!/bin/bash
#
# Metrics Capture Script
#
# Purpose: Capture system metrics during EWOA drills
# Usage: ./capture_metrics.sh <scenario_name>
#

set -e

SCENARIO="${1:-unknown}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVIDENCE_DIR="${SCRIPT_DIR}/evidence/${TIMESTAMP}/${SCENARIO}"

echo "=== Capturing Metrics for: $SCENARIO ==="
echo "Timestamp: $TIMESTAMP"
echo "Evidence directory: $EVIDENCE_DIR"

mkdir -p "$EVIDENCE_DIR"

# Capture Docker stats
echo "[1/6] Capturing Docker stats..."
docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}" > "$EVIDENCE_DIR/docker_stats.txt"

# Capture service status
echo "[2/6] Capturing service status..."
docker-compose ps > "$EVIDENCE_DIR/service_status.txt"

# Capture container logs
echo "[3/6] Capturing container logs..."
docker logs astra-core > "$EVIDENCE_DIR/astra_core.log" 2>&1 || echo "ASTRA Core not running" > "$EVIDENCE_DIR/astra_core.log"
docker logs astra-orchestrator > "$EVIDENCE_DIR/astra_orchestrator.log" 2>&1 || echo "Orchestrator not running" > "$EVIDENCE_DIR/astra_orchestrator.log"
docker logs postgres > "$EVIDENCE_DIR/postgres.log" 2>&1 || echo "Postgres not running" > "$EVIDENCE_DIR/postgres.log"

# Capture network stats
echo "[4/6] Capturing network stats..."
docker network inspect astra_taw_prod_v1_default > "$EVIDENCE_DIR/network_info.json" 2>&1 || echo "Network not found" > "$EVIDENCE_DIR/network_info.json"

# Capture system metrics
echo "[5/6] Capturing system metrics..."
cat > "$EVIDENCE_DIR/system_metrics.txt" << EOF
=== System Metrics ===
Timestamp: $(date -Iseconds)
Uptime: $(uptime)
Memory: $(free -h)
Disk: $(df -h /)
CPU: $(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1"%"}')
EOF

# Capture metrics from StatsD (if available)
echo "[6/6] Capturing StatsD metrics..."
if docker ps | grep -q statsd; then
  docker exec statsd cat /tmp/statsd_metrics.txt > "$EVIDENCE_DIR/statsd_metrics.txt" 2>&1 || echo "StatsD metrics not available" > "$EVIDENCE_DIR/statsd_metrics.txt"
else
  echo "StatsD not running" > "$EVIDENCE_DIR/statsd_metrics.txt"
fi

# Create summary JSON
cat > "$EVIDENCE_DIR/metrics_summary.json" << EOF
{
  "scenario": "$SCENARIO",
  "timestamp": "$(date -Iseconds)",
  "evidence_dir": "$EVIDENCE_DIR",
  "services": {
    "astra_core": "$(docker ps -qf "name=astra-core" > /dev/null 2>&1 && echo 'running' || echo 'stopped')",
    "astra_orchestrator": "$(docker ps -qf "name=astra-orchestrator" > /dev/null 2>&1 && echo 'running' || echo 'stopped')",
    "postgres": "$(docker ps -qf "name=postgres" > /dev/null 2>&1 && echo 'running' || echo 'stopped')"
  },
  "files_captured": [
    "docker_stats.txt",
    "service_status.txt",
    "astra_core.log",
    "astra_orchestrator.log",
    "postgres.log",
    "network_info.json",
    "system_metrics.txt",
    "statsd_metrics.txt"
  ]
}
EOF

echo "✅ Metrics captured successfully"
echo "Evidence directory: $EVIDENCE_DIR"
echo ""
