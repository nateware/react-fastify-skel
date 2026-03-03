import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { build } from "../helper.js";

describe("Google auth routes", () => {
  let app: Awaited<ReturnType<typeof build>>;

  beforeEach(async () => {
    vi.stubEnv("GOOGLE_CLIENT_ID", "test-client-id");
    vi.stubEnv("GOOGLE_CLIENT_SECRET", "test-client-secret");
    vi.stubEnv("GOOGLE_REDIRECT_URI", "http://localhost:3001/api/auth/google/callback");
    vi.stubEnv("JWT_SECRET", "test-jwt-secret");
    app = await build();
  });

  afterEach(async () => {
    await app.close();
    vi.unstubAllEnvs();
  });

  it("GET /api/auth/google redirects to Google consent screen", async () => {
    const res = await app.inject({ url: "/api/auth/google" });
    expect(res.statusCode).toBe(302);
    expect(res.headers.location).toContain("accounts.google.com");
  });

  it("GET /api/auth/google/callback rejects missing params", async () => {
    const res = await app.inject({ url: "/api/auth/google/callback" });
    expect(res.statusCode).toBe(400);
    expect(res.json()).toEqual({ error: "Invalid OAuth callback" });
  });
});
