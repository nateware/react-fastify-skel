// Side-effect import so TypeScript picks up @fastify/cookie's
// declaration merging for .cookies, .setCookie, .clearCookie on Fastify types.
import "@fastify/cookie";
import type { CookieSerializeOptions } from "@fastify/cookie";

const isProduction = () => process.env.NODE_ENV === "production";

export const AUTH_COOKIE_NAME = "session";
export const STATE_COOKIE_NAME = "oauth_state";
export const VERIFIER_COOKIE_NAME = "oauth_code_verifier";

export function sessionCookieOptions(): CookieSerializeOptions {
  return {
    httpOnly: true,
    secure: isProduction(),
    sameSite: isProduction() ? "none" : "lax",
    path: "/",
    maxAge: 60 * 60 * 24 * 7, // 7 days
  };
}

export function oauthStateCookieOptions(): CookieSerializeOptions {
  return {
    httpOnly: true,
    secure: isProduction(),
    sameSite: "lax",
    path: "/",
    maxAge: 60 * 10, // 10 minutes
  };
}
