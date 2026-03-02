FROM node:22-alpine AS pruner
RUN npm install -g turbo@^2
WORKDIR /app
COPY . .
RUN turbo prune backend --docker

FROM node:22-alpine AS installer
WORKDIR /app
COPY --from=pruner /app/out/json/ .
RUN npm ci

FROM node:22-alpine AS builder
WORKDIR /app
COPY --from=installer /app/ .
COPY --from=pruner /app/out/full/ .
RUN npm run build --workspace=backend

FROM node:22-alpine
WORKDIR /app
COPY --from=pruner /app/out/json/ .
RUN npm ci --omit=dev
COPY --from=builder /app/backend/dist ./backend/dist
WORKDIR /app/backend
# Cloud Run sets PORT dynamically; fastify-cli reads it automatically.
# Do NOT set FASTIFY_PORT — it would override Cloud Run's PORT.
EXPOSE 8080
CMD ["npm", "run", "start"]
