import cors from "@fastify/cors";
import fp from "fastify-plugin";

/**
 * Enables CORS for all routes.
 *
 * @see https://github.com/fastify/fastify-cors
 */
export default fp(async (fastify) => {
  fastify.register(cors, {
    origin: true,
  });
});
