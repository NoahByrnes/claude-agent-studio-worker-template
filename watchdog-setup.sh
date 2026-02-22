#!/bin/bash
#
# Watchdog System Setup
# Install and configure the watchdog system
#
# Usage:
#   watchdog-setup.sh install          # Install watchdog system
#   watchdog-setup.sh start            # Start watchdog daemon
#   watchdog-setup.sh stop             # Stop watchdog daemon
#   watchdog-setup.sh status           # Show status
#   watchdog-setup.sh enable-cron      # Enable periodic checks via cron
#   watchdog-setup.sh disable-cron     # Disable cron checks

set -euo pipefail

LOG_FILE="/var/log/watchdog/setup.log"
PID_FILE="/tmp/watchdog.pid"

mkdir -p "$(dirname "$LOG_FILE")"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Install watchdog system
install() {
    log "Installing watchdog system"

    # Ensure scripts are executable
    chmod +x /usr/local/bin/watchdog.sh 2>/dev/null || chmod +x ./watchdog.sh
    chmod +x /usr/local/bin/watchdog-alert.sh 2>/dev/null || chmod +x ./watchdog-alert.sh
    chmod +x /usr/local/bin/heartbeat.sh 2>/dev/null || chmod +x ./heartbeat.sh

    # Create directories
    mkdir -p /tmp/watchdog
    mkdir -p /var/log/watchdog

    log "✓ Watchdog system installed"
    log ""
    log "Configuration:"
    log "  WATCHDOG_TIMEOUT=${WATCHDOG_TIMEOUT:-90} (seconds before alert)"
    log "  WATCHDOG_CHECK_INTERVAL=${WATCHDOG_CHECK_INTERVAL:-10} (seconds between checks)"
    log "  WATCHDOG_ALERT_METHOD=${WATCHDOG_ALERT_METHOD:-email} (sms|email|both|none)"
    log "  WATCHDOG_AUTO_RESTART=${WATCHDOG_AUTO_RESTART:-false} (auto-restart dead workers)"
    log ""
    log "To start: watchdog-setup.sh start"
    log "To enable cron: watchdog-setup.sh enable-cron"
}

# Start watchdog daemon
start_daemon() {
    if [[ -f "$PID_FILE" ]]; then
        local pid=$(cat "$PID_FILE")
        if ps -p "$pid" > /dev/null 2>&1; then
            log "Watchdog already running (PID: $pid)"
            return 0
        else
            log "Removing stale PID file"
            rm -f "$PID_FILE"
        fi
    fi

    log "Starting watchdog daemon"

    # Start in background
    if command -v watchdog.sh >/dev/null 2>&1; then
        nohup watchdog.sh >> "$LOG_FILE" 2>&1 &
    else
        nohup ./watchdog.sh >> "$LOG_FILE" 2>&1 &
    fi

    local pid=$!
    echo $pid > "$PID_FILE"

    sleep 1

    if ps -p "$pid" > /dev/null 2>&1; then
        log "✓ Watchdog started (PID: $pid)"
    else
        log "✗ Failed to start watchdog"
        rm -f "$PID_FILE"
        return 1
    fi
}

# Stop watchdog daemon
stop_daemon() {
    if [[ ! -f "$PID_FILE" ]]; then
        log "Watchdog not running (no PID file)"
        return 0
    fi

    local pid=$(cat "$PID_FILE")

    if ! ps -p "$pid" > /dev/null 2>&1; then
        log "Watchdog not running (stale PID file)"
        rm -f "$PID_FILE"
        return 0
    fi

    log "Stopping watchdog (PID: $pid)"
    kill -TERM "$pid" 2>/dev/null || kill -KILL "$pid" 2>/dev/null

    sleep 1

    if ps -p "$pid" > /dev/null 2>&1; then
        log "✗ Failed to stop watchdog"
        return 1
    else
        log "✓ Watchdog stopped"
        rm -f "$PID_FILE"
    fi
}

# Show status
show_status() {
    if [[ -f "$PID_FILE" ]]; then
        local pid=$(cat "$PID_FILE")
        if ps -p "$pid" > /dev/null 2>&1; then
            echo "Watchdog: Running (PID: $pid)"
        else
            echo "Watchdog: Not running (stale PID file)"
        fi
    else
        echo "Watchdog: Not running"
    fi

    echo ""

    # Show worker status
    if command -v watchdog.sh >/dev/null 2>&1; then
        watchdog.sh --status
    else
        ./watchdog.sh --status
    fi
}

# Enable cron checks
enable_cron() {
    log "Enabling watchdog cron checks"

    local cron_schedule="${WATCHDOG_CRON_SCHEDULE:-*/5 * * * *}"  # Every 5 minutes
    local cron_entry="$cron_schedule /usr/local/bin/watchdog.sh --once >> /var/log/watchdog/cron.log 2>&1"

    # Add to crontab
    (crontab -l 2>/dev/null | grep -v "watchdog.sh --once" || true; echo "$cron_entry") | crontab -

    log "✓ Cron check enabled: $cron_schedule"
    log "Note: This supplements the daemon, not replaces it"
    log "For continuous monitoring, use: watchdog-setup.sh start"
}

# Disable cron checks
disable_cron() {
    log "Disabling watchdog cron checks"

    crontab -l 2>/dev/null | grep -v "watchdog.sh --once" | crontab - || true

    log "✓ Cron checks disabled"
}

# Main
main() {
    case "${1:-}" in
        install)
            install
            ;;
        start)
            start_daemon
            ;;
        stop)
            stop_daemon
            ;;
        restart)
            stop_daemon
            sleep 1
            start_daemon
            ;;
        status)
            show_status
            ;;
        enable-cron)
            enable_cron
            ;;
        disable-cron)
            disable_cron
            ;;
        --help|-h)
            cat <<EOF
Watchdog System Setup

Usage:
  watchdog-setup.sh install         Install watchdog system
  watchdog-setup.sh start           Start watchdog daemon (continuous monitoring)
  watchdog-setup.sh stop            Stop watchdog daemon
  watchdog-setup.sh restart         Restart watchdog daemon
  watchdog-setup.sh status          Show status of watchdog and workers
  watchdog-setup.sh enable-cron     Enable periodic checks via cron (every 5 min)
  watchdog-setup.sh disable-cron    Disable cron checks
  watchdog-setup.sh --help          Show this help

Environment Variables:
  WATCHDOG_TIMEOUT            Timeout in seconds (default: 90)
  WATCHDOG_CHECK_INTERVAL     Check interval in seconds (default: 10)
  WATCHDOG_ALERT_METHOD       Alert method: sms|email|both|none (default: email)
  WATCHDOG_AUTO_RESTART       Auto-restart dead workers (default: false)
  WATCHDOG_CRON_SCHEDULE      Cron schedule for periodic checks (default: */5 * * * *)
  STATUS_UPDATE_RECIPIENTS    Alert recipients (required for alerts)

Alert Configuration (required for notifications):
  # For Email (via SendGrid)
  export SENDGRID_API_KEY="your_api_key"
  export STATUS_UPDATE_FROM_EMAIL="watchdog@example.com"

  # For SMS (via Twilio)
  export TWILIO_ACCOUNT_SID="your_sid"
  export TWILIO_AUTH_TOKEN="your_token"
  export TWILIO_PHONE_NUMBER="+1234567890"

  # Recipients
  export STATUS_UPDATE_RECIPIENTS="user@example.com,+1234567890"

Examples:
  # Install and start with default settings
  watchdog-setup.sh install
  watchdog-setup.sh start

  # Start with custom timeout and auto-restart
  WATCHDOG_TIMEOUT=120 WATCHDOG_AUTO_RESTART=true watchdog-setup.sh start

  # Check status
  watchdog-setup.sh status

  # Enable cron for backup monitoring
  watchdog-setup.sh enable-cron
EOF
            ;;
        *)
            log "ERROR: Unknown command: ${1:-}"
            log "Run 'watchdog-setup.sh --help' for usage"
            exit 1
            ;;
    esac
}

main "$@"
