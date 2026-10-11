#!/bin/bash
# ==============================================================================
# 📦 Billket Automated Database Backup Script (PostgreSQL Docker)
# Saves gzipped SQL dumps to local backup directory and manages retention
# ==============================================================================

set -euo pipefail

BACKUP_DIR="${BACKUP_DIR:-/home/ubuntu/backups}"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="${BACKUP_DIR}/billket_db_${TIMESTAMP}.sql.gz"
CONTAINER_NAME="billket-postgres"
DB_USER="billket_user"
DB_NAME="billket_db"
RETENTION_DAYS=14

mkdir -p "$BACKUP_DIR"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting automated database backup..."

# Verify docker container is running
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  echo "❌ Error: Container '${CONTAINER_NAME}' is not running!" >&2
  exit 1
fi

# Run pg_dump through docker and pipe to gzip
docker exec -t "$CONTAINER_NAME" pg_dump -U "$DB_USER" "$DB_NAME" | gzip > "$BACKUP_FILE"

# Verify backup file was created and is non-empty
if [ -s "$BACKUP_FILE" ]; then
  FILE_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
  echo "✅ Backup successfully created: ${BACKUP_FILE} (${FILE_SIZE})"
else
  echo "❌ Error: Backup file is empty or failed to generate!" >&2
  rm -f "$BACKUP_FILE"
  exit 1
fi

# Cleanup old backups older than RETENTION_DAYS
echo "🧹 Pruning backups older than ${RETENTION_DAYS} days..."
find "$BACKUP_DIR" -name "billket_db_*.sql.gz" -type f -mtime +"$RETENTION_DAYS" -exec rm -f {} +

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Backup completed successfully."
