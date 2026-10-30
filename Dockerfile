# syntax=docker/dockerfile:1.7

# =============================================================================
# Builder stage — installs production dependencies only, on a fresh Node base.
# =============================================================================

# TODO(step-4a): set the builder base image as node:20.11-slim and name the stage "builder".
FROM node:20.11-slim AS builder
#   Do NOT use `node:latest` — we want reproducible builds across the cohort.

WORKDIR /app

# TODO(step-4b): copy package.json and package-lock.json, then install deps.
COPY app/package.json app/package-lock.json ./
# proxy-addr 2.0.7 (pinned by the lockfile via express) has a CRITICAL CVE that
# fails the Trivy scan; 2.0.8 is the patched release and still fits express's ~2.0.7 range.
RUN npm ci --omit=dev && npm update proxy-addr --omit=dev

# TODO(step-4c): copy the rest of the app source into /app.
COPY app/ ./

# =============================================================================
# Runtime stage — slim final image. Nothing from builder's caches leaks in.
# =============================================================================

# TODO(step-4d): set the runtime base image (same tag as step-4a for consistency).
FROM node:20.11-slim

# The 20.11 base is from early 2024, so pull in Debian security fixes (gnutls, perl)
# and drop npm: the app runs with plain `node`, and npm's bundled deps (e.g. tar)
# carry CRITICAL CVEs that would fail the Trivy scan in CI.
RUN apt-get update \
 && apt-get upgrade -y --no-install-recommends \
 && rm -rf /var/lib/apt/lists/* \
 && rm -rf /usr/local/lib/node_modules/npm /usr/local/bin/npm /usr/local/bin/npx

WORKDIR /app

# TODO(step-4e): copy the fully-installed app from the builder stage.
COPY --from=builder /app /app

ENV NODE_ENV=production
EXPOSE 3000

# TODO(step-4f): add a HEALTHCHECK that probes http://localhost:3000/health.
#   IMPORTANT: `node:20.11-slim` does NOT ship with curl or wget.
#   Use Node's built-in http module instead:
HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=5 \
CMD node -e "require('http').get('http://localhost:3000/health', r => process.exit(r.statusCode===200?0:1)).on('error', () => process.exit(1))"

# TODO(step-4g): declare the container start command.
CMD ["node", "src/index.js"]
