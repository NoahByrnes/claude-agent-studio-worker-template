#!/bin/bash
#
# Worker Heartbeat Signal
# Workers call this periodically to signal they're alive and working
#
# Environment Variables:
#   WORKER_ID - Unique identifier for this worker
#   WATCHDOG_DIR - Directory for watchdog files (default: /tmp/watchdog)
#   HEARTBEAT_INTERVAL - Seconds between heartbeats (default: 30)
#
# Usage:
#   heartbeat.sh [status_message]
#   heartbeat.sh "Processing job 123"
#   heartbeat.sh "Waiting for ferry availability"

set -euo pipefail

# Configuration
WORKER_ID="${WORKER_ID:-worker-$(hostname)-$$}"
WATCHDOG_DIR="${WATCHDOG_DIR:-/tmp/watchdog}"
HEARTBEAT_FILE="$WATCHDOG_DIR/heartbeat-$WORKER_ID.json"
STATUS_MESSAGE="${1:-Working}"

# Create watchdog directory
mkdir -p "$WATCHDOG_DIR"

# Get system metrics
get_memory_usage() {
    # Memory in MB
    ps -o rss= -p $$ 2>/dev/null | awk '{print int($1/1024)}' || echo "0"
}

get_cpu_time() {
    # CPU time in seconds
    ps -o cputime= -p $$ 2>/dev/null | awk -F: '{print ($1*3600)+($2*60)+$3}' || echo "0"
}

get_uptime() {
    # Process uptime in seconds
    ps -o etimes= -p $$ 2>/dev/null | tr -d ' ' || echo "0"
}

# Generate heartbeat JSON
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
MEMORY_MB=$(get_memory_usage)
CPU_TIME=$(get_cpu_time)
UPTIME=$(get_uptime)

cat > "$HEARTBEAT_FILE" <<EOF
{
  "worker_id": "$WORKER_ID",
  "timestamp": "$TIMESTAMP",
  "timestamp_unix": $(date +%s),
  "status": "$STATUS_MESSAGE",
  "metrics": {
    "memory_mb": $MEMORY_MB,
    "cpu_time_seconds": $CPU_TIME,
    "uptime_seconds": $UPTIME,
    "pid": $$
  },
  "healthy": true
}
EOF

# Optional: Log heartbeat (only if verbose mode)
if [[ "${HEARTBEAT_VERBOSE:-false}" == "true" ]]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Heartbeat sent: $STATUS_MESSAGE (mem: ${MEMORY_MB}MB, uptime: ${UPTIME}s)"
fi

exit 0
