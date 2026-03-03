// Provide cookie type augmentations for Fastify.
//
// In the turbo prune Docker build, @fastify/cookie is hoisted to the root
// node_modules while fastify stays in backend/node_modules. This means
// @fastify/cookie's own "declare module 'fastify'" can't resolve the fastify
// package and its augmentation silently fails.
//
// By declaring the augmentation here (inside backend/src/), TypeScript
// resolves 'fastify' from backend/node_modules/ and the merge succeeds.

import type { CookieSerializeOptions } from "@fastify/cookie";

declare module "fastify" {
  interface FastifyRequest {
    cookies: { [cookieName: string]: string | undefined };
  }

  interface FastifyReply {
    setCookie(name: string, value: string, options?: CookieSerializeOptions): this;
    clearCookie(name: string, options?: CookieSerializeOptions): this;
  }
}
