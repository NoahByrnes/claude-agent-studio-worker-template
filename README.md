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

### BC Ferries Availability Polling

Workers have the `wait-for-ferry` command-line tool for polling BC Ferries availability.

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
- `--poll-interval` - Seconds between checks (default: 60)
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
