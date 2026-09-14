import { vi } from "vitest";
import type { Actor, Journal, Order } from "../src/api";

export const actors: Actor[] = [{ id: 1, name: "Alex", kind: "user" }, { id: 2, name: "Sam", kind: "user" }];
export function setupApi(status: Order["status"] = "created", sellerView = false, loggedIn = true) {
  const orders: Order[] = [{ id: 42, buyer_id: sellerView ? 2 : 1, seller_id: sellerView ? 1 : 2, amount_minor: 250, currency: "USD", status }];
  const order = orders[0];
  const account = { id: 7, actor_id: 1, account_type: "liability", purpose: "wallet", balance_minor: status === "successful" ? (sellerView ? 1250 : 750) : 1000, currency: "USD" };
  const posting = (kind: "charge" | "reversal"): Journal => ({
    id: kind === "charge" ? 100 : 101, order_id: 42, kind, reversal_of_id: kind === "reversal" ? 100 : null,
    entries: [
      { id: 201, account_id: 7, actor_id: 1, amount_minor: 250, currency: "USD", direction: (kind === "charge") !== sellerView ? "debit" : "credit" },
      { id: 202, account_id: 8, actor_id: 2, amount_minor: 250, currency: "USD", direction: (kind === "charge") !== sellerView ? "credit" : "debit" },
    ],
  });
  const transactions: Journal[] = status === "successful" ? [posting("charge")] : [];
  let mutation: (() => Promise<Response>) | undefined;
  let selected: Actor | null = loggedIn ? actors[0] : null;
  let journalFailure = false;
  const json = (data: unknown, status = 200) => new Response(JSON.stringify(data), { status, headers: { "Content-Type": "application/json" } });
  const list = (key: string, rows: unknown[]) => json({ [key]: rows, meta: { page: 1, per_page: 100, total: rows.length } });
  const fetchMock = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = new URL(String(input), "http://localhost");
    const method = init?.method ?? "GET";
    if (url.pathname === "/v1/session") {
      if (method === "POST") { selected = actors.find((actor) => actor.id === JSON.parse(init?.body as string).actor_id)!; return json({ actor: selected }, 201); }
      if (method === "DELETE") { selected = null; return new Response(null, { status: 204 }); }
      return selected ? json({ actor: selected }) : json({ error: { message: "Select an actor" } }, 401);
    }
    if (method === "GET") {
      if (url.pathname === "/v1/actors") return list("actors", actors);
      if (url.pathname === "/v1/actors/1") return json({ actor: actors[0], accounts: [account] });
      if (url.pathname === "/v1/actors/1/orders") return list("orders", orders);
      if (url.pathname === "/v1/actors/1/transactions") return journalFailure ? json({ error: { message: "Activity unavailable" } }, 503) : list("transactions", transactions);
    }
    if (method === "POST" && url.pathname === "/v1/actors/1/orders") {
      const input = JSON.parse(init?.body as string).order;
      const created: Order = { id: 43, buyer_id: 1, status: "created", ...input };
      orders.unshift(created);
      return json({ order: created }, 201);
    }
    if (method === "POST" && ["/v1/orders/42/complete", "/v1/orders/42/cancel"].includes(url.pathname)) {
      if (mutation) return mutation();
      if (url.pathname.endsWith("/complete")) { order.status = "successful"; account.balance_minor = 750; transactions.push(posting("charge")); }
      else { if (order.status === "successful") { account.balance_minor = 1000; transactions.push(posting("reversal")); } order.status = "cancelled"; }
      return json({ order, accounts: [account] });
    }
    throw new Error(`Unexpected API request: ${method} ${url.pathname}`);
  });
  vi.stubGlobal("fetch", fetchMock);
  return { fetchMock, setMutation: (callback: () => Promise<Response>) => { mutation = callback; }, json,
    failJournal: () => { journalFailure = true; }, transactions, account };
}
