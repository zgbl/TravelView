# TravelView Web —— 自托管用（OCI 上和 TensuGo 同机跑）。
# Vercel 部署不需要这个文件。
#
# 用 standalone 产物: 最终镜像里只有跑起来真正需要的东西，
# 大约 150MB，而不是把 node_modules 整个搬进去。

FROM node:22-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm ci --omit=dev --ignore-scripts || npm install --omit=dev

FROM node:22-alpine AS builder
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm ci || npm install
COPY . .
# NEXT_PUBLIC_* 会被**编译进前端代码**，所以必须在 build 时就给。
# 这几个都不是密钥，写进镜像没有安全问题。
ARG NEXT_PUBLIC_SITE_URL
ARG NEXT_PUBLIC_MEDIA_BASE
ARG NEXT_PUBLIC_MAP_TILES
ENV NEXT_PUBLIC_SITE_URL=$NEXT_PUBLIC_SITE_URL \
    NEXT_PUBLIC_MEDIA_BASE=$NEXT_PUBLIC_MEDIA_BASE \
    NEXT_PUBLIC_MAP_TILES=$NEXT_PUBLIC_MAP_TILES \
    NEXT_TELEMETRY_DISABLED=1
RUN npm run build

FROM node:22-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production NEXT_TELEMETRY_DISABLED=1 PORT=3000
RUN addgroup -g 1001 nodejs && adduser -u 1001 -G nodejs -S nextjs
COPY --from=builder /app/public ./public
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static
USER nextjs
EXPOSE 3000
CMD ["node", "server.js"]
