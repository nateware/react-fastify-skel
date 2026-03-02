import type { FastifyInstance } from "fastify";
import fp from "fastify-plugin";

// The use of fastify-plugin is required to be able
// to export the decorators to the outer scope.

export default fp(async (fastify: FastifyInstance) => {
  fastify.decorate("someSupport", () => {
    return "hugs";
  });
});

declare module "fastify" {
  export interface FastifyInstance {
    someSupport(): string;
  }
}
