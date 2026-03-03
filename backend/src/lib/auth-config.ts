import { Buffer } from "node:buffer";
import * as arctic from "arctic";
import * as jose from "jose";

function requireEnv(name: string): string {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

// --- OAuth Providers ---

export function createGoogleProvider(): arctic.Google {
  return new arctic.Google(
    requireEnv("GOOGLE_CLIENT_ID"),
    requireEnv("GOOGLE_CLIENT_SECRET"),
    requireEnv("GOOGLE_REDIRECT_URI"),
  );
}

export function createAppleProvider(): arctic.Apple {
  const pem = requireEnv("APPLE_PRIVATE_KEY");
  const b64 = pem
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replaceAll("\r", "")
    .replaceAll("\n", "")
    .trim();
  const privateKey = new Uint8Array(Buffer.from(b64, "base64"));
  return new arctic.Apple(
    requireEnv("APPLE_CLIENT_ID"),
    requireEnv("APPLE_TEAM_ID"),
    requireEnv("APPLE_KEY_ID"),
    privateKey,
    requireEnv("APPLE_REDIRECT_URI"),
  );
}

// --- JWT ---

const jwtSecretKey = () => new TextEncoder().encode(requireEnv("JWT_SECRET"));
const JWT_ISSUER = "react-fastify-skel";
const JWT_EXPIRATION = "7d";

export interface JwtPayload {
  sub: string;
  email: string;
}

export async function signJwt(payload: JwtPayload): Promise<string> {
  return new jose.SignJWT({ email: payload.email })
    .setProtectedHeader({ alg: "HS256" })
    .setSubject(payload.sub)
    .setIssuer(JWT_ISSUER)
    .setIssuedAt()
    .setExpirationTime(JWT_EXPIRATION)
    .sign(jwtSecretKey());
}

export async function verifyJwt(token: string): Promise<JwtPayload> {
  const { payload } = await jose.jwtVerify(token, jwtSecretKey(), {
    issuer: JWT_ISSUER,
  });
  return { sub: payload.sub ?? "", email: payload.email as string };
}
