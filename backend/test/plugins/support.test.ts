import Fastify from "fastify";
import { afterEach, describe, expect, it } from "vitest";
import Support from "../../src/plugins/support.js";

describe("support plugin", () => {
  const fastify = Fastify();
  fastify.register(Support);

  afterEach(async () => {
    await fastify.close();
  });

  it("decorates fastify with someSupport", async () => {
    await fastify.ready();
    expect(fastify.someSupport()).toBe("hugs");
  });
});
