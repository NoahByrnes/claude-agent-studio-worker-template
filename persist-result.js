#!/usr/bin/env node
/**
 * Persistent Storage Helper for Worker Results (Node.js)
 * Ensures work isn't lost when workers terminate
 */

const fs = require('fs');
const path = require('path');
const { exec } = require('child_process');
const { promisify } = require('util');

const execAsync = promisify(exec);

// Configuration from environment
const config = {
  s3Bucket: process.env.WORKER_RESULTS_S3_BUCKET || '',
  s3Prefix: process.env.WORKER_RESULTS_S3_PREFIX || 'results',
  storageEndpoint: process.env.WORKER_RESULTS_ENDPOINT || '',
  localDir: process.env.WORKER_RESULTS_LOCAL_DIR || '/workspace/.results',
  taskId: process.env.WORKER_ID || `worker-${Date.now()}`,
};

/**
 * Persist a result to storage
 * @param {string|Buffer} data - File path, directory path, or Buffer/string content
 * @param {Object} options - Storage options
 * @param {string} options.name - Custom name for stored result
 * @param {Object} options.metadata - JSON metadata to attach
 * @param {string} options.taskId - Task/worker ID for organization
 * @param {string} options.contentType - MIME type for content
 * @returns {Promise<Object>} Storage result with locations
 */
async function persistResult(data, options = {}) {
  const {
    name = typeof data === 'string' ? path.basename(data) : 'result.txt',
    metadata = {},
    taskId = config.taskId,
    contentType = 'application/octet-stream',
  } = options;

  const timestamp = new Date().toISOString().replace(/[:.]/g, '-').slice(0, -5);
  const storageKey = `${taskId}/${timestamp}-${name}`;

  console.log(`📦 Persisting result: ${name}`);
  console.log(`   Storage key: ${storageKey}`);

  const results = {
    success: false,
    locations: [],
    errors: [],
  };

  // Prepare file for upload
  let uploadPath = null;
  let tempFile = false;

  if (typeof data === 'string') {
    if (fs.existsSync(data)) {
      uploadPath = data;
    } else {
      // Treat as content string
      uploadPath = `/tmp/${name}`;
      fs.writeFileSync(uploadPath, data);
      tempFile = true;
    }
  } else if (Buffer.isBuffer(data)) {
    uploadPath = `/tmp/${name}`;
    fs.writeFileSync(uploadPath, data);
    tempFile = true;
  } else {
    throw new Error('Data must be a file path, string content, or Buffer');
  }

  // Try S3 storage
  if (config.s3Bucket) {
    try {
      console.log('   Attempting S3 storage...');
      const s3Key = `${config.s3Prefix}/${storageKey}`;
      const metadataStr = JSON.stringify(metadata).replace(/"/g, '\\"');

      await execAsync(
        `aws s3 cp "${uploadPath}" "s3://${config.s3Bucket}/${s3Key}" --metadata "task-id=${taskId},metadata=${metadataStr}"`
      );

      const location = `s3://${config.s3Bucket}/${s3Key}`;
      console.log(`   ✅ Stored to S3: ${location}`);
      results.success = true;
      results.locations.push({ type: 's3', location, key: s3Key });
    } catch (error) {
      console.log('   ⚠️  S3 storage failed:', error.message);
      results.errors.push({ type: 's3', error: error.message });
    }
  }

  // Try HTTP POST storage
  if (config.storageEndpoint) {
    try {
      console.log('   Attempting HTTP storage...');

      const FormData = require('form-data');
      const fetch = require('node-fetch');

      const form = new FormData();
      form.append('file', fs.createReadStream(uploadPath));
      form.append('key', storageKey);
      form.append('task_id', taskId);
      form.append('metadata', JSON.stringify(metadata));

      const response = await fetch(config.storageEndpoint, {
        method: 'POST',
        body: form,
      });

      if (response.ok) {
        const responseData = await response.json().catch(() => ({}));
        console.log(`   ✅ Stored via HTTP: ${config.storageEndpoint}`);
        results.success = true;
        results.locations.push({
          type: 'http',
          location: config.storageEndpoint,
          response: responseData,
        });
      } else {
        throw new Error(`HTTP ${response.status}: ${response.statusText}`);
      }
    } catch (error) {
      console.log('   ⚠️  HTTP storage failed:', error.message);
      results.errors.push({ type: 'http', error: error.message });
    }
  }

  // Local persistence (always attempted)
  try {
    console.log('   Attempting local persistence...');

    const localPath = path.join(config.localDir, storageKey);
    const localDir = path.dirname(localPath);

    fs.mkdirSync(localDir, { recursive: true });
    fs.copyFileSync(uploadPath, localPath);

    // Write metadata
    const metaFile = `${localPath}.meta.json`;
    fs.writeFileSync(
      metaFile,
      JSON.stringify({
        task_id: taskId,
        timestamp,
        name,
        metadata,
        contentType,
      })
    );

    console.log(`   ✅ Stored locally: ${localPath}`);
    results.success = true;
    results.locations.push({ type: 'local', location: localPath });
  } catch (error) {
    console.log('   ⚠️  Local persistence failed:', error.message);
    results.errors.push({ type: 'local', error: error.message });
  }

  // Cleanup temp file
  if (tempFile && uploadPath) {
    fs.unlinkSync(uploadPath);
  }

  if (results.success) {
    console.log('✅ Result persisted successfully!');
  } else {
    console.log('❌ All storage methods failed!');
    throw new Error('All storage methods failed');
  }

  return results;
}

/**
 * List persisted results for a task
 * @param {string} taskId - Task ID to list results for
 * @returns {Promise<Array>} List of results with metadata
 */
async function listResults(taskId = config.taskId) {
  const taskDir = path.join(config.localDir, taskId);

  if (!fs.existsSync(taskDir)) {
    return [];
  }

  const results = [];
  const files = fs.readdirSync(taskDir, { recursive: true });

  for (const file of files) {
    if (file.endsWith('.meta.json')) {
      const metaPath = path.join(taskDir, file);
      const resultPath = metaPath.replace('.meta.json', '');

      if (fs.existsSync(resultPath)) {
        const metadata = JSON.parse(fs.readFileSync(metaPath, 'utf8'));
        results.push({
          path: resultPath,
          ...metadata,
        });
      }
    }
  }

  return results.sort((a, b) => b.timestamp.localeCompare(a.timestamp));
}

/**
 * Retrieve a persisted result
 * @param {string} storageKey - Storage key from persistResult
 * @returns {Promise<Buffer>} Result content
 */
async function retrieveResult(storageKey) {
  const localPath = path.join(config.localDir, storageKey);

  if (fs.existsSync(localPath)) {
    return fs.readFileSync(localPath);
  }

  // Try S3 if configured
  if (config.s3Bucket) {
    const s3Key = `${config.s3Prefix}/${storageKey}`;
    const tempPath = `/tmp/${path.basename(storageKey)}`;

    try {
      await execAsync(`aws s3 cp "s3://${config.s3Bucket}/${s3Key}" "${tempPath}"`);
      const content = fs.readFileSync(tempPath);
      fs.unlinkSync(tempPath);
      return content;
    } catch (error) {
      // Fall through
    }
  }

  throw new Error(`Result not found: ${storageKey}`);
}

// CLI support
if (require.main === module) {
  const args = process.argv.slice(2);

  if (args.length === 0 || args.includes('--help') || args.includes('-h')) {
    console.log(`
Persistent Storage Helper for Worker Results (Node.js)

Usage:
  node persist-result.js [OPTIONS] FILE_OR_CONTENT

Options:
  -n, --name NAME       Custom name for stored result
  -m, --metadata JSON   JSON metadata to attach
  -t, --task-id ID      Task/worker ID for organization
  --list [TASK_ID]      List persisted results
  --retrieve KEY        Retrieve a persisted result
  -h, --help            Show this help

Examples:
  node persist-result.js output.json
  node persist-result.js -n "final-report" -m '{"status":"complete"}' report.pdf
  node persist-result.js --list worker-123
  node persist-result.js --retrieve worker-123/20260114-120000-output.json
    `);
    process.exit(0);
  }

  // Parse options
  const options = {};
  let inputData = null;

  for (let i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '-n':
      case '--name':
        options.name = args[++i];
        break;
      case '-m':
      case '--metadata':
        options.metadata = JSON.parse(args[++i]);
        break;
      case '-t':
      case '--task-id':
        options.taskId = args[++i];
        break;
      case '--list':
        listResults(args[i + 1])
          .then((results) => {
            console.log(JSON.stringify(results, null, 2));
            process.exit(0);
          })
          .catch((error) => {
            console.error('Error listing results:', error.message);
            process.exit(1);
          });
        return;
      case '--retrieve':
        retrieveResult(args[++i])
          .then((content) => {
            process.stdout.write(content);
            process.exit(0);
          })
          .catch((error) => {
            console.error('Error retrieving result:', error.message);
            process.exit(1);
          });
        return;
      default:
        if (!inputData) {
          inputData = args[i];
        }
        break;
    }
  }

  if (!inputData) {
    console.error('Error: FILE_OR_CONTENT required');
    process.exit(1);
  }

  persistResult(inputData, options)
    .then(() => process.exit(0))
    .catch((error) => {
      console.error('Error:', error.message);
      process.exit(1);
    });
}

module.exports = { persistResult, listResults, retrieveResult };
