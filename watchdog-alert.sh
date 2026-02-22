#!/bin/bash
#
# Watchdog Alert Sender
# Sends alerts via SMS/Email when workers timeout
#
# Environment Variables:
#   TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN, TWILIO_PHONE_NUMBER (for SMS)
#   SENDGRID_API_KEY (for email)
#   STATUS_UPDATE_RECIPIENTS - Alert recipients
#   STATUS_UPDATE_FROM_EMAIL - From address for emails
#
# Usage:
#   watchdog-alert.sh --method email --message "Alert text"
#   watchdog-alert.sh --method sms --message "Alert text"

set -euo pipefail

LOG_FILE="/var/log/watchdog/alert.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S %Z')

log() {
    echo "[${TIMESTAMP}] $1" | tee -a "$LOG_FILE"
}

# Parse arguments
METHOD="email"
MESSAGE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --method)
            METHOD="$2"
            shift 2
            ;;
        --message)
            MESSAGE="$2"
            shift 2
            ;;
        *)
            log "Unknown argument: $1"
            exit 1
            ;;
    esac
done

if [[ -z "$MESSAGE" ]]; then
    log "ERROR: --message required"
    exit 1
fi

# Get recipients
RECIPIENTS="${STATUS_UPDATE_RECIPIENTS:-}"
if [[ -z "$RECIPIENTS" ]]; then
    log "No recipients configured (STATUS_UPDATE_RECIPIENTS not set)"
    exit 0
fi

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

    print(f"SMS sent: {message.sid}")
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
        from_email=os.environ.get('STATUS_UPDATE_FROM_EMAIL', 'watchdog@conductor.local'),
        to_emails="${recipient}",
        subject="🚨 Watchdog Alert - ${TIMESTAMP}",
        html_content="""
        <html>
        <body style="font-family: monospace; white-space: pre-wrap;">
${message}

--
Automated alert from Worker Watchdog System
        </body>
        </html>
        """
    )

    message.add_header('X-Alert-Type', 'watchdog')
    message.add_header('X-Alert-Timestamp', "${TIMESTAMP}")

    sg = SendGridAPIClient(os.environ['SENDGRID_API_KEY'])
    response = sg.send(message)

    print(f"Email sent: Status {response.status_code}")
except Exception as e:
    print(f"ERROR: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON
}

# Send to all recipients
IFS=',' read -ra RECIPIENT_LIST <<< "$RECIPIENTS"
for recipient in "${RECIPIENT_LIST[@]}"; do
    recipient=$(echo "$recipient" | xargs)  # trim whitespace

    log "Sending $METHOD alert to $recipient"

    if [[ "$METHOD" == "sms" ]]; then
        if send_sms "$recipient" "$MESSAGE"; then
            log "✓ SMS sent to $recipient"
        else
            log "✗ Failed to send SMS to $recipient"
        fi
    else
        if send_email "$recipient" "$MESSAGE"; then
            log "✓ Email sent to $recipient"
        else
            log "✗ Failed to send email to $recipient"
        fi
    fi
done

log "Alert dispatch completed"
