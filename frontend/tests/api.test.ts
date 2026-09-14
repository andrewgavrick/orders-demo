import { expect, it, vi } from "vitest";
import { parseAmount, sessionApi } from "../src/api";

it("parses minor units exactly and respects currency precision", () => {
  expect(parseAmount("0.29", "USD")).toBe(29);
  expect(parseAmount("10", "JPY")).toBe(10);
  expect(parseAmount("1.001", "KWD")).toBe(1001);
  for (const value of ["0", "-1", "1.001", "1e3", "90071992547409.92"])
    expect(() => parseAmount(value, "USD")).toThrow();
});
it("loads every page of participants", async () => {
  const fetch = vi.fn(async (url: string) => new Response(JSON.stringify({
    actors: [{ id: url.includes("page=2") ? 2 : 1, name: "Actor", kind: "user" }],
    meta: { page: url.includes("page=2") ? 2 : 1, per_page: 1, total: 2 },
  }), { status: 200 }));
  vi.stubGlobal("fetch", fetch);
  expect((await sessionApi.actors()).map((actor) => actor.id)).toEqual([1, 2]);
  expect(fetch).toHaveBeenCalledTimes(2);
});

it('formats large amounts and negative subunits without rounding', async () => {
  const { money, sumMinor } = await import('../src/api');
  expect(money(9007199254740991, 'USD')).toBe('$90,071,992,547,409.91');
  expect(money(-1, 'USD')).toBe('-$0.01');
  expect(money(1001, 'KWD')).toMatch(/1\.001/);
  expect(money(42, 'JPY')).toBe('¥42');
  expect(money(sumMinor([9007199254740991, 9007199254740991]), 'USD')).toBe('$180,143,985,094,819.82');
});
