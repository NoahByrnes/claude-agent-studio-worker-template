# Real-Time Worker Monitoring and Oversight System

Comprehensive monitoring system for real-time visibility into worker health, performance, and events.

## Overview

The monitoring system provides:

- **Real-time HTTP API** - Query worker status, metrics, and events via REST endpoints
- **Server-Sent Events (SSE)** - Live streaming of health updates and events
- **Worker Registry** - Centralized discovery and tracking of all workers
- **Structured Event Logging** - JSON-based event log with timestamps
- **Prometheus Metrics** - Compatible with Prometheus/Grafana for visualization
- **CLI Tools** - Command-line interface for querying and monitoring

## Architecture

```
┌─────────────────┐
│  Worker 1       │──┐
│  - heartbeat    │  │
│  - events       │  │
│  - registry     │  │
└─────────────────┘  │
                     ├──> /tmp/watchdog/
┌─────────────────┐  │    ├── heartbeat-*.json
│  Worker 2       │──┤    ├── events.jsonl
│  - heartbeat    │  │    └── registry.json
│  - events       │  │
│  - registry     │  │
└─────────────────┘  │
                     │
┌─────────────────┐  │
│  Worker 3       │──┘
│  - heartbeat    │
│  - events       │
│  - registry     │
└─────────────────┘

         │
         ▼
┌─────────────────────────────┐
│  Monitoring Server          │
│  (monitoring-server.js)     │
│  Port: 9090                 │
│                             │
│  HTTP API Endpoints:        │
│  - GET /health              │
│  - GET /workers             │
│  - GET /workers/:id         │
│  - GET /metrics             │
│  - GET /events              │
│  - GET /stream (SSE)        │
│  - GET /registry            │
└─────────────────────────────┘
         │
         ▼
┌─────────────────────────────┐
│  Monitoring CLI             │
│  (monitoring-cli.sh)        │
│                             │
│  Commands:                  │
│  - health                   │
│  - workers                  │
│  - events                   │
│  - watch                    │
│  - metrics                  │
└─────────────────────────────┘
```

## Components

### 1. Monitoring Server (`monitoring-server.js`)

HTTP server providing real-time monitoring API.

**Start the server:**
```bash
# Default port 9090
monitoring-server.js

# Custom port
MONITORING_PORT=8080 monitoring-server.js

# Run in background
monitoring-server.js &
```

**API Endpoints:**

| Endpoint | Description | Response |
|----------|-------------|----------|
| `GET /health` | System health summary | JSON |
| `GET /workers` | List all workers | JSON array |
| `GET /workers/:id` | Worker details | JSON |
| `GET /metrics` | Prometheus metrics | text/plain |
| `GET /events?limit=N` | Recent events | JSON array |
| `GET /stream` | Live SSE stream | text/event-stream |
| `GET /registry` | Worker registry | JSON |

**Example responses:**

```bash
# Health endpoint
curl http://localhost:9090/health
{
  "status": "healthy",
  "workers": {
    "total": 3,
    "healthy": 3,
    "timeout": 0,
    "registered": 3
  },
  "timestamp": "2026-02-22T10:30:00Z"
}

# Workers endpoint
curl http://localhost:9090/workers
[
  {
    "worker_id": "worker-ferry-1",
    "timestamp": "2026-02-22T10:30:00Z",
    "timestamp_unix": 1740222600,
    "status": "Processing ferry booking",
    "metrics": {
      "memory_mb": 256,
      "cpu_time_seconds": 45,
      "uptime_seconds": 3600,
      "pid": 12345
    },
    "age_seconds": 5,
    "healthy": true,
    "status_level": "ok"
  }
]

# Events endpoint
curl http://localhost:9090/events?limit=10
[
  {
    "worker_id": "worker-ferry-1",
    "timestamp": "2026-02-22T10:30:00Z",
    "timestamp_unix": 1740222600,
    "event_type": "task_started",
    "message": "Started ferry booking",
    "booking_id": "123"
  }
]
```

### 2. Worker Event Logger (`worker-event.sh`)

Log structured events from workers.

**Usage:**
```bash
worker-event.sh <event_type> <message> [extra_json]
```

**Examples:**
```bash
# Simple event
worker-event.sh "task_started" "Processing ferry booking"

# With extra data
worker-event.sh "task_started" "Processing ferry booking" '{"booking_id": "123", "route": "TSA-SWB"}'

# Error event
worker-event.sh "error" "API timeout" '{"endpoint": "/availability", "status": 504, "retry_count": 3}'

# Success event
worker-event.sh "task_completed" "Booking successful" '{"confirmation": "BC12345", "duration_seconds": 45}'

# Custom events
worker-event.sh "metric" "Memory usage high" '{"memory_mb": 980, "threshold_mb": 1024}'
```

**Event types (recommended):**
- `task_started` - Task begins execution
- `task_completed` - Task finishes successfully
- `task_failed` - Task fails
- `error` - Error occurred
- `warning` - Warning or degraded state
- `info` - Informational message
- `metric` - Metric threshold crossed
- `state_change` - Worker state changed

**Output format (JSONL):**

Events are written to `/tmp/watchdog/events.jsonl` (one JSON object per line):

```json
{"worker_id":"worker-ferry-1","timestamp":"2026-02-22T10:30:00Z","timestamp_unix":1740222600,"event_type":"task_started","message":"Processing ferry booking","booking_id":"123"}
{"worker_id":"worker-ferry-1","timestamp":"2026-02-22T10:31:00Z","timestamp_unix":1740222660,"event_type":"task_completed","message":"Booking successful","confirmation":"BC12345"}
```

### 3. Worker Registry (`worker-registry.sh`)

Centralized worker discovery and tracking.

**Register worker:**
```bash
# Basic registration
worker-registry.sh register --task "ferry-booking"

# With tags
worker-registry.sh register --task "ferry-booking" --tags "production,ferry,high-priority"

# With metadata
worker-registry.sh register \
  --task "data-sync" \
  --tags "background,s3" \
  --metadata '{"source":"s3://bucket","dest":"postgres://db"}'
```

**Query registry:**
```bash
# List all registered workers
worker-registry.sh list

# Get specific worker details
worker-registry.sh get worker-ferry-1

# Cleanup stale workers (no heartbeat for 5+ minutes)
worker-registry.sh cleanup 300
```

**Unregister worker:**
```bash
worker-registry.sh unregister
```

**Registry format:**

Registry stored in `/tmp/watchdog/registry.json`:

```json
{
  "workers": {
    "worker-ferry-1": {
      "worker_id": "worker-ferry-1",
      "task": "ferry-booking",
      "tags": ["production", "ferry"],
      "registered_at": "2026-02-22T10:00:00Z",
      "registered_at_unix": 1740220800,
      "hostname": "e2b-sandbox-123",
      "pid": 12345,
      "metadata": {},
      "status": "active"
    }
  },
  "updated_at": "2026-02-22T10:30:00Z"
}
```

### 4. Monitoring CLI (`monitoring-cli.sh`)

Command-line interface for querying monitoring server.

**Usage:**
```bash
# System health
monitoring-cli.sh health

# List workers
monitoring-cli.sh workers

# Worker details
monitoring-cli.sh worker worker-ferry-1

# Recent events
monitoring-cli.sh events 50

# Live health monitoring
monitoring-cli.sh watch

# Prometheus metrics
monitoring-cli.sh metrics
```

**Output examples:**

```bash
$ monitoring-cli.sh health
=== System Health ===
Status: healthy
Timestamp: 2026-02-22T10:30:00Z

Workers:
  Total: 3
  Healthy: 3
  Timeout: 0
  Registered: 3

$ monitoring-cli.sh workers
=== Active Workers ===

WORKER_ID                      STATUS     AGE      LAST_HEARTBEAT                 STATUS_MESSAGE
--------------------------------------------------------------------------------------------------------
worker-ferry-1                 ok         5s       2026-02-22T10:30:00Z           Processing ferry booking
worker-data-sync-2             ok         12s      2026-02-22T10:29:53Z           Syncing data from S3
worker-background-3            ok         8s       2026-02-22T10:29:57Z           Idle
```

## Integration with Existing Systems

### Heartbeat System

The monitoring system extends the existing heartbeat system:

```bash
# Workers still use heartbeat.sh
heartbeat.sh "Processing ferry booking"

# Monitoring server reads heartbeat files
# No changes needed to existing workers
```

### Watchdog System

Monitoring complements the watchdog alerting:

```bash
# Start both systems
monitoring-server.js &       # Real-time monitoring
watchdog-setup.sh start      # Timeout alerting

# Watchdog triggers alerts on timeout
# Monitoring provides real-time visibility
```

### Event Logging

Add event logging to existing workers:

```bash
# Before
heartbeat.sh "Processing ferry booking"
bc-ferries-book

# After (with events)
heartbeat.sh "Processing ferry booking"
worker-event.sh "task_started" "Ferry booking started" '{"route":"TSA-SWB"}'

bc-ferries-book
result=$?

if [[ $result -eq 0 ]]; then
    worker-event.sh "task_completed" "Booking successful"
else
    worker-event.sh "task_failed" "Booking failed" '{"exit_code":$result}'
fi
```

## Complete Worker Example

Here's a full example of a worker using all monitoring features:

```bash
#!/bin/bash
set -euo pipefail

# Configuration
export WORKER_ID="worker-ferry-$(date +%s)"
export WATCHDOG_DIR="/tmp/watchdog"

# Register worker
worker-registry.sh register \
    --task "ferry-booking" \
    --tags "production,ferry" \
    --metadata '{"route":"TSA-SWB","booking_date":"2026-03-15"}'

# Log start event
worker-event.sh "task_started" "Ferry booking worker started" '{"route":"TSA-SWB"}'

# Start heartbeat loop in background
(
    while true; do
        heartbeat.sh "Monitoring ferry availability"
        sleep 30
    done
) &
HEARTBEAT_PID=$!

# Cleanup on exit
cleanup() {
    kill $HEARTBEAT_PID 2>/dev/null || true
    worker-registry.sh unregister
    worker-event.sh "worker_stopped" "Worker shutting down"
}
trap cleanup EXIT INT TERM

# Main work
worker-event.sh "info" "Starting availability check"
heartbeat.sh "Checking ferry availability"

if wait-for-ferry --from tsawwassen --to swartz_bay --date "03/15/2026" --time "3:00 pm"; then
    worker-event.sh "info" "Ferry available - starting booking"
    heartbeat.sh "Booking ferry"

    if bc-ferries-book; then
        worker-event.sh "task_completed" "Booking successful" '{"confirmation":"BC12345"}'
    else
        worker-event.sh "task_failed" "Booking failed" '{"reason":"payment_error"}'
        exit 1
    fi
else
    worker-event.sh "task_failed" "Ferry not available" '{"timeout":true}'
    exit 1
fi

worker-event.sh "task_completed" "Worker completed successfully"
```

## Prometheus Integration

The monitoring server exports Prometheus-compatible metrics:

**Scrape configuration:**

```yaml
# prometheus.yml
scrape_configs:
  - job_name: 'worker-monitoring'
    static_configs:
      - targets: ['localhost:9090']
    metrics_path: /metrics
    scrape_interval: 10s
```

**Available metrics:**

- `workers_total` - Total number of active workers
- `workers_healthy` - Number of healthy workers
- `workers_timeout` - Number of workers in timeout
- `worker_age_seconds{worker_id}` - Age of last heartbeat per worker
- `worker_memory_mb{worker_id}` - Memory usage per worker
- `worker_uptime_seconds{worker_id}` - Uptime per worker

**Grafana dashboard:**

Create panels for:
- Worker count gauge (total, healthy, timeout)
- Worker age time series (detect timeouts)
- Memory usage per worker
- Event rate (from events log)

## Server-Sent Events (SSE)

Live streaming of health updates and events:

```bash
# Listen to SSE stream
curl -N http://localhost:9090/stream

# Output:
data: {"type":"connected","timestamp":"2026-02-22T10:30:00Z"}

data: {"type":"health","data":{"status":"healthy","workers":{"total":3,"healthy":3,"timeout":0}}}

data: {"type":"event","data":{"worker_id":"worker-ferry-1","event_type":"task_started","message":"Processing"}}
```

**Browser integration:**

```javascript
const eventSource = new EventSource('http://localhost:9090/stream');

eventSource.addEventListener('message', (e) => {
    const data = JSON.parse(e.data);

    if (data.type === 'health') {
        updateHealthDisplay(data.data);
    } else if (data.type === 'event') {
        addEventToLog(data.data);
    }
});
```

## Configuration

### Environment Variables

**Monitoring Server:**
```bash
MONITORING_PORT=9090                # HTTP server port
WATCHDOG_DIR=/tmp/watchdog          # Directory for watchdog files
MONITORING_REGISTRY=/tmp/watchdog/registry.json  # Registry file
WATCHDOG_TIMEOUT=90                 # Timeout threshold
```

**Worker Components:**
```bash
WORKER_ID=worker-unique-id          # Worker identifier
WATCHDOG_DIR=/tmp/watchdog          # Watchdog directory
WORKER_EVENT_VERBOSE=false          # Log events to stdout
HEARTBEAT_VERBOSE=false             # Log heartbeats to stdout
```

**Monitoring CLI:**
```bash
MONITORING_URL=http://localhost:9090  # Monitoring server URL
```

## Use Cases

### 1. Conductor (Stu) Monitoring Multiple Workers

Stu spawns workers and monitors them in real-time:

```bash
# Start monitoring server
monitoring-server.js &

# Spawn workers
for i in {1..5}; do
    spawn_worker.sh "task-$i" &
done

# Monitor all workers
monitoring-cli.sh watch
```

### 2. Debugging Stuck Workers

When a worker times out, investigate:

```bash
# List workers (shows timeouts)
monitoring-cli.sh workers

# Get worker details
monitoring-cli.sh worker worker-ferry-1

# Check recent events
monitoring-cli.sh events 100 | grep worker-ferry-1

# Check heartbeat file directly
cat /tmp/watchdog/heartbeat-worker-ferry-1.json | jq
```

### 3. Performance Analysis

Track worker performance over time:

```bash
# Export metrics to Prometheus
curl http://localhost:9090/metrics > metrics.txt

# Analyze memory usage
monitoring-cli.sh workers | awk '{print $1, $6}' | sort -k2 -n

# Event frequency
cat /tmp/watchdog/events.jsonl | jq -r '.event_type' | sort | uniq -c
```

### 4. Automated Monitoring in CI/CD

Check worker health in test pipelines:

```bash
#!/bin/bash
# Start monitoring
monitoring-server.js &
MONITOR_PID=$!

# Run tests with workers
run_integration_tests.sh

# Check health
health=$(monitoring-cli.sh health)
status=$(echo "$health" | grep -Po 'Status: \K\w+')

if [[ "$status" != "healthy" ]]; then
    echo "Workers unhealthy!"
    monitoring-cli.sh workers
    exit 1
fi

kill $MONITOR_PID
```

## File Structure

```
/tmp/watchdog/
  ├── heartbeat-worker-1.json          # Worker 1 heartbeat
  ├── heartbeat-worker-2.json          # Worker 2 heartbeat
  ├── registry.json                    # Worker registry
  └── events.jsonl                     # Event log (JSONL)

/var/log/watchdog/
  ├── watchdog.log                     # Watchdog daemon log
  ├── alert.log                        # Alert dispatch log
  └── monitoring.log                   # Monitoring server log (optional)

/usr/local/bin/
  ├── monitoring-server.js             # Monitoring HTTP server
  ├── worker-event.sh                  # Event logger
  ├── worker-registry.sh               # Registry manager
  ├── monitoring-cli.sh                # CLI tool
  ├── heartbeat.sh                     # Heartbeat sender
  ├── watchdog.sh                      # Watchdog daemon
  └── watchdog-setup.sh                # Watchdog setup
```

## Performance Impact

**Monitoring Server:**
- Memory: ~10-20MB
- CPU: <1% (mostly idle)
- Disk I/O: Minimal (reads only)
- Network: Minimal (HTTP polling)

**Worker Components:**
- Event logging: ~1ms per event
- Registry operations: ~2-5ms per operation
- Heartbeat: ~1ms (unchanged)

**Recommended:**
- ✅ Run monitoring server on conductor
- ✅ Use for production workers
- ✅ Enable event logging for important tasks
- ✅ Register long-running workers
- ⚠️  Limit event frequency for high-throughput workers

## Troubleshooting

### Monitoring server not responding

```bash
# Check if server is running
ps aux | grep monitoring-server

# Check port is listening
netstat -tlnp | grep 9090

# Restart server
pkill -f monitoring-server.js
monitoring-server.js &
```

### Events not appearing

```bash
# Check events file
ls -lh /tmp/watchdog/events.jsonl

# Verify event logging works
worker-event.sh "test" "Test message"
tail /tmp/watchdog/events.jsonl

# Check verbose mode
WORKER_EVENT_VERBOSE=true worker-event.sh "test" "Test with logging"
```

### Registry out of sync

```bash
# Cleanup stale workers
worker-registry.sh cleanup 300

# View registry
cat /tmp/watchdog/registry.json | jq

# Force re-register
worker-registry.sh unregister
worker-registry.sh register --task "my-task"
```

### CLI can't connect

```bash
# Verify monitoring URL
echo $MONITORING_URL

# Test connection
curl http://localhost:9090/health

# Use custom URL
MONITORING_URL=http://localhost:8080 monitoring-cli.sh health
```

## Security Considerations

### Access Control

The monitoring server has no authentication by default. For production:

1. **Network isolation**: Run on private network or localhost only
2. **Firewall rules**: Restrict port 9090 to trusted IPs
3. **Reverse proxy**: Add authentication via nginx/apache
4. **TLS**: Use HTTPS for remote access

### Data Privacy

- Heartbeat files contain: worker ID, timestamps, memory usage
- Events may contain: task names, messages, custom data
- Registry contains: worker IDs, tasks, metadata

**Best practices:**
- Don't log sensitive data in events (passwords, tokens, PII)
- Use generic worker IDs (not usernames or emails)
- Sanitize metadata before registration
- Rotate event logs regularly

### File Permissions

All monitoring files are world-readable by default (`/tmp/watchdog/`):

```bash
# Restrict permissions if needed
chmod 700 /tmp/watchdog
chmod 600 /tmp/watchdog/*.json
```

## Comparison with Watchdog System

| Feature | Watchdog | Monitoring System |
|---------|----------|-------------------|
| **Purpose** | Failure detection | Real-time visibility |
| **Trigger** | Timeout-based | Always-on |
| **Output** | Alerts (SMS/email) | HTTP API + events |
| **Frequency** | Every 10s (checks) | Real-time (streaming) |
| **Use case** | "Something is wrong" | "What's happening now?" |

**Use both together:**
- Watchdog: Alerts when workers fail
- Monitoring: Dashboard for Stu to see all workers

## Future Enhancements

Potential improvements:

1. **Authentication** - API keys or OAuth for monitoring server
2. **Database backend** - Store events/registry in SQLite or PostgreSQL
3. **Metrics retention** - Historical metrics storage and querying
4. **Web dashboard** - React/Vue UI for visualization
5. **Alerting rules** - Custom alert rules in monitoring server
6. **Worker logs** - Centralized log aggregation
7. **Distributed tracing** - OpenTelemetry integration
8. **Worker groups** - Organize workers by team/project
9. **Cost tracking** - E2B usage per worker
10. **Auto-scaling** - Spawn workers based on metrics

## License

MIT - Same as parent repository
