# Claude Agent Studio Worker Template

E2B template for Claude Agent Studio workers. This repository contains the container definitions that workers run in.

## Templates

### Standard Worker Template (`Dockerfile`)
Used by regular workers for general task execution.

**Includes:**
- Node.js 20
- Claude Code CLI
- Playwright with Chromium browser (for browser automation)
- Python 3
- Basic utilities (curl, wget, git, jq)

### Infrastructure Worker Template (`infrastructure.Dockerfile`)
Used by infrastructure workers that can modify this repository.

**Additional capabilities:**
- GitHub CLI (gh) - Create PRs, manage issues
- E2B CLI - Rebuild templates
- Docker CLI - Analyze and modify Dockerfiles
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
