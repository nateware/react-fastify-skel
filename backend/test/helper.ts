import Fastify, { type FastifyInstance } from "fastify";
import app from "../src/app.js";

async function build(): Promise<FastifyInstance> {
  const fastify = Fastify({ logger: false });
  await fastify.register(app);
  await fastify.ready();
  return fastify;
}

export { build };
