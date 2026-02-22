#!/bin/bash
#
# Worker Event Logger
# Records structured events to centralized event log
#
# Environment Variables:
#   WORKER_ID - Unique identifier for this worker
#   WATCHDOG_DIR - Directory for watchdog files (default: /tmp/watchdog)
#
# Usage:
#   worker-event.sh <event_type> <message> [extra_json]
#   worker-event.sh "task_started" "Processing ferry booking" '{"booking_id": "123"}'
#   worker-event.sh "error" "API timeout" '{"endpoint": "/availability", "status": 504}'
#   worker-event.sh "task_completed" "Booking successful" '{"confirmation": "BC12345"}'

set -euo pipefail

# Configuration
WORKER_ID="${WORKER_ID:-worker-$(hostname)-$$}"
WATCHDOG_DIR="${WATCHDOG_DIR:-/tmp/watchdog}"
EVENTS_FILE="$WATCHDOG_DIR/events.jsonl"

# Arguments
EVENT_TYPE="${1:-info}"
MESSAGE="${2:-No message}"
EXTRA_JSON="${3:-{}}"

# Create watchdog directory
mkdir -p "$WATCHDOG_DIR"

# Validate extra JSON
if ! echo "$EXTRA_JSON" | jq empty 2>/dev/null; then
    echo "Warning: Invalid JSON in extra_json parameter, using empty object" >&2
    EXTRA_JSON="{}"
fi

# Generate event JSON
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
TIMESTAMP_UNIX=$(date +%s)

# Merge extra JSON with base event
EVENT_JSON=$(jq -n \
    --arg worker_id "$WORKER_ID" \
    --arg timestamp "$TIMESTAMP" \
    --argjson timestamp_unix "$TIMESTAMP_UNIX" \
    --arg event_type "$EVENT_TYPE" \
    --arg message "$MESSAGE" \
    --argjson extra "$EXTRA_JSON" \
    '{
        worker_id: $worker_id,
        timestamp: $timestamp,
        timestamp_unix: $timestamp_unix,
        event_type: $event_type,
        message: $message
    } + $extra'
)

# Append to events log (JSONL format - one JSON object per line)
echo "$EVENT_JSON" >> "$EVENTS_FILE"

# Optional: Log to stdout if verbose
if [[ "${WORKER_EVENT_VERBOSE:-false}" == "true" ]]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] EVENT [$EVENT_TYPE] $MESSAGE"
fi

exit 0
