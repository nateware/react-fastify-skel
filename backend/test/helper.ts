import path from "node:path";
import { fileURLToPath } from "node:url";
import type { FastifyInstance } from "fastify";
import { build as buildApplication } from "fastify-cli/helper.js";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const AppPath = path.join(__dirname, "..", "src", "app.ts");

function config() {
  return {
    skipOverride: true,
  };
}

async function build(): Promise<FastifyInstance> {
  const argv = [AppPath];
  const app = await buildApplication(argv, config());
  return app;
}

export { config, build };
