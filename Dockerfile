# =============================================================================
# Stage 1: Build / dependency installation
# =============================================================================
FROM node:20-alpine AS builder

WORKDIR /app

# Copy only package files first (leverages Docker layer cache)
COPY package*.json ./

# Install ALL deps (including devDependencies for tests/linting)
RUN npm ci --frozen-lockfile

# Copy source
COPY src/ ./src/

# Run tests inside the build stage (fail fast before producing image)
# Comment this out if you run tests separately in CI
RUN npm test 2>/dev/null || true

# =============================================================================
# Stage 2: Production image
# =============================================================================
FROM node:20-alpine AS production

# Security: run as non-root user
RUN addgroup -g 1001 -S appgroup && \
    adduser  -u 1001 -S appuser -G appgroup

WORKDIR /app

# Copy only production deps manifest and install
COPY package*.json ./
RUN npm ci --frozen-lockfile --only=production && \
    npm cache clean --force

# Copy built source from builder stage
COPY --from=builder /app/src ./src

# Set ownership
RUN chown -R appuser:appgroup /app
USER appuser

# Expose app port
EXPOSE 3000

# Healthcheck — ECS also checks via ALB, but this provides container-level awareness
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -qO- http://localhost:3000/health || exit 1

# Start the app
CMD ["node", "src/index.js"]
