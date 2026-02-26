# ==========================================
# Stage 1: Dependencies
# ==========================================
FROM node:20-alpine AS deps
RUN apk add --no-cache libc6-compat
WORKDIR /app

ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"
RUN corepack enable && corepack prepare pnpm@latest --activate

COPY package.json pnpm-lock.yaml* yarn.lock* package-lock.json* ./

RUN \
  if [ -f pnpm-lock.yaml ]; then \
    pnpm config set registry https://registry.npmjs.org && \
    pnpm i --frozen-lockfile; \
  elif [ -f yarn.lock ]; then \
    yarn config set registry https://registry.npmjs.org && \
    yarn --frozen-lockfile; \
  else \
    npm config set registry https://registry.npmjs.org && \
    npm ci; \
  fi

# ==========================================
# Stage 2: Builder
# ==========================================
FROM node:20-alpine AS builder
WORKDIR /app
RUN corepack enable && corepack prepare pnpm@latest --activate

COPY --from=deps /app/node_modules ./node_modules
# 直接拷贝你在 Debian 宿主机已经 Patch (去Auth + 删Edge) 好的源码
COPY . .

# 限制构建内存，防止甲骨文 VPS 假死
ENV NEXT_TELEMETRY_DISABLED=1
ENV NODE_ENV=production
ENV NODE_OPTIONS="--max-old-space-size=768"

RUN \
  if [ -f pnpm-lock.yaml ]; then pnpm run build; \
  elif [ -f yarn.lock ]; then yarn build; \
  else npm run build; \
  fi

# ==========================================
# Stage 3: Runner (极致压缩)
# ==========================================
FROM node:20-alpine AS runner
WORKDIR /app

ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1
ENV PORT=3000
ENV HOSTNAME="0.0.0.0"
ENV DOCKER_ENV=true

RUN addgroup --system --gid 1001 nodejs && \
    adduser --system --uid 1001 nextjs

# 解决权限问题并拷贝 Standalone 产物
COPY --from=builder --chown=nextjs:nodejs /app/public ./public
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static
COPY --from=builder --chown=nextjs:nodejs /app/start.js ./start.js
COPY --from=builder --chown=nextjs:nodejs /app/scripts ./scripts
COPY --from=builder --chown=nextjs:nodejs /app/config.json ./config.json

USER nextjs
EXPOSE 3000

# 🚀 修正点：CMD 后面必须带空格！
CMD ["node", "start.js"]