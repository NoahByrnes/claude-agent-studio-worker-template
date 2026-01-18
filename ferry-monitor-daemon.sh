#!/bin/bash
# Ferry Monitor Daemon Manager
# Manages background ferry monitoring processes

DAEMON_DIR="/tmp/ferry-monitor"
PIDFILE="${DAEMON_DIR}/monitor.pid"
LOGFILE="${DAEMON_DIR}/monitor.log"
CONFIGFILE="${DAEMON_DIR}/config.json"

# Ensure daemon directory exists
mkdir -p "${DAEMON_DIR}"

function start_monitor() {
    if [ -f "${PIDFILE}" ]; then
        PID=$(cat "${PIDFILE}")
        if kill -0 "${PID}" 2>/dev/null; then
            echo "Ferry monitor is already running (PID: ${PID})"
            return 1
        else
            # Stale pidfile, remove it
            rm -f "${PIDFILE}"
        fi
    fi

    # Check if config exists
    if [ ! -f "${CONFIGFILE}" ]; then
        echo "No monitor configuration found at ${CONFIGFILE}"
        echo "Use 'ferry-monitor-daemon config' to set up monitoring"
        return 1
    fi

    # Start monitor in background
    echo "Starting ferry monitor..."
    nohup bash -c "
        while true; do
            # Read config and run monitor
            DEPARTURE=\$(jq -r '.departure' '${CONFIGFILE}')
            ARRIVAL=\$(jq -r '.arrival' '${CONFIGFILE}')
            DATE=\$(jq -r '.date' '${CONFIGFILE}')
            TIME=\$(jq -r '.time' '${CONFIGFILE}')
            ADULTS=\$(jq -r '.adults // 1' '${CONFIGFILE}')
            CHILDREN=\$(jq -r '.children // 0' '${CONFIGFILE}')
            VEHICLE=\$(jq -r '.vehicle // true' '${CONFIGFILE}')
            POLL_INTERVAL=\$(jq -r '.pollInterval // 60' '${CONFIGFILE}')
            TIMEOUT=\$(jq -r '.timeout // 3600' '${CONFIGFILE}')

            VEHICLE_FLAG=\"--vehicle\"
            if [ \"\${VEHICLE}\" = \"false\" ]; then
                VEHICLE_FLAG=\"--no-vehicle\"
            fi

            echo \"[\$(date)] Starting monitor: \${DEPARTURE} -> \${ARRIVAL} on \${DATE} at \${TIME}\" >> '${LOGFILE}'

            /usr/local/bin/wait-for-ferry \\
                --from \"\${DEPARTURE}\" \\
                --to \"\${ARRIVAL}\" \\
                --date \"\${DATE}\" \\
                --time \"\${TIME}\" \\
                --adults \"\${ADULTS}\" \\
                --children \"\${CHILDREN}\" \\
                \${VEHICLE_FLAG} \\
                --poll-interval \"\${POLL_INTERVAL}\" \\
                --timeout \"\${TIMEOUT}\" \\
                --json >> '${LOGFILE}' 2>&1

            EXIT_CODE=\$?
            echo \"[\$(date)] Monitor exited with code \${EXIT_CODE}\" >> '${LOGFILE}'

            if [ \${EXIT_CODE} -eq 0 ]; then
                echo \"[\$(date)] Ferry became AVAILABLE! Check logs for details.\" >> '${LOGFILE}'
                # Optionally trigger notification or booking here
            fi

            # Wait before restarting (if continuous monitoring enabled)
            CONTINUOUS=\$(jq -r '.continuous // false' '${CONFIGFILE}')
            if [ \"\${CONTINUOUS}\" = \"true\" ]; then
                sleep 300  # Wait 5 minutes before checking again
            else
                break  # Exit after one check
            fi
        done
    " >> "${LOGFILE}" 2>&1 &

    PID=$!
    echo "${PID}" > "${PIDFILE}"
    echo "Ferry monitor started (PID: ${PID})"
    echo "Logs: ${LOGFILE}"
}

function stop_monitor() {
    if [ ! -f "${PIDFILE}" ]; then
        echo "Ferry monitor is not running (no pidfile)"
        return 1
    fi

    PID=$(cat "${PIDFILE}")
    if ! kill -0 "${PID}" 2>/dev/null; then
        echo "Ferry monitor is not running (stale pidfile)"
        rm -f "${PIDFILE}"
        return 1
    fi

    echo "Stopping ferry monitor (PID: ${PID})..."
    kill "${PID}"
    rm -f "${PIDFILE}"
    echo "Ferry monitor stopped"
}

function status_monitor() {
    if [ ! -f "${PIDFILE}" ]; then
        echo "Status: NOT RUNNING"
        return 1
    fi

    PID=$(cat "${PIDFILE}")
    if kill -0 "${PID}" 2>/dev/null; then
        echo "Status: RUNNING (PID: ${PID})"
        if [ -f "${CONFIGFILE}" ]; then
            echo ""
            echo "Configuration:"
            jq '.' "${CONFIGFILE}"
        fi
        return 0
    else
        echo "Status: NOT RUNNING (stale pidfile)"
        rm -f "${PIDFILE}"
        return 1
    fi
}

function show_logs() {
    if [ ! -f "${LOGFILE}" ]; then
        echo "No logs found"
        return 1
    fi

    LINES="${1:-50}"
    echo "Last ${LINES} lines of ferry monitor log:"
    echo "----------------------------------------"
    tail -n "${LINES}" "${LOGFILE}"
}

function configure_monitor() {
    echo "Ferry Monitor Configuration"
    echo "=========================="
    echo ""

    read -p "Departure terminal: " DEPARTURE
    read -p "Arrival terminal: " ARRIVAL
    read -p "Date (MM/DD/YYYY): " DATE
    read -p "Time (e.g., 1:20 pm): " TIME
    read -p "Number of adults [1]: " ADULTS
    ADULTS=${ADULTS:-1}
    read -p "Number of children [0]: " CHILDREN
    CHILDREN=${CHILDREN:-0}
    read -p "With vehicle? (y/n) [y]: " VEHICLE_INPUT
    VEHICLE_INPUT=${VEHICLE_INPUT:-y}
    VEHICLE="true"
    if [[ "${VEHICLE_INPUT}" =~ ^[Nn] ]]; then
        VEHICLE="false"
    fi
    read -p "Poll interval (seconds) [60]: " POLL_INTERVAL
    POLL_INTERVAL=${POLL_INTERVAL:-60}
    read -p "Timeout (seconds) [3600]: " TIMEOUT
    TIMEOUT=${TIMEOUT:-3600}
    read -p "Continuous monitoring? (y/n) [n]: " CONTINUOUS_INPUT
    CONTINUOUS_INPUT=${CONTINUOUS_INPUT:-n}
    CONTINUOUS="false"
    if [[ "${CONTINUOUS_INPUT}" =~ ^[Yy] ]]; then
        CONTINUOUS="true"
    fi

    # Create config JSON
    cat > "${CONFIGFILE}" <<EOF
{
  "departure": "${DEPARTURE}",
  "arrival": "${ARRIVAL}",
  "date": "${DATE}",
  "time": "${TIME}",
  "adults": ${ADULTS},
  "children": ${CHILDREN},
  "vehicle": ${VEHICLE},
  "pollInterval": ${POLL_INTERVAL},
  "timeout": ${TIMEOUT},
  "continuous": ${CONTINUOUS}
}
EOF

    echo ""
    echo "Configuration saved to ${CONFIGFILE}"
    echo ""
    echo "Configuration:"
    jq '.' "${CONFIGFILE}"
    echo ""
    echo "Run 'ferry-monitor-daemon start' to begin monitoring"
}

function show_help() {
    cat <<EOF
Ferry Monitor Daemon Manager

Usage: ferry-monitor-daemon <command> [options]

Commands:
  start      Start the ferry monitor daemon
  stop       Stop the ferry monitor daemon
  restart    Restart the ferry monitor daemon
  status     Check daemon status
  logs       Show recent log entries (default: 50 lines)
  config     Configure monitoring parameters
  help       Show this help message

Examples:
  # Configure monitoring
  ferry-monitor-daemon config

  # Start monitoring in background
  ferry-monitor-daemon start

  # Check if running
  ferry-monitor-daemon status

  # View logs
  ferry-monitor-daemon logs 100

  # Stop monitoring
  ferry-monitor-daemon stop

Configuration file: ${CONFIGFILE}
Log file: ${LOGFILE}
PID file: ${PIDFILE}
EOF
}

# Main command dispatcher
case "${1}" in
    start)
        start_monitor
        ;;
    stop)
        stop_monitor
        ;;
    restart)
        stop_monitor
        sleep 1
        start_monitor
        ;;
    status)
        status_monitor
        ;;
    logs)
        show_logs "${2}"
        ;;
    config)
        configure_monitor
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        echo "Unknown command: ${1}"
        echo "Run 'ferry-monitor-daemon help' for usage"
        exit 1
        ;;
esac
