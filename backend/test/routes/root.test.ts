import { afterEach, describe, expect, it } from "vitest";
import { build } from "../helper.js";

describe("root route", () => {
  let app: Awaited<ReturnType<typeof build>>;

  afterEach(async () => {
    await app.close();
  });

  it("returns { root: true }", async () => {
    app = await build();
    const res = await app.inject({ url: "/" });
    expect(res.json()).toEqual({ root: true });
  });
});
