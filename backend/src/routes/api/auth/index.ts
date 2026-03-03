import { eq } from "drizzle-orm";
import type { FastifyPluginAsync } from "fastify";
import { users } from "../../../db/schema.js";
import { verifyJwt } from "../../../lib/auth-config.js";
import { AUTH_COOKIE_NAME, sessionCookieOptions } from "../../../lib/cookie-utils.js";
import appleRoutes from "./apple.js";
import googleRoutes from "./google.js";

const authRoutes: FastifyPluginAsync = async (fastify) => {
  fastify.register(googleRoutes, { prefix: "/google" });
  fastify.register(appleRoutes, { prefix: "/apple" });
  // GET /api/auth/me — return current user or 401
  fastify.get("/me", async (request, reply) => {
    const token = request.cookies[AUTH_COOKIE_NAME];
    if (!token) {
      return reply.status(401).send({ error: "Not authenticated" });
    }

    try {
      const payload = await verifyJwt(token);
      const [user] = await fastify.db
        .select({
          id: users.id,
          email: users.email,
          name: users.name,
          avatarUrl: users.avatarUrl,
        })
        .from(users)
        .where(eq(users.id, Number(payload.sub)));

      if (!user) {
        reply.clearCookie(AUTH_COOKIE_NAME, { path: "/" });
        return reply.status(401).send({ error: "User not found" });
      }

      return user;
    } catch {
      reply.clearCookie(AUTH_COOKIE_NAME, { path: "/" });
      return reply.status(401).send({ error: "Invalid session" });
    }
  });

  // POST /api/auth/logout — clear session cookie
  fastify.post("/logout", async (_request, reply) => {
    reply.clearCookie(AUTH_COOKIE_NAME, sessionCookieOptions());
    return { success: true };
  });
};

export default authRoutes;
