import { drizzle, type NodePgDatabase } from "drizzle-orm/node-postgres";
import type { FastifyInstance } from "fastify";
import fp from "fastify-plugin";

import { createPool } from "../db/connect.js";
import * as schema from "../db/schema.js";

export type DbClient = NodePgDatabase<typeof schema>;

export default fp(async (fastify: FastifyInstance) => {
  if (!process.env.DATABASE_URL && !process.env.CLOUDSQL_CONNECTION) {
    fastify.log.warn("DATABASE_URL / CLOUDSQL_CONNECTION not set — skipping database connection");
    return;
  }

  const { pool, cleanup } = await createPool();

  await pool.query("SELECT 1");

  const db = drizzle(pool, { schema });

  fastify.decorate("db", db);

  fastify.addHook("onClose", async () => {
    await cleanup();
  });
});

declare module "fastify" {
  export interface FastifyInstance {
    db: DbClient;
  }
}
