import type { FastifyPluginAsync } from "fastify";

const root: FastifyPluginAsync = async (fastify) => {
  fastify.get("/", async () => {
    return { root: true };
  });
};

export default root;
