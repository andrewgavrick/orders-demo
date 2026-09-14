export type Actor = { id: number; name: string; kind: "user" | "system" };
export type Order = {
  id: number; buyer_id: number; seller_id: number; amount_minor: number;
  currency: string; status: "created" | "successful" | "cancelled"; created_at?: string;
};
export type Account = {
  id: number; actor_id: number; account_type: string; purpose: string;
  balance_minor: number; currency: string;
};
export type Entry = {
  id: number; account_id: number; actor_id: number; direction: "debit" | "credit";
  amount_minor: number; currency: string; created_at?: string;
};
export type Journal = {
  id: number; order_id: number | null; kind: "charge" | "reversal" | "opening_balance";
  reversal_of_id: number | null; entries: Entry[]; created_at?: string;
};
export type Snapshot = {
  actor: Actor; accounts: Account[]; actors: Actor[]; orders: Order[]; transactions: Journal[];
};
export interface OrdersApi {
  load(actorId: number): Promise<Snapshot>;
  mutate(id: number, action: "complete" | "cancel"): Promise<{ order: Order; accounts: Account[] }>;
  journal(actorId: number): Promise<Journal[]>;
  create(actorId: number, sellerId: number, amount: number, currency: string): Promise<Order>;
}
export class ApiError extends Error {
  status: number;
  constructor(message: string, status: number) { super(message); this.status = status; }
}
async function request<T>(url: string, body?: unknown, method = body === undefined ? "GET" : "POST"): Promise<T> {
  let response: Response;
  try {
    response = await fetch(`/v1${url}`, {
      method, credentials: "same-origin", headers: { "Accept": "application/json", ...(method !== "GET" ? { "Content-Type": "application/json" } : {}) },
      ...(body !== undefined ? { body: JSON.stringify(body) } : {}),
    });
  } catch {
    throw new ApiError("Cannot reach the server. Refresh to check the latest state before retrying.", 0);
  }
  if (response.status === 204) return undefined as T;
  let data;
  try { data = await response.json(); }
  catch { throw new ApiError("The server returned an unexpected response. Please refresh.", response.status); }
  if (!response.ok) throw new ApiError(data.error?.message ?? "The request failed. Please refresh.", response.status);
  // JSON numbers outside JS's exact range must never silently become displayed money.
  function check(value: unknown): void {
    if (value && typeof value === "object") {
      for (const [key, item] of Object.entries(value)) {
        if ((key === "amount_minor" || key === "balance_minor") && !Number.isSafeInteger(item))
          throw new ApiError("This amount exceeds the exact range supported by this interface.", 422);
        check(item);
      }
    }
  }
  check(data);
  return data;
}
// Small demo collections are loaded page by page; no silent first-page truncation.
async function collection<K extends string, T>(url: string, key: K): Promise<T[]> {
  const rows: T[] = [];
  for (let page = 1; ; page++) {
    const result = await request<Record<K, T[]> & { meta: { page: number; per_page: number; total: number } }>(`${url}?page=${page}&per_page=100`);
    rows.push(...result[key]);
    if (page * result.meta.per_page >= result.meta.total) break;
    if (!result[key].length) throw new ApiError("The list changed while loading. Please refresh.", 409);
  }
  return rows;
}
export const sessionApi = {
  actors: () => collection<"actors", Actor>("/actors", "actors"),
  async current(): Promise<Actor | null> {
    try { return (await request<{ actor: Actor }>("/session")).actor; }
    catch (error) { if (error instanceof ApiError && error.status === 401) return null; throw error; }
  },
  async select(actor_id: number) { return (await request<{ actor: Actor }>("/session", { actor_id })).actor; },
  async logout() {
    try { await request<void>("/session", {}, "DELETE"); }
    catch (error) { if (!(error instanceof ApiError && error.status === 401)) throw error; }
  },
};
export const httpApi: OrdersApi = {
  async load(id) {
    const [profile, orders, transactions, actors] = await Promise.all([
      request<Pick<Snapshot, "actor" | "accounts">>(`/actors/${id}`),
      collection<"orders", Order>(`/actors/${id}/orders`, "orders"),
      this.journal(id), sessionApi.actors(),
    ]);
    return { ...profile, orders, transactions, actors };
  },
  mutate: (id, action) => request(`/orders/${id}/${action}`, {}),
  journal: (id) => collection<"transactions", Journal>(`/actors/${id}/transactions`, "transactions"),
  async create(id, seller_id, amount_minor, currency) {
    return (await request<{ order: Order }>(`/actors/${id}/orders`, { order: { seller_id, amount_minor, currency } })).order;
  },
};
export function currencyDigits(currency: string) {
  return new Intl.NumberFormat("en-US", { style: "currency", currency }).resolvedOptions().maximumFractionDigits ?? 2;
}
export function parseAmount(value: string, currency: string): number {
  const digits = currencyDigits(currency);
  const [whole, fraction = ""] = value.trim().split(".");
  if (!/^\d+(\.\d+)?$/.test(value.trim()) || fraction.length > digits)
    throw new Error("Enter an amount with the correct number of decimal places.");
  const minor = BigInt(whole) * 10n ** BigInt(digits) + BigInt(fraction.padEnd(digits, "0") || "0");
  if (minor <= 0n || minor > BigInt(Number.MAX_SAFE_INTEGER)) throw new Error("Enter a positive amount within the supported range.");
  return Number(minor);
}
export function money(amount: number | bigint, currency: string) {
  const minor = BigInt(amount);
  const digits = currencyDigits(currency);
  const scale = 10n ** BigInt(digits);
  const absolute = minor < 0n ? -minor : minor;
  const whole = absolute / scale;
  const signedWhole = minor < 0n ? (whole === 0n ? -0 : -whole) : whole;
  const fraction = (absolute % scale).toString().padStart(digits, "0");
  return new Intl.NumberFormat("en-US", { style: "currency", currency })
    .formatToParts(signedWhole)
    .map((part) => part.type === "fraction" ? fraction : part.value).join("");
}
export function sumMinor(amounts: number[]) {
  return amounts.reduce((sum, amount) => sum + BigInt(amount), 0n);
}
export function walletMovement(journal: Journal, accountId: number) {
  return journal.entries.filter((entry) => entry.account_id === accountId)
    .reduce((sum, entry) => sum + BigInt(entry.direction === "credit" ? entry.amount_minor : -entry.amount_minor), 0n);
}
