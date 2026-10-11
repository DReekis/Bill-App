#!/bin/bash
# ==============================================================================
# 🔄 Billket Database Restore Script (PostgreSQL Docker)
# Restores a gzipped or plain SQL dump into the running PostgreSQL container
# Usage: ./restore-db.sh <path_to_backup_file> [--force]
# ==============================================================================

set -euo pipefail

BACKUP_FILE="${1:-}"
FORCE_FLAG="${2:-}"
CONTAINER_NAME="billket-postgres"
DB_USER="billket_user"
DB_NAME="billket_db"

if [ -z "$BACKUP_FILE" ]; then
  echo "❌ Error: Please specify the backup file to restore."
  echo "Usage: $0 /path/to/billket_db_YYYYMMDD_HHMMSS.sql.gz"
  exit 1
fi

if [ ! -f "$BACKUP_FILE" ]; then
  echo "❌ Error: File not found: ${BACKUP_FILE}"
  exit 1
fi

# Verify docker container is running
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  echo "❌ Error: Container '${CONTAINER_NAME}' is not running!" >&2
  exit 1
fi

echo "⚠️  WARNING: Restoring will overwrite existing data in '${DB_NAME}'!"
echo "Target backup: ${BACKUP_FILE}"

if [ "$FORCE_FLAG" != "--force" ]; then
  read -p "Are you sure you want to proceed? (yes/no): " CONFIRM
  if [ "$CONFIRM" != "yes" ]; then
    echo "Restore cancelled."
    exit 0
  fi
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting database restoration..."

if [[ "$BACKUP_FILE" == *.gz ]]; then
  gunzip -c "$BACKUP_FILE" | docker exec -i "$CONTAINER_NAME" psql -U "$DB_USER" -d "$DB_NAME"
else
  cat "$BACKUP_FILE" | docker exec -i "$CONTAINER_NAME" psql -U "$DB_USER" -d "$DB_NAME"
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✅ Database restoration completed successfully!"
