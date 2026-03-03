import formbody from "@fastify/formbody";
import type { FastifyInstance } from "fastify";
import fp from "fastify-plugin";

export default fp(async (fastify: FastifyInstance) => {
  fastify.register(formbody);
});
