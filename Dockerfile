FROM oven/bun:1.3.10-slim AS node

# build-essential and python3 are required for node-pty
# others are for development inside the container
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    python3 python3-pip \
    && rm -rf /var/lib/apt/lists/*
ENV PYTHON=/usr/bin/python3
ENV PIP=/usr/bin/pip3

# node-gyp needs this
RUN python3 -m pip install -U setuptools --break-system-packages

FROM node AS deps-prod

# install production dependencies
WORKDIR /app
COPY package.json .
COPY scripts/fix-node-pty.js scripts/fix-node-pty.js
RUN bun install --production --frozen-lockfile

FROM deps-prod AS deps

# install development dependencies
WORKDIR /app
RUN bun install -D --frozen-lockfile


FROM node AS builder

WORKDIR /src
COPY --from=deps /app/node_modules ./node_modules
COPY . .

ENV NODE_ENV=production
RUN bun --bun run build


FROM oven/bun:1.3.10-slim AS runtime
# others are for development inside the container
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-pip \
    golang \
    git \
    ca-certificates \
    libglib2.0-0 \
    bash \
    ripgrep fzf jq tmux openssl libssl-dev \
    && rm -rf /var/lib/apt/lists/*
ENV PYTHON=/usr/bin/python3
ENV PIP=/usr/bin/pip3

RUN mkdir -p /app

# install the latest go
ENV GOPATH=/app/.local/go
ENV GOMODCACHE=/app/.local/go/mod
ENV GOCACHE=/app/.local/go/cache
ENV PATH=$GOPATH/bin:$PATH
RUN go install golang.org/dl/go1.26.0@latest
RUN go1.26.0 download
RUN go version

SHELL ["/bin/bash", "-c"]
ENV SHELL=/bin/bash

ENV BUN_INSTALL=/app/.bun
# install prettier, eslint, biome (use prettier+eslint or biome based on your preference)
RUN bun add -g prettier eslint @biomejs/biome

FROM runtime AS runner
WORKDIR /app
COPY --from=deps-prod /app/node_modules ./node_modules
COPY --from=builder /src/dist ./dist
COPY --from=builder /src/package.json ./package.json
COPY --from=builder /src/server ./server
COPY --from=builder /src/public ./public
COPY --from=builder /src/shared ./shared
RUN mkdir -p /app/data /app/.codex /app/.claude /app/.cursor /app/.gemini
RUN chown -R 1000:1000 /app

USER 1000:1000

ENV HOST 0.0.0.0
ENV PORT 3001
EXPOSE 3001
ENV DATABASE_PATH=/app/data/cloudcli.db
ENV HOME=/app
ENV GEMINI_PATH=/app/.gemini

CMD ["--bun", "server/index.js"]
