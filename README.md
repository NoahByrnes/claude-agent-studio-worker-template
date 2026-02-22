# Claude Agent Studio Worker Template

E2B template for Claude Agent Studio workers. This repository contains the container definitions that workers run in.

## Templates

### Conductor Template (`conductor.Dockerfile`)
Used by Stu for orchestration and coordination.

**Includes:**
- Node.js 20
- Claude Code CLI with token budget limits ($20 default)
- claude-mem plugin for persistent memory
- Bun runtime
- SMS/Email handling capabilities:
  - Twilio CLI and Python SDK (for SMS/phone)
  - SendGrid Python SDK (for email)
  - Email validation utilities
- Timestamp and timezone support:
  - tzdata with configurable TZ environment variable (default: UTC)
  - Day.js and Moment.js with timezone support (Node.js)
  - python-dateutil and pytz (Python)
- Cron system for proactive status updates:
  - Scheduled status updates via SMS/email
  - Configurable intervals and recipients
  - Automatic log rotation
- Basic utilities (curl, wget, git, jq, cron)

### Standard Worker Template (`Dockerfile`)
Used by regular workers for general task execution.

**Includes:**
- Node.js 20
- Claude Code CLI with token budget limits ($5 default)
- Destructive Command Guard (dcg) - Safety protection against destructive bash commands
- Playwright with Chromium browser (for browser automation)
- Persistent storage helpers (S3, HTTP, local)
- AWS CLI (for S3 operations)
- Python 3 with BC Ferries polling tool
- Basic utilities (curl, wget, git, jq)

### Infrastructure Worker Template (`infrastructure.Dockerfile`)
Used by infrastructure workers that can modify this repository.

**Includes:**
- Node.js 20
- Claude Code CLI with token budget limits ($10 default)

**Additional capabilities:**
- GitHub CLI (gh) - Create PRs, manage issues
- E2B CLI - Rebuild templates
- Docker CLI - Analyze and modify Dockerfiles
- Persistent storage helpers (S3, HTTP, local)
- AWS CLI (for S3 operations)
- Git configuration for commits

## Building Templates

### Conductor Template
```bash
e2b template build -f conductor.Dockerfile --name claude-agent-studio-conductor
```

### Standard Worker Template
```bash
e2b template build
```

### Infrastructure Worker Template
```bash
e2b template build -f infrastructure.Dockerfile --name claude-agent-studio-worker-infra
```

## Usage

Workers are automatically spawned by Stu (the conductor) using these templates. Template IDs are configured via environment variables:

- `E2B_CONDUCTOR_TEMPLATE_ID` - Conductor template (Stu's environment)
- `E2B_TEMPLATE_ID` - Standard worker template
- `E2B_INFRASTRUCTURE_TEMPLATE_ID` - Infrastructure worker template

### Token Budget Limits (Cost Protection)

All worker templates include automatic token budget limits to prevent runaway costs. Budget limits apply only to non-interactive `claude --print` mode.

**Default budgets:**
- **Standard workers**: $5.00 per session
- **Infrastructure workers**: $10.00 per session
- **Conductor (Stu)**: $20.00 per session

**Environment variables:**
```bash
# Override budget for standard workers
export WORKER_MAX_BUDGET_USD="10.00"

# Override budget for infrastructure workers
export INFRASTRUCTURE_MAX_BUDGET_USD="15.00"

# Override budget for conductor
export CONDUCTOR_MAX_BUDGET_USD="50.00"

# Disable budget limits (not recommended)
export WORKER_MAX_BUDGET_USD="disabled"
```

**How it works:**
- Budget limits automatically apply to `claude --print` commands
- Interactive sessions (`claude` without `--print`) have no limits (user controls)
- Workers hit budget limit will stop gracefully with clear error message
- Users can override budget per-invocation: `claude --print --max-budget-usd 25.00`

**Example usage:**
```bash
# Standard worker with default $5 budget
claude --print "Analyze this codebase"

# Override budget for expensive task
claude --print --max-budget-usd 15.00 "Deep analysis with multiple tools"

# Interactive session - no budget limit
claude
```

**Benefits:**
- Prevents accidental cost overruns from infinite loops or recursive tasks
- Provides predictable cost ceiling per worker session
- Flexible: Environment variables allow per-deployment customization
- Transparent: Workers get clear error when hitting budget limit

### Conductor SMS/Email Capabilities

The conductor template includes comprehensive SMS and email handling with full timestamp support.

#### Timestamp Handling

**Timezone Configuration:**
```bash
# Set timezone via environment variable (defaults to UTC)
export TZ="America/Los_Angeles"
export TZ="America/New_York"
export TZ="Europe/London"
```

**Python timestamp utilities:**
```python
from datetime import datetime
import pytz
from dateutil import parser

# Parse message timestamp with timezone awareness
timestamp = parser.parse("2026-02-22T10:30:00-08:00")

# Convert to different timezone
ny_tz = pytz.timezone('America/New_York')
ny_time = timestamp.astimezone(ny_tz)

# Format for display
print(timestamp.strftime("%Y-%m-%d %I:%M %p %Z"))
```

**Node.js timestamp utilities:**
```javascript
const dayjs = require('dayjs');
const utc = require('dayjs/plugin/utc');
const timezone = require('dayjs/plugin/timezone');

dayjs.extend(utc);
dayjs.extend(timezone);

// Parse and convert message timestamp
const timestamp = dayjs.tz("2026-02-22 10:30", "America/Los_Angeles");
const nyTime = timestamp.tz("America/New_York");

console.log(nyTime.format("YYYY-MM-DD hh:mm A z"));
```

#### SMS via Twilio

**Python SDK:**
```python
from twilio.rest import Client
import os

client = Client(
    os.environ['TWILIO_ACCOUNT_SID'],
    os.environ['TWILIO_AUTH_TOKEN']
)

# Send SMS with timestamp tracking
message = client.messages.create(
    body="Your message here",
    from_=os.environ['TWILIO_PHONE_NUMBER'],
    to="+1234567890"
)

print(f"Message SID: {message.sid}")
print(f"Sent at: {message.date_sent}")
print(f"Status: {message.status}")
```

**Twilio CLI:**
```bash
# Configure credentials
export TWILIO_ACCOUNT_SID="your_account_sid"
export TWILIO_AUTH_TOKEN="your_auth_token"

# Send SMS
twilio api:core:messages:create \
  --from "+1234567890" \
  --to "+0987654321" \
  --body "Your message"

# List recent messages with timestamps
twilio api:core:messages:list --limit 10
```

#### Email via SendGrid

**Python SDK:**
```python
from sendgrid import SendGridAPIClient
from sendgrid.helpers.mail import Mail
import os
from datetime import datetime

# Create timestamped email
message = Mail(
    from_email='from@example.com',
    to_emails='to@example.com',
    subject=f'Message at {datetime.now().isoformat()}',
    html_content='<strong>Your email content</strong>'
)

# Send with timestamp in custom headers
message.add_header('X-Sent-Timestamp', datetime.now().isoformat())

sg = SendGridAPIClient(os.environ['SENDGRID_API_KEY'])
response = sg.send(message)

print(f"Status: {response.status_code}")
print(f"Headers: {response.headers}")
```

#### Email Validation

```python
from email_validator import validate_email, EmailNotValidError

try:
    valid = validate_email("user@example.com")
    email = valid.email  # Normalized form
    print(f"Valid email: {email}")
except EmailNotValidError as e:
    print(f"Invalid email: {e}")
```

**Environment Variables for SMS/Email:**
```bash
# Twilio (SMS)
export TWILIO_ACCOUNT_SID="your_account_sid"
export TWILIO_AUTH_TOKEN="your_auth_token"
export TWILIO_PHONE_NUMBER="+1234567890"

# SendGrid (Email)
export SENDGRID_API_KEY="your_api_key"

# Timezone (optional, defaults to UTC)
export TZ="America/Los_Angeles"
```

### Proactive Status Updates with Cron

The conductor template includes a cron-based system for sending proactive status updates via SMS or email at scheduled intervals.

#### Setup

**Enable status updates:**
```bash
# Configure recipients (comma-separated phone numbers or emails)
export STATUS_UPDATE_RECIPIENTS="user@example.com,+1234567890"

# Choose method: "sms" or "email" (default: email)
export STATUS_UPDATE_METHOD="email"

# Enable cron updates
export STATUS_UPDATE_ENABLED="true"

# Optional: Custom schedule (default: every 6 hours)
export STATUS_UPDATE_SCHEDULE="0 */6 * * *"

# Run setup script
/usr/local/bin/setup-cron.sh
```

#### Cron Schedule Examples

```bash
# Every hour
setup-cron.sh "0 * * * *"

# Every 30 minutes
setup-cron.sh "*/30 * * * *"

# Twice daily (9am and 9pm)
setup-cron.sh "0 9,21 * * *"

# Daily at 3am
setup-cron.sh "0 3 * * *"

# Every 6 hours (default)
setup-cron.sh "0 */6 * * *"

# Disable updates
setup-cron.sh disable
```

#### Status Update Content

Each status update includes:
- Timestamp with timezone
- System uptime
- Memory usage (used/total)
- Disk usage (used/total/percentage)
- Operational status

**Example status message:**
```
Conductor Status Update
Time: 2026-02-22 15:30:00 UTC
Uptime: 3 days, 12:45
Memory: Used: 384Mi / Total: 1024Mi
Disk: Used: 2.1G / Total: 10G (21% used)

Status: Operational
```

#### Manual Status Updates

Send a status update manually at any time:
```bash
/usr/local/bin/status-update.sh
```

#### Logs

Cron job logs are stored in `/var/log/conductor-cron/`:
- `status-update.log` - Status update execution log
- `setup.log` - Cron setup log

View recent logs:
```bash
tail -f /var/log/conductor-cron/status-update.log
```

#### Environment Variables Summary

```bash
# Required for any status updates
STATUS_UPDATE_RECIPIENTS="email1@example.com,email2@example.com"

# Optional configuration
STATUS_UPDATE_METHOD="email"           # "email" or "sms"
STATUS_UPDATE_ENABLED="true"           # Must be "true" to enable
STATUS_UPDATE_SCHEDULE="0 */6 * * *"   # Cron schedule expression
STATUS_UPDATE_FROM_EMAIL="stu@conductor.local"  # From address for emails

# Required for SMS (via Twilio)
TWILIO_ACCOUNT_SID="your_account_sid"
TWILIO_AUTH_TOKEN="your_auth_token"
TWILIO_PHONE_NUMBER="+1234567890"

# Required for Email (via SendGrid)
SENDGRID_API_KEY="your_api_key"
```

### Browser Automation with Playwright

Workers have Playwright with Chromium installed for browser automation tasks. This enables cost-effective browser interactions without the computer use API.

**Example usage:**
```javascript
const { chromium } = require('playwright');

async function scrapeWebsite() {
  const browser = await chromium.launch({ headless: true });
  const page = await browser.newPage();
  await page.goto('https://example.com');
  const content = await page.content();
  await browser.close();
  return content;
}
```

**Benefits:**
- ~25x more cost-effective than computer use API ($0.01 vs $0.25 per task)
- Faster execution (no screenshot processing overhead)
- Full browser automation capabilities (form filling, clicking, navigation)

### Safety Features - Destructive Command Guard

Workers are protected by `destructive_command_guard` (dcg), a high-performance security hook that intercepts and blocks destructive commands before execution, preventing accidental data loss from AI agent actions.

**What it blocks:**
- `git reset --hard` / `git reset --merge` - Discards uncommitted work
- `git checkout -- <file>` - Discards file modifications
- `git clean -f` - Deletes untracked files
- `git push --force` - Rewrites remote history
- `git stash drop` / `git stash clear` - Permanently deletes stashed work
- `rm -rf` outside temp directories - Recursive deletion of important files

**What it allows:**
- Safe git operations: `git status`, `git log`, `git add`, `git commit`, `git push`, `git pull`
- Safe branch deletion: `git branch -d` (requires merge check)
- Temp directory cleanup: `rm -rf /tmp/*` or `rm -rf $TMPDIR/*`
- Standard stash operations: `git stash`, `git stash pop`

**Key features:**
- Sub-millisecond latency (SIMD-accelerated pattern matching)
- Zero configuration required - Works out of the box
- Smart context detection - Won't block `grep "rm -rf"` but will block `rm -rf /`
- AST-based scanning for heredocs and inline scripts (Python, JavaScript, Bash, etc.)
- Fail-open design - Never blocks workflow due to timeouts

**Configuration:**
Additional protection packs can be enabled in `~/.config/dcg/config.toml` for databases (PostgreSQL, MySQL), cloud providers (AWS, Azure, GCP), containers (Docker), Kubernetes, and more.

**Learn more:** [Destructive Command Guard on GitHub](https://github.com/Dicklesworthstone/destructive_command_guard)

### BC Ferries Tools

Workers have comprehensive BC Ferries tools for monitoring and booking.

#### 1. Availability Polling (`wait-for-ferry`)

Poll BC Ferries API for sailing availability.

**Usage:**
```bash
# Wait for a specific sailing to become available
wait-for-ferry \
  --from "Departure Bay" \
  --to "Horseshoe Bay" \
  --date "10/15/2025" \
  --time "1:20 pm" \
  --adults 2 \
  --vehicle \
  --verbose

# Walk-on passenger, check every 30 seconds
wait-for-ferry \
  --from tsawwassen \
  --to swartz_bay \
  --date "12/25/2025" \
  --time "9:00 am" \
  --no-vehicle \
  --poll-interval 30

# JSON output for programmatic use
wait-for-ferry \
  --from nanaimo \
  --to vancouver \
  --date "01/01/2026" \
  --time "3:00 pm" \
  --adults 2 \
  --children 2 \
  --timeout 7200 \
  --json
```

**Exit codes:**
- `0` - Sailing became available
- `1` - Timeout reached (not available)
- `2` - Invalid arguments or API error

**Options:**
- `--from`, `--to` - Terminal names (e.g., "Departure Bay", "Horseshoe Bay")
- `--date` - Date in MM/DD/YYYY format (e.g., "10/15/2025")
- `--time` - Departure time (e.g., "1:20 pm" or "13:20")
- `--adults`, `--children`, `--seniors`, `--infants` - Passenger counts
- `--vehicle` / `--no-vehicle` - Travelling with vehicle (default) or walk-on
- `--poll-interval` - Seconds between checks (default: 10)
- `--timeout` - Maximum wait time in seconds (default: 3600)
- `--verbose` - Show detailed progress
- `--json` - Output result as JSON

**How it works:**
- Polls the BC Ferries REST API (no browser automation needed)
- Returns immediately when sailing becomes available
- Exits with code 0 on success, 1 on timeout
- Minimal resource usage (only HTTP requests library)

**Use cases:**
- Wait for sold-out sailings to become available
- Monitor availability for trip planning
- Trigger booking workflows when spots open up
- Alert systems for ferry availability changes

#### 2. Auto-Booking (`bc-ferries-book`)

Automated browser-based booking using Playwright. Completes entire booking flow from login to payment.

**Usage:**
```bash
# Book a ferry sailing (dry run by default - no payment)
bc-ferries-book

# With environment variables:
export DEPARTURE="Departure Bay"
export ARRIVAL="Horseshoe Bay"
export DATE="2026-01-24"
export SAILING_TIME="1:10 pm"
export ADULTS="2"
export VEHICLE_HEIGHT="under_7ft"
export VEHICLE_LENGTH="under_20ft"
export BC_FERRIES_EMAIL="user@example.com"
export BC_FERRIES_PASSWORD="password"
export CC_NAME="John Doe"
export CC_NUMBER="4111111111111111"
export CC_EXPIRY="12/26"
export CC_CVV="123"
export CC_ADDRESS="123 Main St"
export CC_CITY="Vancouver"
export CC_PROVINCE="British Columbia"
export CC_POSTAL="V6B 1A1"
export DRY_RUN="true"  # Set to "false" to actually submit payment

bc-ferries-book
```

**Output:**
```json
{
  "success": true,
  "confirmationNumber": "BC12345",
  "failedStep": null,
  "error": null
}
```

**Exit codes:**
- `0` - Booking succeeded
- `1` - Booking failed (check JSON output for details)

**Steps automated:**
1. Login to BC Ferries account
2. Navigate to booking flow
3. Select departure/arrival terminals
4. Select travel date
5. Add passengers
6. Select vehicle dimensions
7. Find and select specific sailing time
8. Select fare type (reservation only)
9. Proceed to checkout
10. Fill payment form
11. Submit payment (if `DRY_RUN=false`)

**Security:**
- Credentials passed via environment variables (encrypted in E2B)
- Screenshots saved on errors for debugging
- Dry run mode by default (prevents accidental charges)

#### 3. Watch and Book Daemon (`bc-ferries-watch-and-book`)

**NEW: Background daemon that combines monitoring + auto-booking in one command.**

The daemon runs in the background, continuously monitors for availability, and automatically triggers booking when a sailing becomes available. Perfect for workers that need to launch long-running tasks and move on to other work.

**Features:**
- Runs as background daemon (non-blocking)
- Monitors API every 10 seconds for availability
- Automatically books when sailing becomes available
- Process management (start/stop/status)
- Writes results to `/tmp/ferry-booking-result.json`
- Comprehensive logging to `/tmp/ferry-watch-and-book.log`

**Usage:**

```bash
# Set booking credentials (required)
export BC_FERRIES_EMAIL="user@example.com"
export BC_FERRIES_PASSWORD="password"
export CC_NAME="John Doe"
export CC_NUMBER="4111111111111111"
export CC_EXPIRY="12/26"
export CC_CVV="123"
export CC_ADDRESS="123 Main St"
export CC_CITY="Vancouver"
export CC_PROVINCE="British Columbia"
export CC_POSTAL="V6B 1A1"
export VEHICLE_HEIGHT="under_7ft"
export VEHICLE_LENGTH="under_20ft"
export DRY_RUN="true"  # Set to "false" for real booking

# Start daemon (non-blocking - returns immediately)
bc-ferries-watch-and-book start \
  --from "Departure Bay" \
  --to "Horseshoe Bay" \
  --date "01/24/2026" \
  --time "1:10 pm" \
  --adults 2 \
  --vehicle \
  --daemon

# Worker can now continue other tasks...
# Daemon runs in background monitoring for availability

# Check status
bc-ferries-watch-and-book status

# View logs
bc-ferries-watch-and-book logs

# Stop daemon
bc-ferries-watch-and-book stop

# Read final result
cat /tmp/ferry-booking-result.json
```

**Status output:**
```json
{
  "status": "monitoring",
  "timestamp": "2026-01-18T20:45:00",
  "pid": 1234,
  "from": "Departure Bay",
  "to": "Horseshoe Bay",
  "date": "01/24/2026",
  "time": "1:10 pm",
  "poll_interval": 10
}
```

**Result output (after completion):**
```json
{
  "success": true,
  "timestamp": "2026-01-18T21:00:00",
  "phase": "completed",
  "confirmationNumber": "BC12345",
  "booking_details": {
    "success": true,
    "confirmationNumber": "BC12345",
    "failedStep": null,
    "error": null
  }
}
```

**Commands:**
- `start` - Start monitoring daemon (non-blocking)
- `status` - Check daemon status and progress
- `logs` - View daemon logs
- `stop` - Stop running daemon

**Options:**
- `--from`, `--to` - Terminal names
- `--date` - Date in MM/DD/YYYY format
- `--time` - Sailing time (e.g., "1:10 pm")
- `--adults`, `--children`, `--seniors`, `--infants` - Passenger counts
- `--vehicle` / `--no-vehicle` - Vehicle or walk-on
- `--poll-interval` - Seconds between checks (default: 10)
- `--timeout` - Max monitoring time in seconds (default: 3600)
- `--daemon` / `--no-daemon` - Background mode (default: daemon)

**How it works:**
1. Daemon starts in background (returns immediately)
2. Calls `wait-for-ferry` to monitor API every 10s
3. When sailing becomes available, calls `bc-ferries-book` automatically
4. Writes result to `/tmp/ferry-booking-result.json`
5. Worker can check status/logs/result at any time
6. Daemon exits after booking completes (success or failure)

**Use cases:**
- Long-running ferry monitoring without blocking worker
- Auto-book sold-out sailings when they become available
- Launch multiple monitoring tasks in parallel
- Worker continues other tasks while daemon monitors

**Process files:**
- `/tmp/ferry-watch-and-book.pid` - Process ID
- `/tmp/ferry-watch-and-book-status.json` - Current status
- `/tmp/ferry-booking-result.json` - Final booking result
- `/tmp/ferry-watch-and-book.log` - Detailed logs

#### 4. Playwright Test (`test-playwright`)

Verify Playwright Python bindings are working correctly.

**Usage:**
```bash
test-playwright
```

This will test browser launch, navigation, and screenshot capabilities.

## Worker Watchdog System

Workers can use the watchdog system to detect stuck, crashed, or unresponsive tasks using heartbeat monitoring and dead man's switch pattern.

**Quick start:**
```bash
# In your worker script - send heartbeats periodically
while processing; do
    heartbeat.sh "Processing batch $batch_num"
    process_data
    sleep 10
done

# Start watchdog daemon to monitor heartbeats
watchdog-setup.sh install
watchdog-setup.sh start
```

**Features:**
- Heartbeat monitoring with configurable timeout (default: 90s)
- Dead man's switch - missing heartbeat triggers alert
- Multi-tier alerting via SMS/Email (Twilio/SendGrid)
- Health metrics tracking (memory, CPU, uptime)
- Auto-restart for dead workers (optional)
- Continuous daemon or cron-based checks

**Alert configuration:**
```bash
export STATUS_UPDATE_RECIPIENTS="stu@example.com,+1234567890"
export WATCHDOG_ALERT_METHOD="email"  # or "sms" or "both"
export WATCHDOG_TIMEOUT=90  # seconds before alert
```

**Status monitoring:**
```bash
watchdog-setup.sh status
```

See [WATCHDOG.md](./WATCHDOG.md) for complete documentation, use cases, and best practices.

## Persistent Storage

Workers run in ephemeral environments, but work doesn't have to be lost. The persistent storage system provides automatic multi-tier backup:

**Quick start:**
```bash
# Store a result file
persist-result output.json

# Store with metadata
persist-result --name "final-report" --metadata '{"status":"complete"}' report.pdf
```

**Storage tiers:**
1. S3 (if configured) - Production-ready, $0.023/GB/month
2. HTTP POST (if configured) - Custom backends
3. Local persistence - Always available as backup

**Configuration:**
```bash
export WORKER_RESULTS_S3_BUCKET="my-results-bucket"
export AWS_ACCESS_KEY_ID="..."
export AWS_SECRET_ACCESS_KEY="..."
```

See [PERSISTENT_STORAGE.md](./PERSISTENT_STORAGE.md) for complete documentation, examples, and best practices.

## Self-Modification

Infrastructure workers can modify this repository to add new capabilities:

1. Worker clones this repo
2. Worker edits Dockerfile to add packages/tools
3. Worker creates PR with changes
4. Stu reviews PR for security
5. Stu approves, worker merges
6. Worker rebuilds E2B template
7. New capabilities available to all future workers

## License

MIT
