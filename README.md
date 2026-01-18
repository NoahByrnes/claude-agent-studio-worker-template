# Claude Agent Studio Worker Template

E2B template for Claude Agent Studio workers. This repository contains the container definitions that workers run in.

## Templates

### Standard Worker Template (`Dockerfile`)
Used by regular workers for general task execution.

**Includes:**
- Node.js 20
- Claude Code CLI
- Playwright with Chromium browser (for browser automation)
- Persistent storage helpers (S3, HTTP, local)
- AWS CLI (for S3 operations)
- Python 3 with BC Ferries polling tool
- Basic utilities (curl, wget, git, jq)

### Infrastructure Worker Template (`infrastructure.Dockerfile`)
Used by infrastructure workers that can modify this repository.

**Additional capabilities:**
- GitHub CLI (gh) - Create PRs, manage issues
- E2B CLI - Rebuild templates
- Docker CLI - Analyze and modify Dockerfiles
- Persistent storage helpers (S3, HTTP, local)
- AWS CLI (for S3 operations)
- Git configuration for commits

## Building Templates

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

- `E2B_TEMPLATE_ID` - Standard worker template
- `E2B_INFRASTRUCTURE_TEMPLATE_ID` - Infrastructure worker template

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
