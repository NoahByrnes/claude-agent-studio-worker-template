#!/bin/bash
#
# Proactive Status Update Script for Conductor (Stu)
# Sends periodic status updates via SMS/Email with timestamp tracking
#
# Environment Variables Required:
#   TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN, TWILIO_PHONE_NUMBER (for SMS)
#   SENDGRID_API_KEY (for email)
#   STATUS_UPDATE_RECIPIENTS - comma-separated list of phone numbers or emails
#   STATUS_UPDATE_METHOD - "sms" or "email" (default: email)
#   TZ - timezone for timestamps (default: UTC)

set -euo pipefail

LOG_FILE="/var/log/conductor-cron/status-update.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S %Z')

# Log function
log() {
    echo "[${TIMESTAMP}] $1" | tee -a "$LOG_FILE"
}

# Get system status
get_status() {
    local uptime_info=$(uptime)
    local memory_info=$(free -h | grep Mem | awk '{print "Used: "$3" / Total: "$2}')
    local disk_info=$(df -h /workspace | tail -1 | awk '{print "Used: "$3" / Total: "$2" ("$5" used)"}')

    cat <<EOF
Conductor Status Update
Time: ${TIMESTAMP}
Uptime: ${uptime_info}
Memory: ${memory_info}
Disk: ${disk_info}

Status: Operational
EOF
}

# Send via Twilio SMS
send_sms() {
    local recipient="$1"
    local message="$2"

    if [[ -z "${TWILIO_ACCOUNT_SID:-}" ]] || [[ -z "${TWILIO_AUTH_TOKEN:-}" ]] || [[ -z "${TWILIO_PHONE_NUMBER:-}" ]]; then
        log "ERROR: Twilio credentials not configured"
        return 1
    fi

    python3 <<PYTHON
from twilio.rest import Client
import os
import sys

try:
    client = Client(
        os.environ['TWILIO_ACCOUNT_SID'],
        os.environ['TWILIO_AUTH_TOKEN']
    )

    message = client.messages.create(
        body="""${message}""",
        from_=os.environ['TWILIO_PHONE_NUMBER'],
        to="${recipient}"
    )

    print(f"SMS sent: {message.sid} at {message.date_sent}")
except Exception as e:
    print(f"ERROR: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON
}

# Send via SendGrid Email
send_email() {
    local recipient="$1"
    local message="$2"

    if [[ -z "${SENDGRID_API_KEY:-}" ]]; then
        log "ERROR: SendGrid API key not configured"
        return 1
    fi

    python3 <<PYTHON
from sendgrid import SendGridAPIClient
from sendgrid.helpers.mail import Mail
import os
import sys

try:
    message = Mail(
        from_email=os.environ.get('STATUS_UPDATE_FROM_EMAIL', 'stu@conductor.local'),
        to_emails="${recipient}",
        subject="Conductor Status Update - ${TIMESTAMP}",
        html_content="""
        <html>
        <body style="font-family: monospace; white-space: pre-wrap;">
${message}
        </body>
        </html>
        """
    )

    # Add timestamp header
    message.add_header('X-Conductor-Timestamp', "${TIMESTAMP}")

    sg = SendGridAPIClient(os.environ['SENDGRID_API_KEY'])
    response = sg.send(message)

    print(f"Email sent: Status {response.status_code}")
except Exception as e:
    print(f"ERROR: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON
}

# Main execution
main() {
    log "Starting status update check"

    # Get recipients
    local recipients="${STATUS_UPDATE_RECIPIENTS:-}"
    if [[ -z "$recipients" ]]; then
        log "No recipients configured (STATUS_UPDATE_RECIPIENTS not set)"
        return 0
    fi

    # Get send method
    local method="${STATUS_UPDATE_METHOD:-email}"

    # Get status message
    local status_message
    status_message=$(get_status)

    # Send to each recipient
    IFS=',' read -ra RECIPIENT_LIST <<< "$recipients"
    for recipient in "${RECIPIENT_LIST[@]}"; do
        recipient=$(echo "$recipient" | xargs)  # trim whitespace

        log "Sending $method to $recipient"

        if [[ "$method" == "sms" ]]; then
            if send_sms "$recipient" "$status_message"; then
                log "✓ SMS sent to $recipient"
            else
                log "✗ Failed to send SMS to $recipient"
            fi
        else
            if send_email "$recipient" "$status_message"; then
                log "✓ Email sent to $recipient"
            else
                log "✗ Failed to send email to $recipient"
            fi
        fi
    done

    log "Status update completed"
}

# Run main function
main "$@"
