# ==============================================================================
# Multi-Stage Production Dockerfile for Billket Cloud Backend (Fastify + Prisma)
# Target Architecture: x86_64 and ARM64 (AWS Graviton t4g / App Runner)
# Optimized for minimal image size (<120 MB), fast startup, and non-root security.
# ==============================================================================

# ------------------------------------------------------------------------------
# Stage 1: Build & Dependencies
# ------------------------------------------------------------------------------
FROM node:20-alpine AS builder

WORKDIR /app

# Install openssl and libc compatibility for Prisma engine compilation
RUN apk add --no-cache openssl libc6-compat

# Copy dependency manifests
COPY package.json package-lock.json ./

# Install all dependencies (including devDependencies for TypeScript build)
RUN npm ci

# Copy configuration, source code, and assets
COPY tsconfig.json ./
COPY src/ ./src/
COPY prisma/ ./prisma/
COPY scripts/ ./scripts/
COPY public/ ./public/

# Configure Prisma for production PostgreSQL and generate Prisma client
RUN node scripts/prepare-db.js postgresql
RUN npx prisma generate

# Compile TypeScript to JavaScript
RUN npm run build

# ------------------------------------------------------------------------------
# Stage 2: Production Runtime
# ------------------------------------------------------------------------------
FROM node:20-alpine AS runner

WORKDIR /app

# Install openssl and dumb-init for reliable PID 1 process management
RUN apk add --no-cache openssl dumb-init

# Set production environment variables
ENV NODE_ENV=production
ENV PORT=4000

# Copy package manifests and install production-only dependencies
COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force

# Copy compiled JavaScript and assets from builder
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/node_modules/.prisma ./node_modules/.prisma
COPY --from=builder /app/node_modules/@prisma ./node_modules/@prisma
COPY --from=builder /app/prisma ./prisma
COPY --from=builder /app/public ./public
COPY --from=builder /app/scripts ./scripts

# Copy entrypoint script and grant execution permissions
COPY docker-entrypoint.sh ./
RUN chmod +x docker-entrypoint.sh

# Use non-root node user for container security
USER node

# Expose HTTP port
EXPOSE 4000

# Container healthcheck
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:4000/health || exit 1

# Start container via dumb-init
ENTRYPOINT ["dumb-init", "--", "./docker-entrypoint.sh"]
