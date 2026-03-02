import cors from "@fastify/cors";
import type { FastifyInstance } from "fastify";
import fp from "fastify-plugin";

/**
 * Enables CORS for all routes.
 * Set CORS_ORIGIN env var to restrict to a specific domain in production.
 * Falls back to `true` (reflect request origin) for development.
 *
 * @see https://github.com/fastify/fastify-cors
 */
export default fp(async (fastify: FastifyInstance) => {
  const origin = process.env.CORS_ORIGIN || true;
  fastify.register(cors, {
    origin,
  });
});
