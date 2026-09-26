#!/bin/sh
set -e

echo "=========================================================="
echo "  🚀 Billket Cloud Backend Server (Fastify + Prisma)     "
echo "  Environment: ${NODE_ENV:-production}                   "
echo "  Port:        ${PORT:-4000}                             "
echo "=========================================================="

# Automatically synchronize database schema with PostgreSQL on AWS startup
if [ -n "$DATABASE_URL" ] && [ "$SKIP_DB_PUSH" != "true" ]; then
  echo "[Billket Cloud] Synchronizing database schema with PostgreSQL..."
  npx prisma db push --skip-generate || echo "[Billket Cloud] Notice: Database push finished with warnings, continuing startup..."
fi

echo "[Billket Cloud] Starting server on port ${PORT:-4000}..."
exec node dist/server.js
