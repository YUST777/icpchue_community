#!/bin/bash

# Configuration
# Source the environment variables
# Find project root relative to script
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$PROJECT_ROOT/express-backend/.env"
if [ -f "$ENV_FILE" ]; then
    export $(grep -v '^#' "$ENV_FILE" | xargs)
else
    echo "Error: .env file not found at $ENV_FILE"
    exit 1
fi

# Check required variables
if [ -z "$DATABASE_URL" ] || [ -z "$TELEGRAM_BOT_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ]; then
    echo "Error: Missing required environment variables (DATABASE_URL, TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID)"
    exit 1
fi

# Variables
BACKUP_DIR="$PROJECT_ROOT/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
FILENAME="backup_$TIMESTAMP.sql.gz"
FILEPATH="$BACKUP_DIR/$FILENAME"

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

# 1. Create Dump (using Docker to avoid installing pg_dump on host)
echo "Creating backup..."
# We use 'postgres:alpine' image to run pg_dump. 
# --no-owner --no-acl are often safer for restores across different environments/owners.
docker run --rm -e PGPASSWORD="$DATABASE_PASSWORD" postgres:17-alpine \
    pg_dump "$DATABASE_URL" --format=custom --no-owner --no-acl | gzip > "$FILEPATH"

if [ ! -s "$FILEPATH" ]; then
    echo "Error: Backup file is empty. Check database connection."
    rm -f "$FILEPATH"
    exit 1
fi

FILE_SIZE=$(du -h "$FILEPATH" | cut -f1)
echo "Backup created: $FILENAME ($FILE_SIZE)"

# 2. Compute Application Scale (Optional context for the message)
# (Skipped for simplicity, just sending file)

# 3. Send to Telegram
echo "Sending to Telegram..."
CAPTION="📦 *Database Backup*%0A📅 Date: $(date)%0A💾 Size: $FILE_SIZE"

RESPONSE=$(curl -s -F document=@"$FILEPATH" \
     -F chat_id="$TELEGRAM_CHAT_ID" \
     -F caption="$CAPTION" \
     -F parse_mode="Markdown" \
     "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendDocument")

echo "Telegram Response: $RESPONSE"

if echo "$RESPONSE" | grep -q '"ok":true'; then
    echo "Backup sent successfully!"
else
    echo "Error sending to Telegram: $RESPONSE"
fi

# Cleanup: Delete files older than 7 days
find "$BACKUP_DIR" -name "backup_*.sql.gz" -mtime +7 -delete
