#!/usr/bin/env node
/**
 * Real-Time Worker Monitoring Server
 *
 * Provides HTTP API endpoints for real-time worker monitoring and oversight:
 * - GET /health - Overall system health
 * - GET /workers - List all workers with status
 * - GET /workers/:id - Detailed worker metrics
 * - GET /metrics - Prometheus-compatible metrics
 * - GET /events - Real-time event stream (SSE)
 *
 * Environment Variables:
 *   MONITORING_PORT - HTTP server port (default: 9090)
 *   WATCHDOG_DIR - Directory for watchdog files (default: /tmp/watchdog)
 *   MONITORING_REGISTRY - Worker registry file (default: /tmp/watchdog/registry.json)
 */

const http = require('http');
const fs = require('fs');
const path = require('path');
const { EventEmitter } = require('events');

// Configuration
const PORT = process.env.MONITORING_PORT || 9090;
const WATCHDOG_DIR = process.env.WATCHDOG_DIR || '/tmp/watchdog';
const REGISTRY_FILE = process.env.MONITORING_REGISTRY || path.join(WATCHDOG_DIR, 'registry.json');
const EVENTS_FILE = path.join(WATCHDOG_DIR, 'events.jsonl');
const WATCHDOG_TIMEOUT = parseInt(process.env.WATCHDOG_TIMEOUT || '90', 10);

// Event emitter for SSE
const eventEmitter = new EventEmitter();

// Ensure directories exist
fs.mkdirSync(WATCHDOG_DIR, { recursive: true });

/**
 * Read all worker heartbeats
 */
function readWorkers() {
  const workers = [];

  try {
    const files = fs.readdirSync(WATCHDOG_DIR);
    const now = Math.floor(Date.now() / 1000);

    for (const file of files) {
      if (file.startsWith('heartbeat-') && file.endsWith('.json')) {
        try {
          const filepath = path.join(WATCHDOG_DIR, file);
          const data = JSON.parse(fs.readFileSync(filepath, 'utf8'));

          const age = now - (data.timestamp_unix || 0);
          const healthy = age <= WATCHDOG_TIMEOUT;

          workers.push({
            ...data,
            age_seconds: age,
            healthy,
            status_level: healthy ? 'ok' : 'timeout',
          });
        } catch (err) {
          console.error(`Failed to read ${file}:`, err.message);
        }
      }
    }
  } catch (err) {
    console.error('Failed to read workers:', err.message);
  }

  return workers;
}

/**
 * Read worker registry
 */
function readRegistry() {
  try {
    if (fs.existsSync(REGISTRY_FILE)) {
      return JSON.parse(fs.readFileSync(REGISTRY_FILE, 'utf8'));
    }
  } catch (err) {
    console.error('Failed to read registry:', err.message);
  }

  return { workers: {}, updated_at: null };
}

/**
 * Calculate system health summary
 */
function calculateHealth() {
  const workers = readWorkers();
  const registry = readRegistry();

  const total = workers.length;
  const healthy = workers.filter(w => w.healthy).length;
  const timeout = total - healthy;

  const overall = timeout === 0 ? 'healthy' : (healthy > 0 ? 'degraded' : 'critical');

  return {
    status: overall,
    workers: {
      total,
      healthy,
      timeout,
      registered: Object.keys(registry.workers || {}).length,
    },
    timestamp: new Date().toISOString(),
  };
}

/**
 * Generate Prometheus metrics
 */
function generateMetrics() {
  const workers = readWorkers();
  const health = calculateHealth();

  const lines = [
    '# HELP workers_total Total number of active workers',
    '# TYPE workers_total gauge',
    `workers_total ${health.workers.total}`,
    '',
    '# HELP workers_healthy Number of healthy workers',
    '# TYPE workers_healthy gauge',
    `workers_healthy ${health.workers.healthy}`,
    '',
    '# HELP workers_timeout Number of workers in timeout',
    '# TYPE workers_timeout gauge',
    `workers_timeout ${health.workers.timeout}`,
    '',
    '# HELP worker_age_seconds Age of last heartbeat in seconds',
    '# TYPE worker_age_seconds gauge',
  ];

  for (const worker of workers) {
    lines.push(`worker_age_seconds{worker_id="${worker.worker_id}"} ${worker.age_seconds}`);
  }

  lines.push('');
  lines.push('# HELP worker_memory_mb Worker memory usage in MB');
  lines.push('# TYPE worker_memory_mb gauge');

  for (const worker of workers) {
    const memory = worker.metrics?.memory_mb || 0;
    lines.push(`worker_memory_mb{worker_id="${worker.worker_id}"} ${memory}`);
  }

  lines.push('');
  lines.push('# HELP worker_uptime_seconds Worker uptime in seconds');
  lines.push('# TYPE worker_uptime_seconds gauge');

  for (const worker of workers) {
    const uptime = worker.metrics?.uptime_seconds || 0;
    lines.push(`worker_uptime_seconds{worker_id="${worker.worker_id}"} ${uptime}`);
  }

  return lines.join('\n') + '\n';
}

/**
 * Read recent events
 */
function readEvents(limit = 100) {
  try {
    if (!fs.existsSync(EVENTS_FILE)) {
      return [];
    }

    const content = fs.readFileSync(EVENTS_FILE, 'utf8');
    const lines = content.trim().split('\n').filter(Boolean);

    const events = lines
      .slice(-limit)
      .map(line => {
        try {
          return JSON.parse(line);
        } catch {
          return null;
        }
      })
      .filter(Boolean);

    return events.reverse();
  } catch (err) {
    console.error('Failed to read events:', err.message);
    return [];
  }
}

/**
 * HTTP request handler
 */
function handleRequest(req, res) {
  const url = new URL(req.url, `http://${req.headers.host}`);
  const pathname = url.pathname;

  console.log(`${req.method} ${pathname}`);

  // CORS headers
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    res.writeHead(204);
    res.end();
    return;
  }

  // Health endpoint
  if (pathname === '/health') {
    const health = calculateHealth();
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(health, null, 2));
    return;
  }

  // Workers list
  if (pathname === '/workers') {
    const workers = readWorkers();
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(workers, null, 2));
    return;
  }

  // Worker detail
  if (pathname.startsWith('/workers/')) {
    const workerId = pathname.slice(9);
    const workers = readWorkers();
    const worker = workers.find(w => w.worker_id === workerId);

    if (worker) {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify(worker, null, 2));
    } else {
      res.writeHead(404, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'Worker not found' }));
    }
    return;
  }

  // Prometheus metrics
  if (pathname === '/metrics') {
    const metrics = generateMetrics();
    res.writeHead(200, { 'Content-Type': 'text/plain' });
    res.end(metrics);
    return;
  }

  // Events endpoint
  if (pathname === '/events') {
    const limit = parseInt(url.searchParams.get('limit') || '100', 10);
    const events = readEvents(limit);
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(events, null, 2));
    return;
  }

  // Server-Sent Events (SSE) stream
  if (pathname === '/stream') {
    res.writeHead(200, {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache',
      'Connection': 'keep-alive',
    });

    // Send initial connection event
    res.write('data: ' + JSON.stringify({ type: 'connected', timestamp: new Date().toISOString() }) + '\n\n');

    // Send health updates every 5 seconds
    const interval = setInterval(() => {
      const health = calculateHealth();
      res.write('data: ' + JSON.stringify({ type: 'health', data: health }) + '\n\n');
    }, 5000);

    // Handle events
    const eventHandler = (event) => {
      res.write('data: ' + JSON.stringify({ type: 'event', data: event }) + '\n\n');
    };

    eventEmitter.on('event', eventHandler);

    // Cleanup on close
    req.on('close', () => {
      clearInterval(interval);
      eventEmitter.off('event', eventHandler);
    });

    return;
  }

  // Registry endpoint
  if (pathname === '/registry') {
    const registry = readRegistry();
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(registry, null, 2));
    return;
  }

  // Root - API documentation
  if (pathname === '/') {
    const docs = {
      name: 'Worker Monitoring API',
      version: '1.0.0',
      endpoints: {
        'GET /health': 'System health summary',
        'GET /workers': 'List all workers with status',
        'GET /workers/:id': 'Detailed worker metrics',
        'GET /metrics': 'Prometheus-compatible metrics',
        'GET /events?limit=N': 'Recent events (default: 100)',
        'GET /stream': 'Server-Sent Events stream',
        'GET /registry': 'Worker registry',
      },
      documentation: 'See MONITORING.md for full documentation',
    };

    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(docs, null, 2));
    return;
  }

  // 404
  res.writeHead(404, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({ error: 'Not found' }));
}

/**
 * Watch for new events and emit them
 */
function watchEvents() {
  let lastSize = 0;

  setInterval(() => {
    try {
      if (fs.existsSync(EVENTS_FILE)) {
        const stats = fs.statSync(EVENTS_FILE);

        if (stats.size > lastSize) {
          const content = fs.readFileSync(EVENTS_FILE, 'utf8');
          const lines = content.trim().split('\n').filter(Boolean);
          const newLines = lines.slice(-(stats.size - lastSize));

          for (const line of newLines) {
            try {
              const event = JSON.parse(line);
              eventEmitter.emit('event', event);
            } catch {
              // Skip invalid JSON
            }
          }

          lastSize = stats.size;
        }
      }
    } catch (err) {
      console.error('Failed to watch events:', err.message);
    }
  }, 1000);
}

/**
 * Start server
 */
function startServer() {
  const server = http.createServer(handleRequest);

  server.listen(PORT, () => {
    console.log(`Worker Monitoring Server listening on port ${PORT}`);
    console.log(`Health: http://localhost:${PORT}/health`);
    console.log(`Workers: http://localhost:${PORT}/workers`);
    console.log(`Metrics: http://localhost:${PORT}/metrics`);
    console.log(`Events: http://localhost:${PORT}/events`);
    console.log(`Stream: http://localhost:${PORT}/stream`);
  });

  // Watch for events
  watchEvents();

  // Graceful shutdown
  process.on('SIGTERM', () => {
    console.log('Shutting down monitoring server...');
    server.close(() => {
      console.log('Server shut down');
      process.exit(0);
    });
  });
}

// Start server if run directly
if (require.main === module) {
  startServer();
}

module.exports = { startServer, readWorkers, calculateHealth };
