# syntax=docker/dockerfile:1

ARG NODE_VERSION=22

# ---------------------------------------------------------------------------
# deps: all npm dependencies (dev dependencies are needed to build)
# ---------------------------------------------------------------------------
FROM node:${NODE_VERSION}-alpine AS deps

WORKDIR /app
COPY package.json package-lock.json ./
RUN --mount=type=cache,target=/root/.npm \
    npm ci --no-audit --no-fund

# ---------------------------------------------------------------------------
# builder: `next build` with output: 'standalone'
# ---------------------------------------------------------------------------
FROM node:${NODE_VERSION}-alpine AS builder

WORKDIR /app
ENV NEXT_TELEMETRY_DISABLED=1
COPY --from=deps /app/node_modules ./node_modules
COPY . .

# NEXT_PUBLIC_* values are inlined into the client bundle at build time.
ARG NEXT_PUBLIC_API_URL
ENV NEXT_PUBLIC_API_URL=$NEXT_PUBLIC_API_URL

RUN npm run build

# ---------------------------------------------------------------------------
# runner: standalone server + static assets only, running as UID 1000
# ---------------------------------------------------------------------------
FROM node:${NODE_VERSION}-alpine AS runner

WORKDIR /app
ENV NODE_ENV=production \
    NEXT_TELEMETRY_DISABLED=1 \
    PORT=3000

# Code stays owned by root (read-only for the app user); only .next/cache,
# where Next.js writes at runtime, is owned by UID 1000 (the image's `node` user).
COPY --from=builder /app/public ./public
COPY --from=builder /app/.next/standalone ./
COPY --from=builder /app/.next/static ./.next/static
RUN mkdir -p .next/cache && chown 1000:1000 .next/cache

USER 1000:1000

EXPOSE 3000

# Kubernetes sets HOSTNAME to the pod name, and server.js binds to $HOSTNAME,
# so force it to listen on all interfaces.
CMD ["sh", "-c", "HOSTNAME=0.0.0.0 exec node server.js"]
