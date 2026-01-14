#!/bin/bash
# Persistent Storage Helper for Worker Results
# Ensures work isn't lost when workers terminate

set -e

# Configuration from environment variables
S3_BUCKET="${WORKER_RESULTS_S3_BUCKET:-}"
S3_PREFIX="${WORKER_RESULTS_S3_PREFIX:-results}"
STORAGE_ENDPOINT="${WORKER_RESULTS_ENDPOINT:-}"
LOCAL_PERSIST_DIR="${WORKER_RESULTS_LOCAL_DIR:-/workspace/.results}"

# Usage information
usage() {
    echo "Usage: persist-result.sh [OPTIONS] FILE_OR_DIR"
    echo ""
    echo "Persist worker results to storage backends with automatic fallback."
    echo ""
    echo "Arguments:"
    echo "  FILE_OR_DIR          File or directory to persist"
    echo ""
    echo "Options:"
    echo "  -n, --name NAME      Custom name for stored result (default: filename)"
    echo "  -m, --metadata JSON  JSON metadata to attach (default: {})"
    echo "  -t, --task-id ID     Task/worker ID for organization"
    echo "  -h, --help           Show this help"
    echo ""
    echo "Environment Variables:"
    echo "  WORKER_RESULTS_S3_BUCKET      S3 bucket name (enables S3 storage)"
    echo "  WORKER_RESULTS_S3_PREFIX      S3 key prefix (default: 'results')"
    echo "  AWS_ACCESS_KEY_ID             AWS credentials"
    echo "  AWS_SECRET_ACCESS_KEY         AWS credentials"
    echo "  AWS_DEFAULT_REGION            AWS region (default: us-east-1)"
    echo "  WORKER_RESULTS_ENDPOINT       HTTP endpoint for POST (enables HTTP storage)"
    echo "  WORKER_RESULTS_LOCAL_DIR      Local persistence directory (default: /workspace/.results)"
    echo ""
    echo "Storage Priority:"
    echo "  1. S3 (if configured)"
    echo "  2. HTTP POST (if configured)"
    echo "  3. Local persistence (always available)"
    echo ""
    exit 0
}

# Parse arguments
NAME=""
METADATA="{}"
TASK_ID="${WORKER_ID:-worker-$(date +%s)}"

while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--name)
            NAME="$2"
            shift 2
            ;;
        -m|--metadata)
            METADATA="$2"
            shift 2
            ;;
        -t|--task-id)
            TASK_ID="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            if [[ -z "$INPUT_PATH" ]]; then
                INPUT_PATH="$1"
            else
                echo "Error: Multiple input paths not supported"
                exit 1
            fi
            shift
            ;;
    esac
done

# Validate input
if [[ -z "$INPUT_PATH" ]]; then
    echo "Error: FILE_OR_DIR required"
    usage
fi

if [[ ! -e "$INPUT_PATH" ]]; then
    echo "Error: Path does not exist: $INPUT_PATH"
    exit 1
fi

# Determine name
if [[ -z "$NAME" ]]; then
    NAME=$(basename "$INPUT_PATH")
fi

# Generate unique storage key
TIMESTAMP=$(date -u +"%Y%m%d-%H%M%S")
STORAGE_KEY="${TASK_ID}/${TIMESTAMP}-${NAME}"

echo "📦 Persisting result: $INPUT_PATH"
echo "   Storage key: $STORAGE_KEY"

# Create archive if directory
TEMP_ARCHIVE=""
if [[ -d "$INPUT_PATH" ]]; then
    echo "   Archiving directory..."
    TEMP_ARCHIVE="/tmp/${NAME}.tar.gz"
    tar -czf "$TEMP_ARCHIVE" -C "$(dirname "$INPUT_PATH")" "$(basename "$INPUT_PATH")"
    UPLOAD_FILE="$TEMP_ARCHIVE"
    STORAGE_KEY="${STORAGE_KEY}.tar.gz"
else
    UPLOAD_FILE="$INPUT_PATH"
fi

# Track success
SUCCESS=false

# Try S3 storage
if [[ -n "$S3_BUCKET" ]]; then
    echo "   Attempting S3 storage..."
    S3_KEY="${S3_PREFIX}/${STORAGE_KEY}"

    if aws s3 cp "$UPLOAD_FILE" "s3://${S3_BUCKET}/${S3_KEY}" --metadata "task-id=${TASK_ID},metadata=${METADATA}" 2>/dev/null; then
        echo "   ✅ Stored to S3: s3://${S3_BUCKET}/${S3_KEY}"
        SUCCESS=true
    else
        echo "   ⚠️  S3 storage failed"
    fi
fi

# Try HTTP POST storage
if [[ -n "$STORAGE_ENDPOINT" ]] && [[ "$SUCCESS" != true ]]; then
    echo "   Attempting HTTP storage..."

    RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$STORAGE_ENDPOINT" \
        -F "file=@${UPLOAD_FILE}" \
        -F "key=${STORAGE_KEY}" \
        -F "task_id=${TASK_ID}" \
        -F "metadata=${METADATA}" \
        2>/dev/null || echo "000")

    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)

    if [[ "$HTTP_CODE" =~ ^2[0-9]{2}$ ]]; then
        echo "   ✅ Stored via HTTP: $STORAGE_ENDPOINT"
        SUCCESS=true
    else
        echo "   ⚠️  HTTP storage failed (status: $HTTP_CODE)"
    fi
fi

# Local persistence (always attempted as backup)
echo "   Attempting local persistence..."
mkdir -p "$LOCAL_PERSIST_DIR/${TASK_ID}"

LOCAL_PATH="$LOCAL_PERSIST_DIR/${STORAGE_KEY}"
LOCAL_DIR=$(dirname "$LOCAL_PATH")
mkdir -p "$LOCAL_DIR"

if cp "$UPLOAD_FILE" "$LOCAL_PATH" 2>/dev/null; then
    echo "   ✅ Stored locally: $LOCAL_PATH"

    # Write metadata
    META_FILE="${LOCAL_PATH}.meta.json"
    echo "{\"task_id\":\"${TASK_ID}\",\"timestamp\":\"${TIMESTAMP}\",\"name\":\"${NAME}\",\"metadata\":${METADATA}}" > "$META_FILE"

    SUCCESS=true
else
    echo "   ⚠️  Local persistence failed"
fi

# Cleanup temp archive
if [[ -n "$TEMP_ARCHIVE" ]]; then
    rm -f "$TEMP_ARCHIVE"
fi

# Final status
if [[ "$SUCCESS" == true ]]; then
    echo "✅ Result persisted successfully!"
    exit 0
else
    echo "❌ All storage methods failed!"
    exit 1
fi
