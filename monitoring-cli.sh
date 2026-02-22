#!/bin/bash
#
# Worker Monitoring CLI
# Command-line interface for querying monitoring server
#
# Environment Variables:
#   MONITORING_URL - Base URL for monitoring server (default: http://localhost:9090)
#
# Usage:
#   monitoring-cli.sh health                    # System health
#   monitoring-cli.sh workers                   # List all workers
#   monitoring-cli.sh worker <id>               # Worker details
#   monitoring-cli.sh events [limit]            # Recent events
#   monitoring-cli.sh watch                     # Watch health updates (live)
#   monitoring-cli.sh metrics                   # Prometheus metrics

set -euo pipefail

# Configuration
MONITORING_URL="${MONITORING_URL:-http://localhost:9090}"

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if jq is available
if ! command -v jq >/dev/null 2>&1; then
    echo "Error: jq is required but not installed" >&2
    exit 1
fi

# Fetch JSON from monitoring server
fetch_json() {
    local endpoint="$1"
    local url="${MONITORING_URL}${endpoint}"

    if ! curl -sf "$url" 2>/dev/null; then
        echo "Error: Failed to fetch $url" >&2
        echo "Is the monitoring server running? (monitoring-server.js)" >&2
        exit 1
    fi
}

# Display health status
show_health() {
    local health=$(fetch_json "/health")

    local status=$(echo "$health" | jq -r '.status')
    local total=$(echo "$health" | jq -r '.workers.total')
    local healthy=$(echo "$health" | jq -r '.workers.healthy')
    local timeout=$(echo "$health" | jq -r '.workers.timeout')
    local registered=$(echo "$health" | jq -r '.workers.registered')
    local timestamp=$(echo "$health" | jq -r '.timestamp')

    # Color status
    local status_color=$GREEN
    if [[ "$status" == "degraded" ]]; then
        status_color=$YELLOW
    elif [[ "$status" == "critical" ]]; then
        status_color=$RED
    fi

    echo -e "${BLUE}=== System Health ===${NC}"
    echo -e "Status: ${status_color}${status}${NC}"
    echo "Timestamp: $timestamp"
    echo ""
    echo "Workers:"
    echo "  Total: $total"
    echo -e "  Healthy: ${GREEN}${healthy}${NC}"
    if [[ $timeout -gt 0 ]]; then
        echo -e "  Timeout: ${RED}${timeout}${NC}"
    else
        echo "  Timeout: 0"
    fi
    echo "  Registered: $registered"
}

# List all workers
list_workers() {
    local workers=$(fetch_json "/workers")

    echo -e "${BLUE}=== Active Workers ===${NC}"
    echo ""

    local count=$(echo "$workers" | jq 'length')

    if [[ $count -eq 0 ]]; then
        echo "No active workers"
        return
    fi

    # Header
    printf "%-30s %-10s %-8s %-30s %s\n" "WORKER_ID" "STATUS" "AGE" "LAST_HEARTBEAT" "STATUS_MESSAGE"
    echo "--------------------------------------------------------------------------------------------------------"

    # Workers
    echo "$workers" | jq -r '.[] |
        "\(.worker_id)\t\(.status_level)\t\(.age_seconds)\t\(.timestamp)\t\(.status)"
    ' | while IFS=$'\t' read -r worker_id status_level age timestamp status_msg; do
        # Color status
        local status_color=$GREEN
        if [[ "$status_level" == "timeout" ]]; then
            status_color=$RED
        fi

        # Format age
        local age_formatted="${age}s"

        # Truncate status message
        local status_truncated=$(echo "$status_msg" | cut -c1-40)

        printf "%-30s ${status_color}%-10s${NC} %-8s %-30s %s\n" \
            "$worker_id" "$status_level" "$age_formatted" "$timestamp" "$status_truncated"
    done
}

# Show worker details
show_worker() {
    local worker_id="$1"

    local worker=$(fetch_json "/workers/$worker_id")

    echo -e "${BLUE}=== Worker Details ===${NC}"
    echo ""
    echo "$worker" | jq .
}

# Show recent events
show_events() {
    local limit="${1:-100}"

    local events=$(fetch_json "/events?limit=$limit")

    echo -e "${BLUE}=== Recent Events (limit: $limit) ===${NC}"
    echo ""

    local count=$(echo "$events" | jq 'length')

    if [[ $count -eq 0 ]]; then
        echo "No events recorded"
        return
    fi

    # Display events
    echo "$events" | jq -r '.[] |
        "\(.timestamp)\t\(.worker_id)\t\(.event_type)\t\(.message)"
    ' | while IFS=$'\t' read -r timestamp worker_id event_type message; do
        # Color event type
        local type_color=$NC
        case "$event_type" in
            error|failed)
                type_color=$RED
                ;;
            warning)
                type_color=$YELLOW
                ;;
            success|completed)
                type_color=$GREEN
                ;;
        esac

        echo -e "${timestamp} ${BLUE}[${worker_id}]${NC} ${type_color}${event_type}${NC}: ${message}"
    done
}

# Watch health updates (live)
watch_health() {
    echo -e "${BLUE}=== Watching Health Updates ===${NC}"
    echo "Press Ctrl+C to stop"
    echo ""

    # Use SSE stream
    curl -sf -N "${MONITORING_URL}/stream" 2>/dev/null | while read -r line; do
        if [[ "$line" =~ ^data:\ (.+)$ ]]; then
            local data="${BASH_REMATCH[1]}"
            local type=$(echo "$data" | jq -r '.type')

            if [[ "$type" == "health" ]]; then
                # Clear screen and show health
                clear
                echo -e "${BLUE}=== Live Health Monitor ===${NC}"
                echo "Press Ctrl+C to stop"
                echo ""

                local health_data=$(echo "$data" | jq -r '.data')

                local status=$(echo "$health_data" | jq -r '.status')
                local total=$(echo "$health_data" | jq -r '.workers.total')
                local healthy=$(echo "$health_data" | jq -r '.workers.healthy')
                local timeout=$(echo "$health_data" | jq -r '.workers.timeout')
                local timestamp=$(echo "$health_data" | jq -r '.timestamp')

                # Color status
                local status_color=$GREEN
                if [[ "$status" == "degraded" ]]; then
                    status_color=$YELLOW
                elif [[ "$status" == "critical" ]]; then
                    status_color=$RED
                fi

                echo -e "Status: ${status_color}${status}${NC}"
                echo "Timestamp: $timestamp"
                echo ""
                echo "Workers: Total=$total Healthy=${healthy} Timeout=${timeout}"
            elif [[ "$type" == "event" ]]; then
                local event_data=$(echo "$data" | jq -r '.data')
                local event_type=$(echo "$event_data" | jq -r '.event_type')
                local message=$(echo "$event_data" | jq -r '.message')

                echo -e "\n${YELLOW}[Event]${NC} ${event_type}: ${message}"
            fi
        fi
    done
}

# Show Prometheus metrics
show_metrics() {
    local metrics=$(curl -sf "${MONITORING_URL}/metrics" 2>/dev/null)

    if [[ -z "$metrics" ]]; then
        echo "Error: Failed to fetch metrics" >&2
        exit 1
    fi

    echo "$metrics"
}

# Main execution
main() {
    case "${1:-}" in
        health)
            show_health
            ;;
        workers)
            list_workers
            ;;
        worker)
            if [[ -z "${2:-}" ]]; then
                echo "Error: Worker ID required" >&2
                echo "Usage: monitoring-cli.sh worker <worker_id>" >&2
                exit 1
            fi
            show_worker "$2"
            ;;
        events)
            show_events "${2:-100}"
            ;;
        watch)
            watch_health
            ;;
        metrics)
            show_metrics
            ;;
        --help|-h)
            cat <<EOF
Worker Monitoring CLI

Usage:
  monitoring-cli.sh health                    Show system health
  monitoring-cli.sh workers                   List all active workers
  monitoring-cli.sh worker <id>               Show worker details
  monitoring-cli.sh events [limit]            Show recent events (default: 100)
  monitoring-cli.sh watch                     Watch health updates (live)
  monitoring-cli.sh metrics                   Show Prometheus metrics
  monitoring-cli.sh --help                    Show this help

Environment Variables:
  MONITORING_URL                Base URL for monitoring server (default: http://localhost:9090)

Examples:
  # Check system health
  monitoring-cli.sh health

  # List all workers
  monitoring-cli.sh workers

  # Watch live updates
  monitoring-cli.sh watch

  # View recent events
  monitoring-cli.sh events 50

  # Get Prometheus metrics
  monitoring-cli.sh metrics

Note: The monitoring server (monitoring-server.js) must be running.
EOF
            ;;
        *)
            echo "Error: Unknown command: ${1:-}" >&2
            echo "Run 'monitoring-cli.sh --help' for usage" >&2
            exit 1
            ;;
    esac
}

main "$@"
