#!/bin/bash
#
# Worker Registry Management
# Registers workers for centralized tracking and discovery
#
# Environment Variables:
#   WORKER_ID - Unique identifier for this worker
#   WATCHDOG_DIR - Directory for watchdog files (default: /tmp/watchdog)
#
# Usage:
#   worker-registry.sh register --task "ferry-booking" --tags "production,ferry"
#   worker-registry.sh unregister
#   worker-registry.sh list
#   worker-registry.sh get <worker_id>
#   worker-registry.sh cleanup  # Remove stale entries

set -euo pipefail

# Configuration
WORKER_ID="${WORKER_ID:-worker-$(hostname)-$$}"
WATCHDOG_DIR="${WATCHDOG_DIR:-/tmp/watchdog}"
REGISTRY_FILE="$WATCHDOG_DIR/registry.json"

# Create watchdog directory
mkdir -p "$WATCHDOG_DIR"

# Initialize registry if it doesn't exist
init_registry() {
    if [[ ! -f "$REGISTRY_FILE" ]]; then
        echo '{"workers":{},"updated_at":null}' > "$REGISTRY_FILE"
    fi
}

# Register worker
register_worker() {
    local task="${1:-unknown}"
    local tags="${2:-}"
    local metadata="${3:-{}}"

    init_registry

    # Validate metadata JSON
    if ! echo "$metadata" | jq empty 2>/dev/null; then
        echo "Error: Invalid JSON in metadata parameter" >&2
        exit 1
    fi

    # Convert comma-separated tags to JSON array
    local tags_json="[]"
    if [[ -n "$tags" ]]; then
        tags_json=$(echo "$tags" | jq -R 'split(",") | map(gsub("^\\s+|\\s+$";""))')
    fi

    # Create worker entry
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local timestamp_unix=$(date +%s)
    local hostname=$(hostname)
    local pid=$$

    local worker_entry=$(jq -n \
        --arg worker_id "$WORKER_ID" \
        --arg task "$task" \
        --argjson tags "$tags_json" \
        --arg registered_at "$timestamp" \
        --argjson registered_at_unix "$timestamp_unix" \
        --arg hostname "$hostname" \
        --argjson pid "$pid" \
        --argjson metadata "$metadata" \
        '{
            worker_id: $worker_id,
            task: $task,
            tags: $tags,
            registered_at: $registered_at,
            registered_at_unix: $registered_at_unix,
            hostname: $hostname,
            pid: $pid,
            metadata: $metadata,
            status: "active"
        }'
    )

    # Update registry
    local updated_registry=$(jq \
        --arg worker_id "$WORKER_ID" \
        --argjson worker "$worker_entry" \
        --arg timestamp "$timestamp" \
        '.workers[$worker_id] = $worker | .updated_at = $timestamp' \
        "$REGISTRY_FILE"
    )

    echo "$updated_registry" > "$REGISTRY_FILE"

    echo "Worker $WORKER_ID registered successfully"
    echo "Task: $task"
    if [[ -n "$tags" ]]; then
        echo "Tags: $tags"
    fi
}

# Unregister worker
unregister_worker() {
    if [[ ! -f "$REGISTRY_FILE" ]]; then
        echo "Registry not found, nothing to unregister"
        return 0
    fi

    # Check if worker exists
    if ! jq -e --arg worker_id "$WORKER_ID" '.workers[$worker_id]' "$REGISTRY_FILE" > /dev/null 2>&1; then
        echo "Worker $WORKER_ID not found in registry"
        return 0
    fi

    # Remove worker from registry
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local updated_registry=$(jq \
        --arg worker_id "$WORKER_ID" \
        --arg timestamp "$timestamp" \
        'del(.workers[$worker_id]) | .updated_at = $timestamp' \
        "$REGISTRY_FILE"
    )

    echo "$updated_registry" > "$REGISTRY_FILE"

    echo "Worker $WORKER_ID unregistered successfully"
}

# List all workers
list_workers() {
    init_registry

    local workers=$(jq -r '.workers | to_entries[] | "\(.key)\t\(.value.task)\t\(.value.status)\t\(.value.registered_at)"' "$REGISTRY_FILE")

    if [[ -z "$workers" ]]; then
        echo "No workers registered"
        return 0
    fi

    echo "WORKER_ID	TASK	STATUS	REGISTERED_AT"
    echo "$workers"
}

# Get worker details
get_worker() {
    local worker_id="${1:-$WORKER_ID}"

    if [[ ! -f "$REGISTRY_FILE" ]]; then
        echo "Registry not found"
        exit 1
    fi

    local worker=$(jq --arg worker_id "$worker_id" '.workers[$worker_id]' "$REGISTRY_FILE")

    if [[ "$worker" == "null" ]]; then
        echo "Worker $worker_id not found"
        exit 1
    fi

    echo "$worker" | jq .
}

# Cleanup stale workers
cleanup_stale() {
    if [[ ! -f "$REGISTRY_FILE" ]]; then
        echo "Registry not found, nothing to clean up"
        return 0
    fi

    local timeout="${1:-300}"  # Default: 5 minutes
    local now=$(date +%s)
    local removed=0

    # Get all worker IDs
    local worker_ids=$(jq -r '.workers | keys[]' "$REGISTRY_FILE")

    for worker_id in $worker_ids; do
        # Check if heartbeat file exists and is recent
        local heartbeat_file="$WATCHDOG_DIR/heartbeat-$worker_id.json"

        if [[ ! -f "$heartbeat_file" ]]; then
            # No heartbeat file, remove from registry
            echo "Removing worker $worker_id (no heartbeat file)"
            local updated_registry=$(jq \
                --arg worker_id "$worker_id" \
                --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
                'del(.workers[$worker_id]) | .updated_at = $timestamp' \
                "$REGISTRY_FILE"
            )
            echo "$updated_registry" > "$REGISTRY_FILE"
            removed=$((removed + 1))
            continue
        fi

        # Check heartbeat age
        local heartbeat_timestamp=$(jq -r '.timestamp_unix // 0' "$heartbeat_file" 2>/dev/null || echo "0")
        local age=$((now - heartbeat_timestamp))

        if [[ $age -gt $timeout ]]; then
            echo "Removing worker $worker_id (heartbeat age: ${age}s > ${timeout}s)"
            local updated_registry=$(jq \
                --arg worker_id "$worker_id" \
                --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
                'del(.workers[$worker_id]) | .updated_at = $timestamp' \
                "$REGISTRY_FILE"
            )
            echo "$updated_registry" > "$REGISTRY_FILE"
            removed=$((removed + 1))
        fi
    done

    echo "Cleanup complete: $removed stale workers removed"
}

# Main execution
main() {
    case "${1:-}" in
        register)
            shift
            # Parse flags
            local task="unknown"
            local tags=""
            local metadata="{}"

            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --task)
                        task="$2"
                        shift 2
                        ;;
                    --tags)
                        tags="$2"
                        shift 2
                        ;;
                    --metadata)
                        metadata="$2"
                        shift 2
                        ;;
                    *)
                        echo "Unknown flag: $1" >&2
                        exit 1
                        ;;
                esac
            done

            register_worker "$task" "$tags" "$metadata"
            ;;
        unregister)
            unregister_worker
            ;;
        list)
            list_workers
            ;;
        get)
            get_worker "${2:-$WORKER_ID}"
            ;;
        cleanup)
            cleanup_stale "${2:-300}"
            ;;
        --help|-h)
            cat <<EOF
Worker Registry Management

Usage:
  worker-registry.sh register [OPTIONS]    Register current worker
  worker-registry.sh unregister            Unregister current worker
  worker-registry.sh list                  List all registered workers
  worker-registry.sh get [WORKER_ID]       Get worker details
  worker-registry.sh cleanup [TIMEOUT]     Remove stale workers (default: 300s)
  worker-registry.sh --help                Show this help

Register Options:
  --task TASK                Task name/description
  --tags TAG1,TAG2           Comma-separated tags
  --metadata JSON            Additional metadata as JSON object

Environment Variables:
  WORKER_ID                  Unique identifier for this worker
  WATCHDOG_DIR               Directory for watchdog files (default: /tmp/watchdog)

Examples:
  # Register worker
  worker-registry.sh register --task "ferry-booking" --tags "production,ferry"

  # Register with metadata
  worker-registry.sh register --task "data-sync" --metadata '{"source":"s3","dest":"db"}'

  # List all workers
  worker-registry.sh list

  # Cleanup stale workers (no heartbeat for 5+ minutes)
  worker-registry.sh cleanup 300

  # Unregister when done
  worker-registry.sh unregister
EOF
            ;;
        *)
            echo "Error: Unknown command: ${1:-}" >&2
            echo "Run 'worker-registry.sh --help' for usage" >&2
            exit 1
            ;;
    esac
}

main "$@"
