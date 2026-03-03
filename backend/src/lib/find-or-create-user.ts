import { and, eq } from "drizzle-orm";
import { oauthAccounts, users } from "../db/schema.js";
import type { DbClient } from "../plugins/db.js";

export interface OAuthProfile {
  email: string;
  name: string | null;
  avatarUrl: string | null;
  provider: string;
  providerAccountId: string;
}

export async function findOrCreateUser(db: DbClient, profile: OAuthProfile) {
  // Check if this specific OAuth account is already linked
  const [existingOAuth] = await db
    .select()
    .from(oauthAccounts)
    .where(
      and(
        eq(oauthAccounts.provider, profile.provider),
        eq(oauthAccounts.providerAccountId, profile.providerAccountId),
      ),
    );

  if (existingOAuth) {
    const [user] = await db.select().from(users).where(eq(users.id, existingOAuth.userId));
    return user;
  }

  // Check if a user with this email exists (link accounts by email)
  const [existingUser] = await db.select().from(users).where(eq(users.email, profile.email));

  if (existingUser) {
    await db.insert(oauthAccounts).values({
      userId: existingUser.id,
      provider: profile.provider,
      providerAccountId: profile.providerAccountId,
    });
    return existingUser;
  }

  // Create new user and link the OAuth account
  const [newUser] = await db
    .insert(users)
    .values({
      email: profile.email,
      name: profile.name,
      avatarUrl: profile.avatarUrl,
    })
    .returning();

  await db.insert(oauthAccounts).values({
    userId: newUser.id,
    provider: profile.provider,
    providerAccountId: profile.providerAccountId,
  });

  return newUser;
}
