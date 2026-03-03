import pg from "pg";

interface PoolConnection {
  pool: pg.Pool;
  cleanup: () => Promise<void>;
}

/**
 * Create a pg.Pool using either:
 *   - DATABASE_URL (local dev / Docker Compose)
 *   - CLOUDSQL_CONNECTION + DB_IAM_USER + DB_NAME (Cloud Run via IAM auth)
 */
export async function createPool(): Promise<PoolConnection> {
  if (process.env.DATABASE_URL) {
    const pool = new pg.Pool({ connectionString: process.env.DATABASE_URL });
    return { pool, cleanup: () => pool.end() };
  }

  const instanceConnectionName = process.env.CLOUDSQL_CONNECTION;
  if (!instanceConnectionName) {
    throw new Error("Set DATABASE_URL (local) or CLOUDSQL_CONNECTION (Cloud SQL)");
  }

  const { Connector, IpAddressTypes, AuthTypes } = await import(
    "@google-cloud/cloud-sql-connector"
  );
  const connector = new Connector();
  const clientOpts = await connector.getOptions({
    instanceConnectionName,
    ipType: IpAddressTypes.PUBLIC,
    authType: AuthTypes.IAM,
  });

  const pool = new pg.Pool({
    ...clientOpts,
    user: process.env.DB_IAM_USER,
    database: process.env.DB_NAME || "app",
  });

  return {
    pool,
    cleanup: async () => {
      await pool.end();
      connector.close();
    },
  };
}
