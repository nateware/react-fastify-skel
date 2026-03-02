import { afterEach, describe, expect, it } from "vitest";
import { build } from "../helper.js";

describe("example route", () => {
  let app: Awaited<ReturnType<typeof build>>;

  afterEach(async () => {
    await app.close();
  });

  it("returns example text", async () => {
    app = await build();
    const res = await app.inject({ url: "/example" });
    expect(res.payload).toBe("this is an example");
  });
});
