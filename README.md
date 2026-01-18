# Claude Agent Studio Worker Template

E2B template for Claude Agent Studio workers. This repository contains the container definitions that workers run in.

**📖 For workers:** See [TOOLS.md](./TOOLS.md) for comprehensive documentation on available tools and capabilities.

## Templates

### Standard Worker Template (`Dockerfile`)
Used by regular workers for general task execution.

**Includes:**
- Node.js 20
- Claude Code CLI
- **BC Ferries polling tool** (`wait-for-ferry`) - Monitor sailing availability
- Playwright with Chromium browser (for browser automation)
- Persistent storage helpers (S3, HTTP, local)
- AWS CLI (for S3 operations)
- Python 3
- Basic utilities (curl, wget, git, jq)

**🔧 See [TOOLS.md](./TOOLS.md) for complete tool documentation and usage examples.**

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

### Worker Tools and Capabilities

Workers have access to specialized tools for domain-specific tasks. For detailed documentation on all available tools, see [TOOLS.md](./TOOLS.md).

#### BC Ferries Availability Polling

Monitor BC Ferries sailing availability using the `wait-for-ferry` command:

```bash
wait-for-ferry \
  --from "Departure Bay" \
  --to "Horseshoe Bay" \
  --date "10/15/2025" \
  --time "1:20 pm" \
  --adults 2 \
  --vehicle
```

**Key features:**
- Polls BC Ferries REST API for real-time availability
- Waits until sailing becomes available or timeout is reached
- Exit code 0 on success, 1 on timeout
- 25x more cost-effective than browser automation ($0.01 vs $0.25 per task)
- Supports all routes, passenger configurations, and vehicle options

See [TOOLS.md](./TOOLS.md#bc-ferries-availability-polling) for complete usage guide.

#### Browser Automation with Playwright

For tasks requiring actual browser interaction, workers have Playwright with Chromium installed.

**When to use:**
- Use `wait-for-ferry` for BC Ferries availability checking
- Use Playwright only when APIs are not available or insufficient

See [TOOLS.md](./TOOLS.md#browser-automation-with-playwright) for Playwright usage guide.

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
