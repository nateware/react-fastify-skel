import type { FastifyPluginAsync } from "fastify";

const example: FastifyPluginAsync = async (fastify) => {
  fastify.get("/", async () => {
    return "this is an example";
  });
};

export default example;
