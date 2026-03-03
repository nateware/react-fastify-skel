import type { FastifyInstance, FastifyReply, FastifyRequest } from "fastify";
import fp from "fastify-plugin";

import { type JwtPayload, verifyJwt } from "../lib/auth-config.js";
import { AUTH_COOKIE_NAME } from "../lib/cookie-utils.js";

export default fp(async (fastify: FastifyInstance) => {
  fastify.decorateRequest("user", null);

  fastify.decorate("authenticate", async (request: FastifyRequest, reply: FastifyReply) => {
    const token = request.cookies[AUTH_COOKIE_NAME];
    if (!token) {
      return reply.status(401).send({ error: "Not authenticated" });
    }

    try {
      const payload = await verifyJwt(token);
      request.user = payload;
    } catch {
      reply.clearCookie(AUTH_COOKIE_NAME, { path: "/" });
      return reply.status(401).send({ error: "Invalid session" });
    }
  });
});

declare module "fastify" {
  export interface FastifyInstance {
    authenticate: (request: FastifyRequest, reply: FastifyReply) => Promise<void>;
  }
  export interface FastifyRequest {
    user: JwtPayload | null;
  }
}
