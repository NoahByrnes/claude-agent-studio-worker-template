# Worker Tools and Capabilities

This document describes the specialized tools and capabilities available to workers in the Claude Agent Studio environment. These tools extend beyond standard command-line utilities and enable workers to handle domain-specific tasks efficiently.

## BC Ferries Availability Polling

### Overview
Workers have access to the `wait-for-ferry` command-line tool for monitoring BC Ferries sailing availability in real-time. This tool polls the BC Ferries REST API and waits until a specific sailing becomes available.

### When to Use This Tool

**Use `wait-for-ferry` when:**
- A user wants to monitor availability for a sold-out sailing
- You need to wait for spots to open up on a specific ferry
- The user wants to be notified when a sailing becomes available
- You're building a workflow that depends on ferry availability

**DO NOT use browser automation (Playwright) for BC Ferries availability checking:**
- The `wait-for-ferry` tool is more efficient and cost-effective
- It uses the REST API directly (no browser overhead)
- Minimal resource usage (only HTTP requests library ~5MB)
- More reliable than web scraping

### Command Syntax

```bash
wait-for-ferry \
  --from <departure_terminal> \
  --to <arrival_terminal> \
  --date <MM/DD/YYYY> \
  --time <departure_time> \
  [--adults N] [--children N] [--seniors N] [--infants N] \
  [--vehicle | --no-vehicle] \
  [--poll-interval SECONDS] \
  [--timeout SECONDS] \
  [--verbose] [--json]
```

### Parameters

**Required:**
- `--from` - Departure terminal name (case-insensitive)
  - Examples: "Departure Bay", "Horseshoe Bay", "Tsawwassen", "Swartz Bay"
  - Short forms accepted: "nanaimo", "vancouver", "victoria"
- `--to` - Arrival terminal name (same format as --from)
- `--date` - Departure date in MM/DD/YYYY format
  - Example: "10/15/2025"
- `--time` - Departure time in 12-hour or 24-hour format
  - Examples: "1:20 pm", "13:20", "9:00 am"

**Passenger Configuration (optional):**
- `--adults N` - Number of adults (age 12+) [default: 1]
- `--children N` - Number of children (age 5-11) [default: 0]
- `--seniors N` - Number of seniors (age 65+) [default: 0]
- `--infants N` - Number of infants (age 0-4, free) [default: 0]

**Vehicle Configuration (optional):**
- `--vehicle` - Travelling with standard vehicle (default)
- `--no-vehicle` - Walk-on passenger (no vehicle)

**Polling Configuration (optional):**
- `--poll-interval N` - Seconds between API checks [default: 60]
  - Warning: Values < 10 may hit rate limits
- `--timeout N` - Maximum wait time in seconds [default: 3600 (1 hour)]
  - Common values: 1800 (30min), 3600 (1hr), 7200 (2hr)

**Output Options (optional):**
- `--verbose` or `-v` - Show detailed progress on stderr
- `--json` - Output result as JSON (for programmatic use)
- `--quiet` or `-q` - Suppress all output (only exit code)

### Exit Codes

The tool uses exit codes to communicate results:

- **0** - Sailing became available (success)
- **1** - Timeout reached, sailing not available
- **2** - Invalid arguments or API error

### Usage Examples

#### Example 1: Basic Wait for Availability
```bash
# Wait for 1:20pm sailing with 2 adults and a vehicle
wait-for-ferry \
  --from "Departure Bay" \
  --to "Horseshoe Bay" \
  --date "10/15/2025" \
  --time "1:20 pm" \
  --adults 2 \
  --vehicle \
  --verbose

# Exit code 0 = available, 1 = timeout
if [ $? -eq 0 ]; then
  echo "Ferry is now available! Proceed with booking."
else
  echo "Ferry did not become available within timeout period."
fi
```

#### Example 2: Walk-On Passenger
```bash
# Single passenger, no vehicle, check every 30 seconds
wait-for-ferry \
  --from tsawwassen \
  --to swartz_bay \
  --date "12/25/2025" \
  --time "9:00 am" \
  --no-vehicle \
  --poll-interval 30 \
  --timeout 7200
```

#### Example 3: Family with Children
```bash
# 2 adults, 2 children, vehicle, 2-hour timeout
wait-for-ferry \
  --from nanaimo \
  --to vancouver \
  --date "01/01/2026" \
  --time "3:00 pm" \
  --adults 2 \
  --children 2 \
  --vehicle \
  --timeout 7200 \
  --verbose
```

#### Example 4: JSON Output for Automation
```bash
# Get structured JSON output for programmatic processing
result=$(wait-for-ferry \
  --from "Departure Bay" \
  --to "Horseshoe Bay" \
  --date "10/15/2025" \
  --time "1:20 pm" \
  --adults 1 \
  --json)

# Parse JSON result
echo "$result" | jq .
```

Sample JSON output:
```json
{
  "available": true,
  "sailing": {
    "departureTime": "1:20 pm",
    "arrivalTime": "3:15 pm",
    "sailingPrice": {
      "status": "AVAILABLE",
      "fromPrice": "$89.50"
    }
  },
  "elapsed": 245.3,
  "checks": 5,
  "price": "$89.50",
  "status": "AVAILABLE"
}
```

#### Example 5: Conditional Workflow
```bash
# Wait for ferry, then trigger booking workflow
if wait-for-ferry --from "Departure Bay" --to "Horseshoe Bay" \
   --date "11/20/2025" --time "2:00 pm" --adults 2 --vehicle; then

  echo "Ferry available! Starting booking workflow..."
  # Trigger booking automation here
  ./book-ferry.sh

else

  echo "Ferry unavailable. Sending notification to user..."
  # Send notification to user
  ./notify-user.sh "Ferry did not become available"

fi
```

### How It Works

1. **API Polling**: The tool polls the BC Ferries REST API at regular intervals
2. **Availability Check**: Each poll checks if the specified sailing has "AVAILABLE" status
3. **Immediate Return**: Returns immediately when availability is found (no unnecessary waiting)
4. **Timeout Handling**: Exits with code 1 if timeout is reached without availability
5. **Error Handling**: Exits with code 2 on API errors or invalid arguments

### Resource Usage

- **Network**: Minimal (only HTTP requests, ~1-2 KB per check)
- **CPU**: Negligible (sleeps between checks)
- **Memory**: ~5-10 MB (Python interpreter + requests library)
- **Disk**: None (no file operations)

**Cost-effectiveness compared to browser automation:**
- **wait-for-ferry**: ~$0.01 per task (API calls only)
- **Playwright automation**: ~$0.25 per task (browser overhead, screenshots)
- **25x more cost-effective for BC Ferries availability checking**

### Best Practices

1. **Use appropriate poll intervals:**
   - Default (60s) is good for most use cases
   - Shorter intervals (30s) for time-sensitive monitoring
   - Never use intervals < 10s (rate limiting risk)

2. **Set reasonable timeouts:**
   - 1 hour (3600s) for evening/overnight monitoring
   - 2 hours (7200s) for peak season monitoring
   - 30 minutes (1800s) for quick checks

3. **Use verbose mode during development:**
   - Helps debug issues with terminal names, dates, times
   - Shows API status and progress
   - Disable in production (use --quiet or redirect stderr)

4. **Handle exit codes properly:**
   - Check exit code to determine next action
   - Exit code 0 = proceed with booking
   - Exit code 1 = notify user or retry later
   - Exit code 2 = check arguments and API status

5. **Prefer this tool over browser automation:**
   - Always check if wait-for-ferry can solve the task
   - Only use Playwright if you need to actually book the ferry
   - Availability checking should always use wait-for-ferry

### Terminal Name Reference

Common terminal names (case-insensitive):

| Full Name | Short Form | Code |
|-----------|------------|------|
| Departure Bay | nanaimo | NAN |
| Duke Point | - | DUK |
| Horseshoe Bay | vancouver | HSB |
| Swartz Bay | victoria | SWB |
| Tsawwassen | - | TSA |

### Troubleshooting

**Problem: "Sailing not found at <time>"**
- Verify the date format is MM/DD/YYYY
- Check that the time matches exactly (use --verbose to see available times)
- Ensure terminal names are spelled correctly
- Try using short forms (e.g., "nanaimo" instead of "Departure Bay")

**Problem: "Timeout reached"**
- The sailing may be fully booked for the entire timeout period
- Try increasing --timeout value
- Check BC Ferries website to verify sailing exists

**Problem: Exit code 2 (error)**
- Check all required arguments are provided
- Verify date is in the future
- Ensure at least one passenger is specified
- Check API status (bcferries.com may be down)

**Problem: Rate limiting / 429 errors**
- Increase --poll-interval to 60s or higher
- Reduce number of concurrent wait-for-ferry processes

## Browser Automation with Playwright

For tasks that require actual browser interaction (beyond what APIs provide), workers have Playwright with Chromium installed.

### When to Use Playwright

**Use Playwright when:**
- APIs are not available or insufficient
- You need to interact with JavaScript-heavy sites
- Form submission and navigation are required
- You need to handle authentication flows
- The website blocks API access

**DO NOT use Playwright when:**
- An API endpoint exists (like BC Ferries availability)
- Simple HTTP requests would work
- The task can be accomplished with curl/wget

### Example Usage
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

**Cost considerations:**
- Playwright tasks cost ~$0.25 each (browser overhead)
- API-based tools cost ~$0.01 each
- Always prefer API tools when available

## Persistent Storage

Workers run in ephemeral environments, but work can be persisted using the storage system.

### Quick Reference

```bash
# Store a result file
persist-result output.json

# Store with metadata
persist-result --name "final-report" --metadata '{"status":"complete"}' report.pdf

# Store to specific tier
persist-result --tier s3 data.csv
```

**Storage tiers:**
1. S3 (if configured) - Production-ready
2. HTTP POST (if configured) - Custom backends
3. Local persistence - Always available as backup

See [PERSISTENT_STORAGE.md](./PERSISTENT_STORAGE.md) for complete documentation.

## Standard Command-Line Tools

Workers also have access to standard development tools:

- **Node.js 20** - JavaScript/TypeScript runtime
- **Python 3** - Python scripting
- **Git** - Version control
- **curl, wget** - HTTP clients
- **jq** - JSON processing
- **AWS CLI** - S3 operations (when configured)

## Getting Help

For detailed documentation on specific tools:
- BC Ferries: `wait-for-ferry --help`
- Persistent Storage: [PERSISTENT_STORAGE.md](./PERSISTENT_STORAGE.md)
- Playwright: https://playwright.dev/docs/intro
- AWS CLI: `aws help`

## Adding New Tools

Infrastructure workers can add new tools to this template by:
1. Modifying the Dockerfile
2. Creating a PR with the changes
3. Getting approval from Stu (the conductor)
4. Rebuilding the E2B template

See [README.md](./README.md) for the self-modification workflow.
