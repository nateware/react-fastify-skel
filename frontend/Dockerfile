FROM node:22-alpine AS pruner
RUN npm install -g turbo@^2
WORKDIR /app
COPY . .
RUN turbo prune frontend --docker

FROM node:22-alpine AS installer
WORKDIR /app
COPY --from=pruner /app/out/json/ .
RUN npm ci

FROM node:22-alpine AS builder
WORKDIR /app
COPY --from=installer /app/ .
COPY --from=pruner /app/out/full/ .
RUN npm run build --workspace=frontend

FROM node:22-alpine
WORKDIR /app
COPY --from=pruner /app/out/json/ .
RUN npm ci --omit=dev
COPY --from=builder /app/frontend/build ./frontend/build
WORKDIR /app/frontend
# Cloud Run sets PORT; react-router-serve reads it automatically.
# This Dockerfile is only used for SSR mode (ssr: true in react-router.config.ts).
EXPOSE 8080
CMD ["npm", "run", "start"]
