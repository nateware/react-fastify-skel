import * as arctic from "arctic";
import type { FastifyPluginAsync } from "fastify";

import { createGoogleProvider, signJwt } from "../../../lib/auth-config.js";
import {
  AUTH_COOKIE_NAME,
  oauthStateCookieOptions,
  STATE_COOKIE_NAME,
  sessionCookieOptions,
  VERIFIER_COOKIE_NAME,
} from "../../../lib/cookie-utils.js";
import { findOrCreateUser } from "../../../lib/find-or-create-user.js";

const googleRoutes: FastifyPluginAsync = async (fastify) => {
  if (!process.env.GOOGLE_CLIENT_ID) {
    fastify.log.warn("GOOGLE_CLIENT_ID not set — skipping Google auth routes");
    return;
  }
  const google = createGoogleProvider();

  // GET /api/auth/google — redirect to Google consent screen
  fastify.get("/", async (_request, reply) => {
    const state = arctic.generateState();
    const codeVerifier = arctic.generateCodeVerifier();
    const url = google.createAuthorizationURL(state, codeVerifier, ["openid", "email", "profile"]);

    reply.setCookie(STATE_COOKIE_NAME, state, oauthStateCookieOptions());
    reply.setCookie(VERIFIER_COOKIE_NAME, codeVerifier, oauthStateCookieOptions());

    return reply.redirect(url.toString());
  });

  // GET /api/auth/google/callback — handle Google OAuth callback
  fastify.get("/callback", async (request, reply) => {
    const { code, state } = request.query as {
      code?: string;
      state?: string;
    };
    const storedState = request.cookies[STATE_COOKIE_NAME];
    const storedVerifier = request.cookies[VERIFIER_COOKIE_NAME];

    if (!code || !state || !storedState || state !== storedState || !storedVerifier) {
      return reply.status(400).send({ error: "Invalid OAuth callback" });
    }

    reply.clearCookie(STATE_COOKIE_NAME, { path: "/" });
    reply.clearCookie(VERIFIER_COOKIE_NAME, { path: "/" });

    const frontendUrl = process.env.FRONTEND_URL || "http://localhost:5173";

    try {
      const tokens = await google.validateAuthorizationCode(code, storedVerifier);
      const claims = arctic.decodeIdToken(tokens.idToken()) as {
        sub: string;
        email: string;
        name?: string;
        picture?: string;
      };

      const user = await findOrCreateUser(fastify.db, {
        email: claims.email,
        name: claims.name ?? null,
        avatarUrl: claims.picture ?? null,
        provider: "google",
        providerAccountId: claims.sub,
      });

      const jwt = await signJwt({ sub: String(user.id), email: user.email });
      reply.setCookie(AUTH_COOKIE_NAME, jwt, sessionCookieOptions());

      return reply.redirect(frontendUrl);
    } catch (e) {
      fastify.log.error(e, "Google OAuth callback failed");
      return reply.redirect(`${frontendUrl}/login?error=oauth_failed`);
    }
  });
};

export default googleRoutes;
