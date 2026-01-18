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

#### Ferry Monitor Background Service

The ferry monitor can run as a **background service** while the worker performs other tasks. This allows long-running monitoring without blocking worker operations.

**Quick Start:**
```bash
# Configure monitoring
ferry-monitor-daemon config

# Start monitoring in background
ferry-monitor-daemon start

# Worker can now do other work while monitor runs in background!

# Check status
ferry-monitor-daemon status

# View logs
ferry-monitor-daemon logs

# Stop monitoring
ferry-monitor-daemon stop
```

**Commands:**
- `ferry-monitor-daemon config` - Interactive configuration setup
- `ferry-monitor-daemon start` - Start background monitoring
- `ferry-monitor-daemon stop` - Stop background monitoring
- `ferry-monitor-daemon restart` - Restart the monitor
- `ferry-monitor-daemon status` - Check if monitor is running
- `ferry-monitor-daemon logs [lines]` - View recent log entries

**Configuration Options:**
- Departure/arrival terminals
- Date and time to monitor
- Passenger counts (adults, children)
- Vehicle vs walk-on
- Poll interval (seconds between checks)
- Timeout (max monitoring duration)
- Continuous monitoring (keep checking after availability found)

**Use Cases:**
- Monitor ferry while worker does other tasks
- Long-running availability checks (hours/days)
- Continuous monitoring for trip planning
- Trigger booking workflows when spots open

**How It Works:**
- Runs as a background process (daemon)
- Logs all activity to `/tmp/ferry-monitor/monitor.log`
- Configuration stored in `/tmp/ferry-monitor/config.json`
- Process ID tracked in `/tmp/ferry-monitor/monitor.pid`
- Minimal resource usage (only HTTP polling)

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

**Note:** For long-running monitoring while doing other work, use `ferry-monitor-daemon` instead. It runs the monitor as a background service.

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

#### 3. Playwright Test (`test-playwright`)

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
