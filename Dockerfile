FROM node:22-alpine AS base
# 配置 Alpine 镜像源（阿里云）
RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.aliyun.com/g' /etc/apk/repositories
ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"
RUN corepack enable
# 配置 npm/pnpm 镜像源
RUN npm config set registry https://registry.npmmirror.com

FROM base AS deps
WORKDIR /usr/src/app
# node-gyp 编译 better-sqlite3 等原生模块所需的构建工具
RUN apk add --no-cache python3 make g++
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY packages/webgl-image/package.json ./packages/webgl-image/
RUN --mount=type=cache,id=pnpm,target=/pnpm/store pnpm install --frozen-lockfile

FROM base AS build
WORKDIR /usr/src/app
COPY --from=deps /usr/src/app/node_modules ./node_modules
COPY --from=deps /usr/src/app/packages/webgl-image/node_modules ./packages/webgl-image/node_modules
COPY . .
RUN NODE_OPTIONS="--max-old-space-size=4096" pnpm run build:deps
RUN NODE_OPTIONS="--max-old-space-size=4096" pnpm run build

FROM node:22-alpine AS runtime
RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.aliyun.com/g' /etc/apk/repositories \
    && apk update && apk add --no-cache perl exiftool
WORKDIR /app

COPY --from=build /usr/src/app/.output ./.output
COPY --from=build /usr/src/app/packages/webgl-image/dist ./packages/webgl-image/dist
COPY --from=build /usr/src/app/scripts ./scripts
COPY --from=build /usr/src/app/server/database/migrations ./server/database/migrations
COPY --from=deps /usr/src/app/node_modules ./node_modules

EXPOSE 3000
VOLUME ["/app/data"]

ENV NODE_ENV=production
ENV NITRO_PORT=3000
ENV NITRO_HOST=0.0.0.0

# node scripts/migrate.mjs first
CMD ["sh", "-c", "node scripts/migrate.mjs && node .output/server/index.mjs"]
