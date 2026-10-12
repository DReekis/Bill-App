#!/bin/sh
set -e

# Default to local container postgres if DATABASE_URL is not provided in env
if [ -z "$DATABASE_URL" ]; then
  export DATABASE_URL="postgresql://billket_user:billket_secure_password_2026@postgres:5432/billket_db?schema=public"
fi

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
