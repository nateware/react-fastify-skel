import * as arctic from "arctic";
import type { FastifyPluginAsync } from "fastify";

import { createAppleProvider, signJwt } from "../../../lib/auth-config.js";
import {
  AUTH_COOKIE_NAME,
  oauthStateCookieOptions,
  STATE_COOKIE_NAME,
  sessionCookieOptions,
} from "../../../lib/cookie-utils.js";
import { findOrCreateUser } from "../../../lib/find-or-create-user.js";

const appleRoutes: FastifyPluginAsync = async (fastify) => {
  if (!process.env.APPLE_CLIENT_ID) {
    fastify.log.warn("APPLE_CLIENT_ID not set — skipping Apple auth routes");
    return;
  }
  const apple = createAppleProvider();

  // GET /api/auth/apple — redirect to Apple consent screen
  fastify.get("/", async (_request, reply) => {
    const state = arctic.generateState();
    const url = apple.createAuthorizationURL(state, ["name", "email"]);

    reply.setCookie(STATE_COOKIE_NAME, state, oauthStateCookieOptions());

    return reply.redirect(url.toString());
  });

  // POST /api/auth/apple/callback — Apple uses form_post response mode
  fastify.post("/callback", async (request, reply) => {
    const body = request.body as {
      code?: string;
      state?: string;
      user?: string; // JSON string, only on first authorization
    };

    const storedState = request.cookies[STATE_COOKIE_NAME];

    if (!body.code || !body.state || !storedState || body.state !== storedState) {
      return reply.status(400).send({ error: "Invalid OAuth callback" });
    }

    reply.clearCookie(STATE_COOKIE_NAME, { path: "/" });

    const frontendUrl = process.env.FRONTEND_URL || "http://localhost:5173";

    try {
      const tokens = await apple.validateAuthorizationCode(body.code);
      const claims = arctic.decodeIdToken(tokens.idToken()) as {
        sub: string;
        email?: string;
      };

      // Apple sends user info only on first authorization
      let userName: string | null = null;
      let userEmail: string = claims.email ?? "";

      if (body.user) {
        try {
          const appleUser = JSON.parse(body.user) as {
            name?: { firstName?: string; lastName?: string };
            email?: string;
          };
          if (appleUser.name) {
            userName =
              [appleUser.name.firstName, appleUser.name.lastName].filter(Boolean).join(" ") || null;
          }
          if (appleUser.email) {
            userEmail = appleUser.email;
          }
        } catch {
          // Fall back to ID token claims
        }
      }

      if (!userEmail) {
        return reply.status(400).send({ error: "Email not available from Apple" });
      }

      const user = await findOrCreateUser(fastify.db, {
        email: userEmail,
        name: userName,
        avatarUrl: null,
        provider: "apple",
        providerAccountId: claims.sub,
      });

      const jwt = await signJwt({ sub: String(user.id), email: user.email });
      reply.setCookie(AUTH_COOKIE_NAME, jwt, sessionCookieOptions());

      return reply.redirect(frontendUrl);
    } catch (e) {
      fastify.log.error(e, "Apple OAuth callback failed");
      return reply.redirect(`${frontendUrl}/login?error=oauth_failed`);
    }
  });
};

export default appleRoutes;
