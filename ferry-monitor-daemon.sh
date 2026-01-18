#!/bin/bash
# Ferry Monitor Daemon Manager
# Manages background ferry monitoring processes

DAEMON_DIR="/tmp/ferry-monitor"
PIDFILE="${DAEMON_DIR}/monitor.pid"
LOGFILE="${DAEMON_DIR}/monitor.log"
CONFIGFILE="${DAEMON_DIR}/config.json"
BOOKING_RESULT="${DAEMON_DIR}/booking-result.json"

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
                echo \"[\$(date)] Ferry became AVAILABLE!\" >> '${LOGFILE}'

                # Check if auto-booking is enabled
                AUTO_BOOK=\$(jq -r '.autoBook // false' '${CONFIGFILE}')
                if [ \"\${AUTO_BOOK}\" = \"true\" ]; then
                    echo \"[\$(date)] Auto-booking enabled, triggering booking workflow...\" >> '${LOGFILE}'

                    # Export booking environment variables from config
                    export DEPARTURE=\$(jq -r '.departure' '${CONFIGFILE}')
                    export ARRIVAL=\$(jq -r '.arrival' '${CONFIGFILE}')
                    export DATE=\$(jq -r '.bookingDate // .date' '${CONFIGFILE}')
                    export SAILING_TIME=\$(jq -r '.time' '${CONFIGFILE}')
                    export ADULTS=\$(jq -r '.adults // 1' '${CONFIGFILE}')
                    export CHILDREN=\$(jq -r '.children // 0' '${CONFIGFILE}')

                    # Vehicle dimensions from config
                    export VEHICLE_HEIGHT=\$(jq -r '.vehicleHeight // \"under_7ft\"' '${CONFIGFILE}')
                    export VEHICLE_LENGTH=\$(jq -r '.vehicleLength // \"under_20ft\"' '${CONFIGFILE}')

                    # Booking credentials from config (securely stored)
                    export BC_FERRIES_EMAIL=\$(jq -r '.bcFerriesEmail // \"\"' '${CONFIGFILE}')
                    export BC_FERRIES_PASSWORD=\$(jq -r '.bcFerriesPassword // \"\"' '${CONFIGFILE}')
                    export CC_NAME=\$(jq -r '.ccName // \"\"' '${CONFIGFILE}')
                    export CC_NUMBER=\$(jq -r '.ccNumber // \"\"' '${CONFIGFILE}')
                    export CC_EXPIRY=\$(jq -r '.ccExpiry // \"\"' '${CONFIGFILE}')
                    export CC_CVV=\$(jq -r '.ccCvv // \"\"' '${CONFIGFILE}')
                    export CC_ADDRESS=\$(jq -r '.ccAddress // \"\"' '${CONFIGFILE}')
                    export CC_CITY=\$(jq -r '.ccCity // \"\"' '${CONFIGFILE}')
                    export CC_PROVINCE=\$(jq -r '.ccProvince // \"British Columbia\"' '${CONFIGFILE}')
                    export CC_POSTAL=\$(jq -r '.ccPostal // \"\"' '${CONFIGFILE}')
                    export DRY_RUN=\$(jq -r '.dryRun // \"true\"' '${CONFIGFILE}')

                    # Run booking script
                    echo \"[\$(date)] Executing bc-ferries-book...\" >> '${LOGFILE}'
                    /usr/local/bin/bc-ferries-book > '${BOOKING_RESULT}' 2>&1
                    BOOKING_EXIT=\$?

                    if [ \${BOOKING_EXIT} -eq 0 ]; then
                        echo \"[\$(date)] ✅ BOOKING SUCCESSFUL! Results: '${BOOKING_RESULT}'\" >> '${LOGFILE}'
                        cat '${BOOKING_RESULT}' >> '${LOGFILE}'
                    else
                        echo \"[\$(date)] ❌ BOOKING FAILED (exit code: \${BOOKING_EXIT})\" >> '${LOGFILE}'
                        cat '${BOOKING_RESULT}' >> '${LOGFILE}'
                    fi
                else
                    echo \"[\$(date)] Auto-booking disabled, monitoring complete.\" >> '${LOGFILE}'
                fi
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
    echo "=== Monitoring Settings ==="
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

    echo ""
    echo "=== Auto-Booking Settings ==="
    echo ""
    read -p "Enable auto-booking when available? (y/n) [n]: " AUTO_BOOK_INPUT
    AUTO_BOOK_INPUT=${AUTO_BOOK_INPUT:-n}
    AUTO_BOOK="false"

    # Booking credential variables
    BOOKING_DATE="${DATE}"
    VEHICLE_HEIGHT="under_7ft"
    VEHICLE_LENGTH="under_20ft"
    BC_FERRIES_EMAIL=""
    BC_FERRIES_PASSWORD=""
    CC_NAME=""
    CC_NUMBER=""
    CC_EXPIRY=""
    CC_CVV=""
    CC_ADDRESS=""
    CC_CITY=""
    CC_PROVINCE="British Columbia"
    CC_POSTAL=""
    DRY_RUN="true"

    if [[ "${AUTO_BOOK_INPUT}" =~ ^[Yy] ]]; then
        AUTO_BOOK="true"
        echo ""
        echo "⚠️  Auto-booking will run bc-ferries-book when availability is detected"
        echo ""

        read -p "Booking date (YYYY-MM-DD) [${DATE}]: " BOOKING_DATE_INPUT
        BOOKING_DATE=${BOOKING_DATE_INPUT:-${DATE}}

        if [ "${VEHICLE}" = "true" ]; then
            echo ""
            echo "Vehicle dimensions:"
            echo "  1) under_7ft (default)"
            echo "  2) 7ft_to_8ft"
            echo "  3) over_8ft"
            read -p "Vehicle height [1]: " VH_CHOICE
            case "${VH_CHOICE}" in
                2) VEHICLE_HEIGHT="7ft_to_8ft" ;;
                3) VEHICLE_HEIGHT="over_8ft" ;;
                *) VEHICLE_HEIGHT="under_7ft" ;;
            esac

            echo ""
            echo "  1) under_20ft (default)"
            echo "  2) 20ft_to_22ft"
            echo "  3) over_22ft"
            read -p "Vehicle length [1]: " VL_CHOICE
            case "${VL_CHOICE}" in
                2) VEHICLE_LENGTH="20ft_to_22ft" ;;
                3) VEHICLE_LENGTH="over_22ft" ;;
                *) VEHICLE_LENGTH="under_20ft" ;;
            esac
        fi

        echo ""
        echo "=== BC Ferries Account ==="
        read -p "BC Ferries email: " BC_FERRIES_EMAIL
        read -sp "BC Ferries password: " BC_FERRIES_PASSWORD
        echo ""

        echo ""
        echo "=== Payment Information ==="
        read -p "Cardholder name: " CC_NAME
        read -p "Card number: " CC_NUMBER
        read -p "Expiry (MM/YY): " CC_EXPIRY
        read -p "CVV: " CC_CVV
        read -p "Billing address: " CC_ADDRESS
        read -p "City: " CC_CITY
        read -p "Province [British Columbia]: " CC_PROVINCE_INPUT
        CC_PROVINCE=${CC_PROVINCE_INPUT:-British Columbia}
        read -p "Postal code: " CC_POSTAL

        echo ""
        read -p "DRY RUN mode (no actual payment)? (y/n) [y]: " DRY_RUN_INPUT
        DRY_RUN_INPUT=${DRY_RUN_INPUT:-y}
        if [[ "${DRY_RUN_INPUT}" =~ ^[Nn] ]]; then
            DRY_RUN="false"
            echo ""
            echo "⚠️  WARNING: DRY RUN DISABLED - REAL PAYMENT WILL BE CHARGED!"
            read -p "Are you sure? (yes/no): " CONFIRM
            if [ "${CONFIRM}" != "yes" ]; then
                echo "Keeping dry run enabled for safety"
                DRY_RUN="true"
            fi
        else
            DRY_RUN="true"
        fi
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
  "continuous": ${CONTINUOUS},
  "autoBook": ${AUTO_BOOK},
  "bookingDate": "${BOOKING_DATE}",
  "vehicleHeight": "${VEHICLE_HEIGHT}",
  "vehicleLength": "${VEHICLE_LENGTH}",
  "bcFerriesEmail": "${BC_FERRIES_EMAIL}",
  "bcFerriesPassword": "${BC_FERRIES_PASSWORD}",
  "ccName": "${CC_NAME}",
  "ccNumber": "${CC_NUMBER}",
  "ccExpiry": "${CC_EXPIRY}",
  "ccCvv": "${CC_CVV}",
  "ccAddress": "${CC_ADDRESS}",
  "ccCity": "${CC_CITY}",
  "ccProvince": "${CC_PROVINCE}",
  "ccPostal": "${CC_POSTAL}",
  "dryRun": "${DRY_RUN}"
}
EOF

    echo ""
    echo "Configuration saved to ${CONFIGFILE}"
    echo ""
    echo "Monitoring Configuration:"
    jq 'del(.bcFerriesPassword, .ccNumber, .ccCvv)' "${CONFIGFILE}"
    echo ""
    echo "⚠️  Credentials are stored in ${CONFIGFILE}"
    echo "    (Config file contains sensitive data - handle securely!)"
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
