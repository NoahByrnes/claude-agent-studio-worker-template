#!/bin/bash
#
# Worker Watchdog Daemon
# Monitors worker heartbeats and triggers alerts on timeout
#
# Environment Variables:
#   WATCHDOG_DIR - Directory for watchdog files (default: /tmp/watchdog)
#   WATCHDOG_TIMEOUT - Seconds before worker is considered dead (default: 90)
#   WATCHDOG_CHECK_INTERVAL - Seconds between checks (default: 10)
#   WATCHDOG_ALERT_METHOD - "sms", "email", "both", or "none" (default: email)
#   STATUS_UPDATE_RECIPIENTS - Alert recipients (comma-separated)
#   WATCHDOG_AUTO_RESTART - Set to "true" to auto-restart dead workers (default: false)
#
# Usage:
#   watchdog.sh                    # Start watchdog daemon
#   watchdog.sh --once             # Single check (no daemon)
#   watchdog.sh --status           # Show status of all workers
#   watchdog.sh --cleanup          # Remove old heartbeat files

set -euo pipefail

# Configuration
WATCHDOG_DIR="${WATCHDOG_DIR:-/tmp/watchdog}"
WATCHDOG_TIMEOUT="${WATCHDOG_TIMEOUT:-90}"
CHECK_INTERVAL="${WATCHDOG_CHECK_INTERVAL:-10}"
ALERT_METHOD="${WATCHDOG_ALERT_METHOD:-email}"
LOG_FILE="/var/log/watchdog/watchdog.log"
PID_FILE="/tmp/watchdog.pid"

# Create directories
mkdir -p "$WATCHDOG_DIR" "$(dirname "$LOG_FILE")"

# Logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] $1" | tee -a "$LOG_FILE"
}

# Check if another watchdog is running
check_running() {
    if [[ -f "$PID_FILE" ]]; then
        local existing_pid=$(cat "$PID_FILE")
        if ps -p "$existing_pid" > /dev/null 2>&1; then
            log "Watchdog already running (PID: $existing_pid)"
            exit 1
        else
            log "Removing stale PID file"
            rm -f "$PID_FILE"
        fi
    fi
}

# Check worker heartbeat
check_heartbeat() {
    local heartbeat_file="$1"
    local worker_id=$(basename "$heartbeat_file" .json | sed 's/heartbeat-//')

    if [[ ! -f "$heartbeat_file" ]]; then
        return 0
    fi

    # Parse heartbeat JSON
    local timestamp_unix=$(jq -r '.timestamp_unix // 0' "$heartbeat_file" 2>/dev/null || echo "0")
    local status=$(jq -r '.status // "Unknown"' "$heartbeat_file" 2>/dev/null || echo "Unknown")
    local worker_id_json=$(jq -r '.worker_id // "unknown"' "$heartbeat_file" 2>/dev/null || echo "unknown")

    # Calculate age
    local now=$(date +%s)
    local age=$((now - timestamp_unix))

    # Check timeout
    if [[ $age -gt $WATCHDOG_TIMEOUT ]]; then
        log "⚠️  TIMEOUT: Worker $worker_id_json missed heartbeat (age: ${age}s, limit: ${WATCHDOG_TIMEOUT}s)"
        log "   Last status: $status"

        # Trigger alert
        send_alert "$worker_id_json" "$age" "$status" "$heartbeat_file"

        # Auto-restart if enabled
        if [[ "${WATCHDOG_AUTO_RESTART:-false}" == "true" ]]; then
            restart_worker "$worker_id_json" "$heartbeat_file"
        fi

        return 1
    else
        # Healthy
        if [[ "${WATCHDOG_VERBOSE:-false}" == "true" ]]; then
            log "✓ Worker $worker_id_json healthy (age: ${age}s, status: $status)"
        fi
        return 0
    fi
}

# Send alert
send_alert() {
    local worker_id="$1"
    local age="$2"
    local status="$3"
    local heartbeat_file="$4"

    # Check if recipients configured
    if [[ -z "${STATUS_UPDATE_RECIPIENTS:-}" ]]; then
        log "No alert recipients configured (STATUS_UPDATE_RECIPIENTS not set)"
        return 0
    fi

    # Parse metrics
    local memory=$(jq -r '.metrics.memory_mb // 0' "$heartbeat_file" 2>/dev/null || echo "0")
    local uptime=$(jq -r '.metrics.uptime_seconds // 0' "$heartbeat_file" 2>/dev/null || echo "0")
    local timestamp=$(jq -r '.timestamp // "Unknown"' "$heartbeat_file" 2>/dev/null || echo "Unknown")

    # Format uptime
    local uptime_formatted=$(printf "%dd %dh %dm" $((uptime/86400)) $((uptime%86400/3600)) $((uptime%3600/60)))

    # Create alert message
    local alert_message
    alert_message=$(cat <<EOF
🚨 WATCHDOG ALERT: Worker Timeout

Worker ID: $worker_id
Last Heartbeat: $timestamp
Age: ${age}s (timeout: ${WATCHDOG_TIMEOUT}s)
Status: $status

Metrics:
  Memory: ${memory}MB
  Uptime: $uptime_formatted

The worker has missed its heartbeat deadline.
This may indicate the worker is stuck, crashed, or overloaded.

Action required: Check worker logs and consider manual intervention.
EOF
)

    log "Sending alert for worker $worker_id"

    # Send via configured method
    if [[ "$ALERT_METHOD" == "sms" ]] || [[ "$ALERT_METHOD" == "both" ]]; then
        if command -v watchdog-alert.sh >/dev/null 2>&1; then
            watchdog-alert.sh --method sms --message "$alert_message" || log "Failed to send SMS alert"
        fi
    fi

    if [[ "$ALERT_METHOD" == "email" ]] || [[ "$ALERT_METHOD" == "both" ]]; then
        if command -v watchdog-alert.sh >/dev/null 2>&1; then
            watchdog-alert.sh --method email --message "$alert_message" || log "Failed to send email alert"
        fi
    fi
}

# Restart worker
restart_worker() {
    local worker_id="$1"
    local heartbeat_file="$2"

    log "Auto-restart enabled for worker $worker_id"

    # Extract PID from heartbeat
    local pid=$(jq -r '.metrics.pid // 0' "$heartbeat_file" 2>/dev/null || echo "0")

    if [[ $pid -gt 0 ]] && ps -p $pid > /dev/null 2>&1; then
        log "Killing stuck worker process (PID: $pid)"
        kill -TERM $pid 2>/dev/null || kill -KILL $pid 2>/dev/null || log "Failed to kill process"
    fi

    # Remove stale heartbeat
    rm -f "$heartbeat_file"

    log "Worker $worker_id terminated. Parent process should respawn if configured."
}

# Status report
show_status() {
    echo "Watchdog Status Report"
    echo "======================"
    echo ""
    echo "Configuration:"
    echo "  Timeout: ${WATCHDOG_TIMEOUT}s"
    echo "  Check Interval: ${CHECK_INTERVAL}s"
    echo "  Alert Method: $ALERT_METHOD"
    echo ""
    echo "Workers:"

    local worker_count=0
    local healthy_count=0
    local timeout_count=0

    for heartbeat_file in "$WATCHDOG_DIR"/heartbeat-*.json; do
        if [[ ! -f "$heartbeat_file" ]]; then
            continue
        fi

        worker_count=$((worker_count + 1))

        local worker_id=$(jq -r '.worker_id // "unknown"' "$heartbeat_file" 2>/dev/null || echo "unknown")
        local timestamp=$(jq -r '.timestamp // "Unknown"' "$heartbeat_file" 2>/dev/null || echo "Unknown")
        local timestamp_unix=$(jq -r '.timestamp_unix // 0' "$heartbeat_file" 2>/dev/null || echo "0")
        local status=$(jq -r '.status // "Unknown"' "$heartbeat_file" 2>/dev/null || echo "Unknown")
        local memory=$(jq -r '.metrics.memory_mb // 0' "$heartbeat_file" 2>/dev/null || echo "0")

        local now=$(date +%s)
        local age=$((now - timestamp_unix))

        if [[ $age -gt $WATCHDOG_TIMEOUT ]]; then
            echo "  ⚠️  $worker_id - TIMEOUT (${age}s ago)"
            timeout_count=$((timeout_count + 1))
        else
            echo "  ✓ $worker_id - Healthy (${age}s ago)"
            healthy_count=$((healthy_count + 1))
        fi

        echo "      Status: $status"
        echo "      Memory: ${memory}MB"
        echo "      Last: $timestamp"
        echo ""
    done

    if [[ $worker_count -eq 0 ]]; then
        echo "  No workers reporting heartbeats"
    else
        echo "Summary: $healthy_count healthy, $timeout_count timeout, $worker_count total"
    fi
}

# Cleanup old heartbeats
cleanup() {
    log "Cleaning up old heartbeat files (older than ${WATCHDOG_TIMEOUT}s)"

    local now=$(date +%s)
    local removed=0

    for heartbeat_file in "$WATCHDOG_DIR"/heartbeat-*.json; do
        if [[ ! -f "$heartbeat_file" ]]; then
            continue
        fi

        local timestamp_unix=$(jq -r '.timestamp_unix // 0' "$heartbeat_file" 2>/dev/null || echo "0")
        local age=$((now - timestamp_unix))

        # Remove if older than 2x timeout
        if [[ $age -gt $((WATCHDOG_TIMEOUT * 2)) ]]; then
            log "Removing stale heartbeat: $(basename "$heartbeat_file") (age: ${age}s)"
            rm -f "$heartbeat_file"
            removed=$((removed + 1))
        fi
    done

    log "Cleanup complete: $removed files removed"
}

# Main daemon loop
run_daemon() {
    log "Starting watchdog daemon (PID: $$)"
    log "Configuration: timeout=${WATCHDOG_TIMEOUT}s, interval=${CHECK_INTERVAL}s, method=$ALERT_METHOD"

    # Write PID file
    echo $$ > "$PID_FILE"

    # Cleanup on exit
    trap "rm -f '$PID_FILE'; log 'Watchdog daemon stopped'" EXIT INT TERM

    while true; do
        # Check all heartbeat files
        for heartbeat_file in "$WATCHDOG_DIR"/heartbeat-*.json; do
            if [[ -f "$heartbeat_file" ]]; then
                check_heartbeat "$heartbeat_file" || true
            fi
        done

        # Sleep
        sleep "$CHECK_INTERVAL"
    done
}

# Main execution
main() {
    case "${1:-}" in
        --once)
            log "Running single check"
            for heartbeat_file in "$WATCHDOG_DIR"/heartbeat-*.json; do
                if [[ -f "$heartbeat_file" ]]; then
                    check_heartbeat "$heartbeat_file" || true
                fi
            done
            ;;
        --status)
            show_status
            ;;
        --cleanup)
            cleanup
            ;;
        --help|-h)
            cat <<EOF
Worker Watchdog Daemon

Usage:
  watchdog.sh              Start watchdog daemon (monitors continuously)
  watchdog.sh --once       Run single check (no daemon)
  watchdog.sh --status     Show status of all workers
  watchdog.sh --cleanup    Remove old heartbeat files
  watchdog.sh --help       Show this help

Environment Variables:
  WATCHDOG_TIMEOUT            Timeout in seconds (default: 90)
  WATCHDOG_CHECK_INTERVAL     Check interval in seconds (default: 10)
  WATCHDOG_ALERT_METHOD       Alert method: sms|email|both|none (default: email)
  STATUS_UPDATE_RECIPIENTS    Alert recipients (comma-separated)
  WATCHDOG_AUTO_RESTART       Auto-restart dead workers (default: false)
  WATCHDOG_VERBOSE            Verbose logging (default: false)

Examples:
  # Start watchdog with 2-minute timeout
  WATCHDOG_TIMEOUT=120 watchdog.sh

  # Check status
  watchdog.sh --status

  # Run single check (for cron)
  watchdog.sh --once
EOF
            ;;
        *)
            check_running
            run_daemon
            ;;
    esac
}

main "$@"
