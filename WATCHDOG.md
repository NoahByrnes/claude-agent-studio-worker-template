# Worker Watchdog System

Comprehensive monitoring system for detecting stuck, crashed, or unresponsive workers using heartbeat signals and dead man's switch pattern.

## Overview

The watchdog system prevents silent failures by requiring workers to actively signal they're alive and working. If a worker stops sending heartbeats, the watchdog triggers alerts and can optionally auto-restart the worker.

### Key Features

- **Heartbeat monitoring** - Workers send periodic "I'm alive" signals
- **Dead man's switch** - Missing heartbeat triggers immediate alert
- **Multi-tier alerting** - Warning → Critical → Dead (configurable thresholds)
- **Health metrics** - Memory, CPU, uptime tracking in every heartbeat
- **Auto-restart** - Optional automatic worker recovery
- **SMS/Email alerts** - Integrates with Twilio and SendGrid
- **Continuous or cron-based** - Run as daemon or periodic checks
- **Zero configuration** - Works out of the box with sensible defaults

## Quick Start

### 1. Worker sends heartbeats

Workers call `heartbeat.sh` periodically to signal they're working:

```bash
# In your worker script
while true; do
    # Do work...
    heartbeat.sh "Processing job 123"

    # More work...
    heartbeat.sh "Uploading results"

    sleep 10
done
```

### 2. Start watchdog daemon

The watchdog monitors heartbeat files and alerts on timeout:

```bash
# Install watchdog system
watchdog-setup.sh install

# Start monitoring daemon
watchdog-setup.sh start

# Check status
watchdog-setup.sh status
```

### 3. Configure alerts

Set recipients to receive timeout notifications:

```bash
# Email alerts (via SendGrid)
export SENDGRID_API_KEY="your_api_key"
export STATUS_UPDATE_RECIPIENTS="stu@example.com"
export WATCHDOG_ALERT_METHOD="email"

# SMS alerts (via Twilio)
export TWILIO_ACCOUNT_SID="your_sid"
export TWILIO_AUTH_TOKEN="your_token"
export TWILIO_PHONE_NUMBER="+1234567890"
export STATUS_UPDATE_RECIPIENTS="+1234567890"
export WATCHDOG_ALERT_METHOD="sms"

# Both email and SMS
export STATUS_UPDATE_RECIPIENTS="stu@example.com,+1234567890"
export WATCHDOG_ALERT_METHOD="both"
```

## How It Works

### Heartbeat Flow

1. Worker calls `heartbeat.sh "status message"`
2. Script writes JSON file to `/tmp/watchdog/heartbeat-{worker_id}.json`
3. JSON includes timestamp, metrics, and status message
4. Watchdog daemon reads all heartbeat files every 10 seconds
5. If heartbeat age > timeout (default 90s), alert is triggered

### Timeout Thresholds

**Default configuration:**
- Heartbeat interval: 30 seconds (worker sends signal)
- Watchdog timeout: 90 seconds (3 missed heartbeats)
- Check interval: 10 seconds (how often watchdog checks)

**Recommended thresholds:**
- Warning: 1 missed heartbeat (60s) - Worker might be busy
- Critical: 2 missed heartbeats (90s) - Worker likely stuck
- Dead: 3+ missed heartbeats (120s+) - Worker needs intervention

### Dead Man's Switch Pattern

The system uses a "dead man's switch" - the worker must actively prove it's alive. This catches:
- Infinite loops (worker running but stuck)
- Deadlocks (worker waiting forever)
- Out of memory crashes (process killed)
- Network hangs (API calls never return)
- Silent exits (worker dies without error)

## Components

### 1. `heartbeat.sh` - Worker heartbeat sender

Called by workers to signal "I'm alive and working".

**Usage:**
```bash
heartbeat.sh [status_message]
```

**Examples:**
```bash
# Simple heartbeat
heartbeat.sh

# With status message
heartbeat.sh "Processing ferry booking"
heartbeat.sh "Waiting for API response"
heartbeat.sh "Uploading results to S3"

# In a loop
while processing; do
    heartbeat.sh "Processing batch $batch_num"
    process_batch
    sleep 5
done
```

**Output:**
Creates `/tmp/watchdog/heartbeat-{worker_id}.json`:
```json
{
  "worker_id": "worker-hostname-12345",
  "timestamp": "2026-02-22T10:30:00Z",
  "timestamp_unix": 1740222600,
  "status": "Processing ferry booking",
  "metrics": {
    "memory_mb": 256,
    "cpu_time_seconds": 45,
    "uptime_seconds": 3600,
    "pid": 12345
  },
  "healthy": true
}
```

### 2. `watchdog.sh` - Monitoring daemon

Monitors heartbeat files and triggers alerts on timeout.

**Usage:**
```bash
# Start daemon (continuous monitoring)
watchdog.sh

# Single check (for cron)
watchdog.sh --once

# Show status
watchdog.sh --status

# Cleanup old heartbeats
watchdog.sh --cleanup
```

**Daemon mode:**
Runs continuously, checking heartbeats every 10 seconds:
```bash
WATCHDOG_TIMEOUT=120 watchdog.sh
```

**Cron mode:**
Run periodic checks without daemon:
```bash
# Add to crontab (every 5 minutes)
*/5 * * * * /usr/local/bin/watchdog.sh --once
```

**Status output:**
```
Watchdog Status Report
======================

Configuration:
  Timeout: 90s
  Check Interval: 10s
  Alert Method: email

Workers:
  ✓ worker-1 - Healthy (15s ago)
      Status: Processing batch 5
      Memory: 256MB
      Last: 2026-02-22T10:30:00Z

  ⚠️  worker-2 - TIMEOUT (120s ago)
      Status: Waiting for API
      Memory: 512MB
      Last: 2026-02-22T10:28:00Z

Summary: 1 healthy, 1 timeout, 2 total
```

### 3. `watchdog-alert.sh` - Alert dispatcher

Sends SMS/email alerts when workers timeout.

**Usage:**
```bash
watchdog-alert.sh --method email --message "Alert text"
watchdog-alert.sh --method sms --message "Alert text"
```

**Alert message format:**
```
🚨 WATCHDOG ALERT: Worker Timeout

Worker ID: worker-hostname-12345
Last Heartbeat: 2026-02-22T10:28:00Z
Age: 120s (timeout: 90s)
Status: Waiting for API response

Metrics:
  Memory: 512MB
  Uptime: 1h 30m

The worker has missed its heartbeat deadline.
This may indicate the worker is stuck, crashed, or overloaded.

Action required: Check worker logs and consider manual intervention.
```

### 4. `watchdog-setup.sh` - Setup and management

Install, configure, and manage the watchdog system.

**Usage:**
```bash
# Install
watchdog-setup.sh install

# Start/stop daemon
watchdog-setup.sh start
watchdog-setup.sh stop
watchdog-setup.sh restart

# Status
watchdog-setup.sh status

# Enable/disable cron checks
watchdog-setup.sh enable-cron
watchdog-setup.sh disable-cron
```

## Configuration

### Environment Variables

**Watchdog settings:**
```bash
# Timeout before alert (seconds)
WATCHDOG_TIMEOUT=90  # Default: 90s (3 missed heartbeats)

# Check interval (seconds)
WATCHDOG_CHECK_INTERVAL=10  # Default: 10s

# Alert method: email, sms, both, none
WATCHDOG_ALERT_METHOD=email  # Default: email

# Auto-restart dead workers
WATCHDOG_AUTO_RESTART=false  # Default: false (alert only)

# Cron schedule for periodic checks
WATCHDOG_CRON_SCHEDULE="*/5 * * * *"  # Default: every 5 minutes

# Verbose logging
WATCHDOG_VERBOSE=false  # Default: false
```

**Worker settings:**
```bash
# Worker identifier (auto-generated if not set)
WORKER_ID="worker-ferry-1"

# Watchdog directory
WATCHDOG_DIR=/tmp/watchdog  # Default

# Heartbeat verbose mode
HEARTBEAT_VERBOSE=true  # Show heartbeat logs
```

**Alert settings:**
```bash
# Recipients (required for alerts)
STATUS_UPDATE_RECIPIENTS="stu@example.com,+1234567890"

# Email configuration (SendGrid)
SENDGRID_API_KEY="your_api_key"
STATUS_UPDATE_FROM_EMAIL="watchdog@conductor.local"

# SMS configuration (Twilio)
TWILIO_ACCOUNT_SID="your_account_sid"
TWILIO_AUTH_TOKEN="your_auth_token"
TWILIO_PHONE_NUMBER="+1234567890"
```

## Use Cases

### 1. Long-running ferry monitoring

Monitor a worker polling BC Ferries API for availability:

```bash
#!/bin/bash
export WORKER_ID="ferry-monitor-tsawwassen-swartz"
export WATCHDOG_TIMEOUT=120  # 2 minutes

# Start watchdog
watchdog-setup.sh start

# Worker loop
while true; do
    heartbeat.sh "Checking ferry availability"

    # Poll API (may take time)
    if wait-for-ferry --from tsawwassen --to swartz_bay --timeout 30; then
        heartbeat.sh "Ferry available - starting booking"
        bc-ferries-book
        break
    fi

    heartbeat.sh "Ferry not available - continuing to poll"
    sleep 10
done

heartbeat.sh "Booking complete"
```

**Benefits:**
- Detects if API polling hangs
- Alerts if worker crashes during booking
- Tracks memory usage during long-running tasks

### 2. Conductor monitoring workers

Stu monitors multiple spawned workers:

```bash
# In conductor (Stu)
watchdog-setup.sh install
watchdog-setup.sh start

# Spawn workers
for task in task1 task2 task3; do
    WORKER_ID="worker-$task" spawn_worker.sh &
done

# Workers send heartbeats
# Conductor's watchdog monitors all workers
# Alerts if any worker stops responding
```

### 3. Scheduled background tasks

Cron job with watchdog protection:

```bash
# In crontab
0 */6 * * * /home/user/scheduled-task.sh

# In scheduled-task.sh
export WORKER_ID="scheduled-backup-$(date +%s)"

heartbeat.sh "Starting scheduled backup"

# Backup process
for file in *.data; do
    heartbeat.sh "Backing up $file"
    aws s3 cp "$file" s3://backups/
done

heartbeat.sh "Backup complete"
```

**Separate watchdog check:**
```bash
# In crontab (every 5 minutes)
*/5 * * * * /usr/local/bin/watchdog.sh --once
```

### 4. Auto-restart stuck workers

Enable automatic recovery:

```bash
export WATCHDOG_AUTO_RESTART=true
export WATCHDOG_TIMEOUT=60  # Restart after 1 minute

watchdog-setup.sh start

# Worker process
while true; do
    heartbeat.sh "Processing"

    # If this hangs, watchdog will kill and restart
    process_data

    sleep 5
done
```

**Warning:** Auto-restart requires proper process supervision (systemd, supervisor, etc.) to respawn killed workers.

## Integration with Existing Systems

### Status Updates

The watchdog system complements the existing status update system:

- **Status updates** (`status-update.sh`): Proactive periodic reports
- **Watchdog** (`watchdog.sh`): Reactive failure detection

Both use the same alert infrastructure (Twilio/SendGrid).

### Persistent Storage

Workers should persist results before crashes:

```bash
while processing; do
    heartbeat.sh "Processing batch $batch"

    result=$(process_batch)

    # Persist result immediately
    persist-result "$result" --name "batch-$batch"

    heartbeat.sh "Batch $batch complete"
done
```

### BC Ferries Tools

Integration with ferry monitoring daemon:

```bash
# In bc-ferries-watch-and-book
export WORKER_ID="ferry-watcher-$(date +%s)"

heartbeat.sh "Starting ferry monitoring"

while monitoring; do
    heartbeat.sh "Polling BC Ferries API"

    if check_availability; then
        heartbeat.sh "Availability found - booking"
        book_ferry
        break
    fi

    sleep 10
done

heartbeat.sh "Monitoring complete"
```

## Monitoring Best Practices

### 1. Heartbeat frequency

**Rule of thumb:** Send heartbeat at 1/3 of timeout interval

- Timeout: 90s → Heartbeat every 30s
- Timeout: 120s → Heartbeat every 40s
- Timeout: 60s → Heartbeat every 20s

### 2. Status messages

Be specific about what the worker is doing:

**Good:**
```bash
heartbeat.sh "Polling BC Ferries API (attempt 15)"
heartbeat.sh "Uploading 2.5MB result to S3"
heartbeat.sh "Waiting for Playwright page load"
```

**Bad:**
```bash
heartbeat.sh "Working"
heartbeat.sh "Processing"
heartbeat.sh "Running"
```

### 3. Critical sections

Send heartbeat before and after risky operations:

```bash
heartbeat.sh "Starting database transaction"
run_database_transaction
heartbeat.sh "Database transaction complete"

heartbeat.sh "Starting browser automation"
playwright_script
heartbeat.sh "Browser automation complete"
```

### 4. Timeout tuning

**Conservative (production):**
- Timeout: 180s (3 minutes)
- Fewer false positives
- Slower failure detection

**Aggressive (development):**
- Timeout: 30s (30 seconds)
- Faster failure detection
- More false positives on slow operations

**Balanced (recommended):**
- Timeout: 90s (90 seconds)
- 3 missed heartbeats (30s interval)
- Good balance of speed and reliability

### 5. Alert fatigue prevention

Don't alert for transient issues:

```bash
# Use higher timeout for slow operations
WATCHDOG_TIMEOUT=300 heartbeat.sh "Large file upload"
upload_large_file

# Reset to normal timeout
WATCHDOG_TIMEOUT=90 heartbeat.sh "Upload complete"
```

Or temporarily disable alerting:

```bash
# Disable alerts during maintenance
export WATCHDOG_ALERT_METHOD=none
maintenance_task

# Re-enable alerts
export WATCHDOG_ALERT_METHOD=email
```

## Troubleshooting

### Worker not detected

**Symptom:** Watchdog doesn't see worker heartbeats

**Check:**
```bash
# List heartbeat files
ls -la /tmp/watchdog/

# Check heartbeat content
cat /tmp/watchdog/heartbeat-*.json | jq

# Verify worker is sending heartbeats
HEARTBEAT_VERBOSE=true heartbeat.sh "test"
```

### False positives

**Symptom:** Alerts for healthy workers

**Solutions:**
- Increase timeout: `WATCHDOG_TIMEOUT=180`
- Increase heartbeat frequency in worker
- Check for slow operations blocking heartbeat

### Watchdog not running

**Symptom:** No monitoring happening

**Check:**
```bash
# Check daemon status
watchdog-setup.sh status

# Check PID file
cat /tmp/watchdog.pid
ps -p $(cat /tmp/watchdog.pid)

# Check logs
tail -f /var/log/watchdog/watchdog.log

# Restart daemon
watchdog-setup.sh restart
```

### Alerts not sending

**Symptom:** Timeout detected but no alert received

**Check:**
```bash
# Verify recipients configured
echo $STATUS_UPDATE_RECIPIENTS

# Check credentials
echo $SENDGRID_API_KEY  # For email
echo $TWILIO_ACCOUNT_SID  # For SMS

# Test alert manually
watchdog-alert.sh --method email --message "Test alert"

# Check alert logs
tail -f /var/log/watchdog/alert.log
```

### Stale heartbeat files

**Symptom:** Old heartbeat files not cleaned up

**Solution:**
```bash
# Manual cleanup
watchdog.sh --cleanup

# Or delete old files
find /tmp/watchdog -name "heartbeat-*.json" -mtime +1 -delete
```

## Architecture

### File Structure

```
/tmp/watchdog/
  heartbeat-worker-1.json      # Worker 1 heartbeat
  heartbeat-worker-2.json      # Worker 2 heartbeat
  ...

/var/log/watchdog/
  watchdog.log                 # Daemon log
  alert.log                    # Alert dispatch log
  setup.log                    # Setup script log
  cron.log                     # Cron check log

/tmp/
  watchdog.pid                 # Daemon PID file
```

### Process Model

```
┌─────────────────┐
│  Worker 1       │──┐
│  heartbeat.sh   │  │
└─────────────────┘  │
                     ├──> /tmp/watchdog/heartbeat-*.json
┌─────────────────┐  │
│  Worker 2       │──┤
│  heartbeat.sh   │  │
└─────────────────┘  │
                     │
┌─────────────────┐  │
│  Worker 3       │──┘
│  heartbeat.sh   │
└─────────────────┘

         │
         ▼
┌─────────────────────────────┐
│  Watchdog Daemon            │
│  watchdog.sh                │
│  - Reads heartbeat files    │
│  - Checks timestamps        │
│  - Triggers alerts          │
└─────────────────────────────┘
         │
         ▼
┌─────────────────────────────┐
│  Alert System               │
│  watchdog-alert.sh          │
│  - Sends SMS (Twilio)       │
│  - Sends Email (SendGrid)   │
└─────────────────────────────┘
```

## Comparison with Status Updates

| Feature | Status Updates | Watchdog |
|---------|---------------|----------|
| **Purpose** | Proactive reporting | Reactive failure detection |
| **Trigger** | Time-based (cron) | Event-based (timeout) |
| **Frequency** | Low (hourly/daily) | High (seconds) |
| **Content** | System health summary | Worker-specific alerts |
| **Alert severity** | Informational | Critical |
| **Use case** | "Everything is fine" | "Something is wrong" |

**Use both together:**
- Status updates: Regular check-ins ("Conductor still running")
- Watchdog: Immediate alerts ("Worker 5 stopped responding")

## Security Considerations

### Heartbeat files

- Stored in `/tmp/watchdog` (ephemeral)
- World-readable by default (no sensitive data)
- Automatically cleaned up on reboot

### Alert credentials

**Never log or expose:**
- `SENDGRID_API_KEY`
- `TWILIO_AUTH_TOKEN`
- `TWILIO_ACCOUNT_SID`

**Best practices:**
- Pass via environment variables (encrypted in E2B)
- Never commit to version control
- Rotate credentials regularly

### Auto-restart risks

**Warning:** `WATCHDOG_AUTO_RESTART=true` kills worker processes

**Risks:**
- Data loss if worker has uncommitted state
- Infinite restart loops if worker is fundamentally broken
- Resource exhaustion from rapid restarts

**Mitigations:**
- Use persistent storage (`persist-result`) frequently
- Implement exponential backoff in restart logic
- Monitor restart count and disable after N failures
- Only enable for stateless workers

## Performance Impact

**Heartbeat overhead:**
- File write: ~1ms
- Memory: ~1KB per heartbeat file
- CPU: Negligible

**Watchdog overhead:**
- Daemon memory: ~5-10MB
- CPU: <1% (mostly sleeping)
- Disk I/O: Minimal (reads only)

**Recommended:**
- ✅ Use on production workers
- ✅ Enable for long-running tasks
- ✅ Run as daemon for continuous monitoring
- ✅ Use cron for backup checks

## Future Enhancements

Potential improvements to consider:

1. **Metrics dashboard** - Web UI showing worker health
2. **Historical tracking** - Store heartbeat history in database
3. **Predictive alerts** - ML-based anomaly detection
4. **Worker groups** - Monitor groups of workers together
5. **Escalation policies** - Multi-tier alert escalation
6. **Integration with APM** - Export metrics to DataDog/New Relic
7. **Slack/Discord alerts** - Additional notification channels
8. **Health scoring** - Composite health score from multiple metrics

## License

MIT - Same as parent repository
