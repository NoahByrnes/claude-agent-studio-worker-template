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
- Python 3 with bc-ferries-monitor dependencies
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

### BC Ferries Monitoring and Scraping

Workers have integrated bc-ferries-monitor Python project for automated BC Ferries availability checking and booking.

**Capabilities:**
- Multi-route ferry availability scraping (any BC Ferries route)
- Multi-day availability checks for consecutive days
- Passenger configuration (adults, children, infants, seniors)
- Vehicle support (standard and oversized)
- Real-time monitoring mode with refresh tracking
- JSON and CSV output formats
- Headless browser operation

**Example usage in Python:**
```python
import subprocess
import json

# Check ferry availability
result = subprocess.run([
    'python3', 'bc_ferries_scraper.py',
    '--from', 'Departure Bay',
    '--to', 'Horseshoe Bay',
    '--date', '2025-10-20',
    '--adults', '2',
    '--output', 'json',
    '--headless'
], capture_output=True, text=True)

# Parse results
availability = json.loads(result.stdout)
```

**Available Python dependencies:**
- FastAPI 0.104.1 (REST API framework)
- Playwright 1.40.0 (browser automation)
- SQLAlchemy 2.0.23 (database ORM)
- Requests 2.31.0 (HTTP client)
- Pydantic 2.5.0 (data validation)
- PostgreSQL support (psycopg2-binary)
- And more (see requirements.txt)

**Use cases:**
- Ferry availability tracking for trip planning
- Price monitoring across dates
- Real-time availability alerts for sold-out sailings
- Automated booking workflow integration
- Data collection for ferry schedules and pricing patterns

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
