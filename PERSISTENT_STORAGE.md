# Persistent Storage for Worker Results

Workers run in ephemeral E2B environments that terminate after task completion. This persistent storage solution ensures work results are never lost.

## Overview

The storage system provides three tiers with automatic fallback:

1. **S3 Storage (Primary)** - Most reliable and cost-effective for production
2. **HTTP POST Storage (Secondary)** - For custom storage backends
3. **Local Persistence (Backup)** - E2B volumes can persist between sandbox sessions

Workers automatically try each method in order until one succeeds.

## Quick Start

### Bash Usage

```bash
# Store a file
persist-result output.json

# Store with custom name and metadata
persist-result --name "final-report" --metadata '{"status":"complete","version":"1.0"}' report.pdf

# Store a directory (automatically archived)
persist-result --task-id worker-123 ./results-directory
```

### Node.js Usage

```javascript
const { persistResult, listResults, retrieveResult } = require('persist-result.js');

// Store a file
await persistResult('/workspace/output.json', {
  name: 'final-report',
  metadata: { status: 'complete', version: '1.0' },
  taskId: 'worker-123'
});

// Store string content
await persistResult('{"result": "success"}', {
  name: 'status.json'
});

// Store Buffer
const buffer = Buffer.from('binary data');
await persistResult(buffer, {
  name: 'data.bin',
  contentType: 'application/octet-stream'
});

// List results for a task
const results = await listResults('worker-123');
console.log(results);

// Retrieve a result
const content = await retrieveResult('worker-123/20260114-120000-output.json');
```

## Configuration

Set environment variables to enable storage backends:

### S3 Storage (Recommended)

```bash
export WORKER_RESULTS_S3_BUCKET="my-results-bucket"
export WORKER_RESULTS_S3_PREFIX="results"  # Optional, default: "results"
export AWS_ACCESS_KEY_ID="AKIA..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_DEFAULT_REGION="us-east-1"  # Optional, default: "us-east-1"
```

**Cost:** ~$0.023 per GB/month (S3 Standard)

### HTTP POST Storage

```bash
export WORKER_RESULTS_ENDPOINT="https://api.example.com/results"
```

The endpoint receives a multipart/form-data POST with:
- `file` - The result file
- `key` - Storage key (e.g., "worker-123/20260114-120000-output.json")
- `task_id` - Worker/task identifier
- `metadata` - JSON metadata string

### Local Persistence

```bash
export WORKER_RESULTS_LOCAL_DIR="/workspace/.results"  # Optional, default: "/workspace/.results"
```

Local persistence is always enabled as a backup and requires no configuration.

## Storage Key Format

Results are stored with organized keys:

```
{task_id}/{timestamp}-{name}
```

Examples:
- `worker-123/20260114-120000-output.json`
- `worker-456/20260114-121530-report.pdf.tar.gz`

Timestamps are in UTC format: `YYYYMMDD-HHMMSS`

## Use Cases

### 1. Long-Running Tasks

```bash
# At the end of a long task
persist-result --name "analysis-complete" results.json
```

### 2. Incremental Results

```javascript
// Save checkpoints during processing
for (let i = 0; i < data.length; i += 1000) {
  const chunk = processChunk(data.slice(i, i + 1000));
  await persistResult(JSON.stringify(chunk), {
    name: `checkpoint-${i}.json`,
    metadata: { progress: i / data.length }
  });
}
```

### 3. Multi-File Results

```bash
# Organize results in a directory, then persist
mkdir -p /workspace/final-results
cp output.json final-results/
cp report.pdf final-results/
cp data.csv final-results/

# Automatically archives as .tar.gz
persist-result --name "final-results" /workspace/final-results
```

### 4. Error Recovery

```javascript
try {
  const result = await performTask();
  await persistResult(JSON.stringify(result), { name: 'success.json' });
} catch (error) {
  // Save error details before worker terminates
  await persistResult(JSON.stringify({
    error: error.message,
    stack: error.stack,
    timestamp: new Date().toISOString()
  }), { name: 'error.json' });
  throw error;
}
```

## Retrieval

### From Local Storage

```bash
# List results
persist-result.js --list worker-123

# Retrieve a result
persist-result.js --retrieve worker-123/20260114-120000-output.json > output.json
```

### From S3

```bash
# Direct download
aws s3 cp s3://my-results-bucket/results/worker-123/20260114-120000-output.json output.json

# List all results for a task
aws s3 ls s3://my-results-bucket/results/worker-123/
```

### From HTTP Storage

Depends on your storage backend implementation. Results are sent to the configured endpoint.

## Metadata

Attach structured metadata to results for organization and querying:

```bash
persist-result --metadata '{
  "status": "complete",
  "duration_ms": 45000,
  "records_processed": 10000,
  "version": "1.0.0"
}' output.json
```

Metadata is stored:
- S3: As object metadata (queryable with S3 Select)
- HTTP: Sent in POST request
- Local: In `.meta.json` file alongside result

## Best Practices

1. **Always persist important results** - Workers can terminate unexpectedly
2. **Use descriptive names** - Makes retrieval easier
3. **Include metadata** - Add context for future reference
4. **Persist early and often** - For long-running tasks, save checkpoints
5. **Configure S3 for production** - Most reliable and cost-effective
6. **Test retrieval** - Verify you can access results after worker termination

## Cost Estimates

### S3 Storage (Recommended)

- **Storage:** $0.023/GB/month (S3 Standard)
- **PUT requests:** $0.005 per 1,000 requests
- **GET requests:** $0.0004 per 1,000 requests

**Example:** 1,000 workers storing 10MB each:
- Storage: 10GB × $0.023 = $0.23/month
- PUT: 1,000 × $0.005/1000 = $0.005
- **Total: ~$0.24/month**

### Local Persistence

- **Cost:** Included in E2B sandbox cost
- **Reliability:** Medium (lost if sandbox is deleted)
- **Best for:** Temporary caching, development

## Troubleshooting

### "S3 storage failed"

Check credentials and bucket access:
```bash
aws s3 ls s3://my-results-bucket/
```

### "HTTP storage failed"

Verify endpoint is accessible:
```bash
curl -X POST "$WORKER_RESULTS_ENDPOINT" \
  -F "file=@test.txt" \
  -F "key=test" \
  -F "task_id=test"
```

### "All storage methods failed"

This should be rare (local persistence usually succeeds). Check:
- Disk space: `df -h /workspace`
- Permissions: `ls -ld /workspace/.results`
- Logs for specific errors

## Security

- **Never commit AWS credentials** - Use environment variables
- **Use IAM roles when possible** - For production deployments
- **Restrict S3 bucket access** - Limit to worker IP ranges or VPC
- **Validate metadata** - Don't trust user-provided metadata without sanitization
- **Encrypt sensitive results** - Use S3 encryption at rest

## Integration with Stu (Conductor)

Stu can configure storage for all workers:

```javascript
// In conductor.js
const workerEnv = {
  WORKER_RESULTS_S3_BUCKET: process.env.WORKER_RESULTS_S3_BUCKET,
  WORKER_RESULTS_S3_PREFIX: 'results',
  AWS_ACCESS_KEY_ID: process.env.AWS_ACCESS_KEY_ID,
  AWS_SECRET_ACCESS_KEY: process.env.AWS_SECRET_ACCESS_KEY,
  WORKER_ID: workerId,
};

// Pass to worker
const sandbox = await E2B.Sandbox.create({
  template: process.env.E2B_TEMPLATE_ID,
  envVars: workerEnv,
});
```

Workers automatically inherit configuration and persist results before termination.

## Examples

See the [examples directory](./examples) for complete examples:
- [Basic file storage](./examples/basic-storage.sh)
- [Incremental checkpoints](./examples/incremental-checkpoints.js)
- [Error recovery](./examples/error-recovery.js)
- [Multi-file results](./examples/multi-file-results.sh)
