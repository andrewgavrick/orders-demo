import { useEffect, useRef, useState } from "react";
import type { FormEvent } from "react";
import { ApiError, httpApi, money, parseAmount, sumMinor } from "./api";
import type { OrdersApi, Snapshot, Order } from "./api";
import JournalRows from "./JournalRows";
import "./App.css";

const date = (value?: string) => value ? new Intl.DateTimeFormat("en-US", { month: "short", day: "numeric" }).format(new Date(value)) : "Today";
export default function OrdersDashboard({ actorId, api = httpApi, onSwitch, switching = false, onSessionExpired }: {
  actorId: number; api?: OrdersApi; onSwitch?: () => Promise<void>; switching?: boolean; onSessionExpired?: () => void;
}) {
  const [data, setData] = useState<Snapshot | null>(null);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const [pending, setPending] = useState<number | null>(null);
  const busy = useRef(false);
  const loadVersion = useRef(0);
  const [filter, setFilter] = useState("all");
  const [search, setSearch] = useState("");
  const [page, setPage] = useState("orders");
  const [amount, setAmount] = useState("");
  const [sellerId, setSellerId] = useState("");
  const [accountId, setAccountId] = useState<number | null>(null);
  const [creating, setCreating] = useState(false);
  const [refreshing, setRefreshing] = useState(false);
  const [formError, setFormError] = useState("");
  const dialog = useRef<HTMLDialogElement>(null);
  const sessionExpired = useRef(onSessionExpired);
  useEffect(() => { sessionExpired.current = onSessionExpired; }, [onSessionExpired]);
  useEffect(() => {
    let active = true;
    const version = ++loadVersion.current;
    api.load(actorId).then((snapshot) => { if (active && version === loadVersion.current) { setData(snapshot); setError(""); } })
      .catch((reason: Error) => { if (active && version === loadVersion.current) { setError(reason.message); if (reason instanceof ApiError && reason.status === 401) sessionExpired.current?.(); } });
    return () => { active = false; };
  }, [api, actorId]);
  function showError(reason: unknown) {
    if (reason instanceof ApiError && reason.status === 401) sessionExpired.current?.();
    return reason instanceof Error ? reason.message : "Something went wrong. Please refresh before retrying.";
  }
  async function refresh() {
    if (busy.current) return;
    busy.current = true; setRefreshing(true); setError("");
    const version = ++loadVersion.current;
    try { const snapshot = await api.load(actorId); if (version === loadVersion.current) setData(snapshot); }
    catch (reason) { if (version === loadVersion.current) setError(showError(reason)); }
    finally { busy.current = false; setRefreshing(false); }
  }
  async function switchActor() {
    try { await onSwitch?.(); }
    catch (reason) { setError(showError(reason)); }
  }
  async function mutate(order: Order, action: "complete" | "cancel") {
    if (busy.current) return;
    busy.current = true; setPending(order.id); setError(""); setNotice("");
    ++loadVersion.current;
    let saved = false;
    try {
      const result = await api.mutate(order.id, action);
      saved = true;
      setData((previous) => previous && { ...previous,
        accounts: previous.accounts.map((item) => result.accounts.find((updated) => updated.id === item.id) ?? item),
        orders: previous.orders.map((item) => item.id === order.id ? result.order : item),
      });
      setNotice(`Order #${order.id} ${action === "complete" ? "completed" : "cancelled"}.`);
      const transactions = await api.journal(actorId);
      setData((previous) => previous && { ...previous, transactions });
    } catch (reason) {
      setError(`${saved ? "Order saved, but activity could not refresh. " : ""}${showError(reason)}`);
    } finally { busy.current = false; setPending(null); }
  }
  const wallets = data?.accounts.filter((item) => item.purpose === "wallet") ?? [];
  const account = wallets.find((item) => item.id === accountId) ?? wallets[0];
  const currency = account?.currency ?? "USD";
  async function create(event: FormEvent) {
    event.preventDefault();
    if (!data || !account || busy.current) return;
    let minor: number;
    try { minor = parseAmount(amount, currency); }
    catch (reason) { setFormError(showError(reason)); return; }
    if (!sellerId) { setFormError("Choose a seller."); return; }
    busy.current = true; setCreating(true); setFormError("");
    ++loadVersion.current;
    try {
      const order = await api.create(actorId, Number(sellerId), minor, currency);
      setData((previous) => previous && { ...previous, orders: [order, ...previous.orders] });
      setFilter("all"); setSearch(""); setPage("orders"); setAmount("");
      dialog.current?.close();
      setNotice(`Order #${order.id} created. Complete it when you’re ready.`);
    } catch (reason) { setFormError(showError(reason)); }
    finally { busy.current = false; setCreating(false); }
  }
  const orders = (data?.orders ?? []).filter((order) => order.currency === currency);
  const visible = orders.filter((order) => (filter === "all" || order.status === filter) && String(order.id).includes(search.replace("#", "").trim()));
  const created = orders.filter((order) => order.status === "created" && order.buyer_id === actorId);
  const successful = orders.filter((order) => order.status === "successful" && order.buyer_id === actorId);
  const total = sumMinor(successful.map((order) => order.amount_minor));
  const transactions = (data?.transactions ?? []).filter((journal) => journal.entries.some((entry) => entry.account_id === account?.id));
  return (
    <div className="workspace">
      <aside className="sidebar">
        <a className="app-name" href="/">Orders Demo</a>
        <div className="workspace-label">WORKSPACE</div>
        <nav aria-label="Main navigation">
          <button
            aria-label="Orders"
            className={page === "orders" ? "nav-item active" : "nav-item"}
            onClick={() => setPage("orders")}
          >
            <span aria-hidden="true">▦</span> Orders{" "}
            <span className="nav-count">{orders.length}</span>
          </button>
          <button
            aria-label="Transactions"
            className={page === "transactions" ? "nav-item active" : "nav-item"}
            onClick={() => setPage("transactions")}
          >
            <span aria-hidden="true">⇄</span> Transactions
          </button>
        </nav>
        <div className="profile">
          <span className="avatar">
            {(data?.actor.name ?? "?").slice(0, 1)}
          </span>
          <div>
            <strong>{data?.actor.name ?? "Your account"}</strong>
            <span>Demo participant</span>
          </div>
        </div>
      </aside>
      <div className="main-wrap">
        <header className="topbar">
          <span>
            Workspace <span className="breadcrumb">/</span>{" "}
            <strong>{page === "orders" ? "Orders" : "Transactions"}</strong>
          </span>
          <div className="workspace-actions">{data && <label className="wallet-select">Wallet<select aria-label="Wallet" disabled={pending !== null || creating || refreshing || switching} value={account?.id ?? ""} onChange={(event) => { setAccountId(Number(event.target.value)); setFilter("all"); }}><option value="" disabled>Select wallet</option>{wallets.map((wallet) => <option key={wallet.id} value={wallet.id}>{wallet.currency}</option>)}</select></label>}<button className="cancel" disabled={pending !== null || creating || refreshing || switching} onClick={() => void refresh()}>{refreshing ? "Refreshing…" : "Refresh"}</button>{onSwitch && <button className="cancel" disabled={pending !== null || creating || refreshing || switching} onClick={() => void switchActor()}>Switch participant</button>}<span className="environment">
            <i />
            Saved to server</span></div>
        </header>
        <main>

          <section className="page-heading">
            <div>
              <h1>
                {page === "orders" ? "Orders overview" : "Transaction history"}
              </h1>
              <p>
                {page === "orders"
                  ? "Create, complete and cancel orders."
                  : "Opening balances, payments and refunds."}
              </p>
            </div>
            <button
              className="primary"
              disabled={!account || pending !== null || refreshing || switching}
              onClick={() => {
                setFormError("");
                dialog.current?.showModal();
              }}
            >
              <span aria-hidden="true">＋</span> New order
            </button>
          </section>
          {error && (
            <div role="alert" className="error-message">
              {error}{" "}
              <button disabled={refreshing || pending !== null} onClick={() => void refresh()}>Refresh</button>
            </div>
          )}
          <div role="status" className={notice ? "notice" : "sr-only"}>
            {notice}
          </div>
          {!data ? (
            <div className="loading">
              {error
                ? "Unable to load the workspace."
                : "Loading your workspace…"}
            </div>
          ) : (
            <>
              <section className="summary-grid" aria-label="Account summary">
                <div className="balance-card">
                  <div className="card-label">
                    Available balance <span aria-hidden="true">↗</span>
                  </div>
                  <output aria-label="Balance">
                    {account ? money(account.balance_minor, currency) : "—"}
                  </output>
                  <div className="balance-footer">
                    <span>
                      <i /> {account ? "Ready to use" : "No wallet available"}
                    </span>
                    <span>
                      {currency} account ·{" "}
                      {account?.id.toString().padStart(4, "0") ?? "—"}
                    </span>
                  </div>
                  <div className="balance-orbit" />
                </div>
                <div className="metric-card">
                  <div className="card-label">
                    Awaiting your payment{" "}
                    <span className="metric-icon amber">◷</span>
                  </div>
                  <div className="metric-number">
                    {created.length.toString().padStart(2, "0")}
                    <span>orders</span>
                  </div>
                  <p>
                    {money(
                      sumMinor(created.map((order) => order.amount_minor)),
                      currency,
                    )}{" "}
                    pending total
                  </p>
                </div>
                <div className="metric-card">
                  <div className="card-label">
                    Completed purchases{" "}
                    <span className="metric-icon green">✓</span>
                  </div>
                  <div className="metric-number">
                    {successful.length.toString().padStart(2, "0")}
                    <span>orders</span>
                  </div>
                  <p>{money(total, currency)} in purchases</p>
                </div>
              </section>
              {page === "orders" && (
                <section className="panel orders-panel">
                  <div className="panel-heading">
                    <h2>
                      All orders <span>{orders.length}</span>
                    </h2>
                    <label className="search">
                      <span aria-hidden="true">⌕</span>
                      <input
                        aria-label="Search orders"
                        placeholder="Search order ID…"
                        value={search}
                        onChange={(e) => setSearch(e.target.value)}
                      />
                    </label>
                  </div>
                  <div className="filters" aria-label="Filter orders">
                    {["all", "created", "successful", "cancelled"].map(
                      (status) => (
                        <button
                          key={status}
                          aria-pressed={filter === status}
                          className={filter === status ? "selected" : ""}
                          onClick={() => setFilter(status)}
                        >
                          {status === "all"
                            ? "All orders"
                            : status === "created"
                              ? "Awaiting completion"
                              : status[0].toUpperCase() + status.slice(1)}
                          <span>
                            {status === "all"
                              ? orders.length
                              : orders.filter((o) => o.status === status)
                                  .length}
                          </span>
                        </button>
                      ),
                    )}
                  </div>
                  <div className="table-scroll">
                    <table aria-label="Orders">
                      <thead>
                        <tr>
                          <th>ORDER</th>
                          <th>PARTICIPANT / DATE</th>
                          <th>AMOUNT</th>
                          <th>STATUS</th>
                          <th className="right">ACTIONS</th>
                        </tr>
                      </thead>
                      <tbody>
                        {visible.map((order) => (
                          <tr key={order.id}>
                            <td>
                              <span className="order-icon" aria-hidden="true">
                                ▤
                              </span>
                              <strong>#{order.id}</strong>
                            </td>
                            <td className="muted"><strong>{data.actors.find((actor) => actor.id === (order.buyer_id === actorId ? order.seller_id : order.buyer_id))?.name ?? "Participant"}</strong><br />{order.buyer_id === actorId ? "Purchase" : "Sale"} · {date(order.created_at)}</td>
                            <td className="money">
                              {money(order.amount_minor, order.currency)}{" "}
                              <small>{order.currency}</small>
                            </td>
                            <td>
                              <span className={`status ${order.status}`}>
                                <i />
                                {order.status}
                              </span>
                            </td>
                            <td>
                              <div className="row-actions">
                                {order.buyer_id === actorId && order.status === "created" && (
                                  <button
                                    className="complete"
                                    disabled={pending !== null || creating || refreshing || switching}
                                    onClick={() => mutate(order, "complete")}
                                  >
                                    Complete
                                  </button>
                                )}
                                {order.buyer_id === actorId && order.status !== "cancelled" && (
                                  <button
                                    className="cancel"
                                    disabled={pending !== null || creating || refreshing || switching}
                                    onClick={() => mutate(order, "cancel")}
                                  >
                                    Cancel
                                  </button>
                                )}
                                {(order.buyer_id !== actorId || order.status === "cancelled") && (
                                  <span className="muted">—</span>
                                )}
                              </div>
                            </td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                  {visible.length === 0 && (
                    <div className="empty">
                      No orders found. Create an order or try another filter.
                    </div>
                  )}
                  <div className="table-footer">
                    Showing {visible.length} of {orders.length} orders{" "}
                    <span>Newest first</span>
                  </div>
                </section>
              )}
              <section className="panel journal">
                <div className="panel-heading">
                  <div>
                    <h2>
                      {page === "orders"
                        ? "Recent activity"
                        : "All transactions"}
                    </h2>
                    <p>Payments, refunds and opening balances.</p>
                  </div>
                  <span className="journal-count">
                    {transactions.length} transactions
                  </span>
                </div>
                <div className="table-scroll">
                  <table aria-label="Transactions">
                    <thead>
                      <tr>
                        <th>TRANSACTION</th>
                        <th>ORDER</th>
                        <th>TYPE</th>
                        <th>DATE</th>
                        <th className="right">AMOUNT</th>
                      </tr>
                    </thead>
                    <tbody>
                      <JournalRows journals={transactions} account={account} actors={data.actors} />
                    </tbody>
                  </table>
                </div>
                {transactions.length === 0 && (
                  <div className="empty">
                    No transactions yet.
                  </div>
                )}
              </section>
            </>
          )}
          <dialog aria-labelledby="new-order-title" ref={dialog}
            onCancel={(e) => {
              if (creating) e.preventDefault();
            }}
          >
            <form onSubmit={create}>
              <div className="dialog-top">
                <button
                  type="button"
                  aria-label="Close new order"
                  disabled={creating}
                  onClick={() => dialog.current?.close()}
                >
                  ×
                </button>
              </div>
              <h2 id="new-order-title">New order</h2>
              <p>Your balance changes only when you complete the order.</p>
              <label className="amount-label">Seller<select aria-label="Seller" value={sellerId} onChange={(event) => setSellerId(event.target.value)} required disabled={creating}><option value="">Choose a seller</option>{data?.actors.filter((actor) => actor.id !== actorId).map((actor) => <option key={actor.id} value={actor.id}>{actor.name}</option>)}</select></label>
<label className="amount-label">
                Amount ({currency})
                <input
                  autoFocus
                  inputMode="decimal"
                  placeholder="0.00"
                  value={amount}
                  onChange={(e) => setAmount(e.target.value)}
                  required
                />
              </label>
              {formError && (
                <p role="alert" className="form-error">
                  {formError}
                </p>
              )}
              <button className="primary create-submit" disabled={creating || !sellerId}>
                {creating ? "Creating…" : "Create order"}
              </button>
            </form>
          </dialog>
        </main>
      </div>
    </div>
  );
}
