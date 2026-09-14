import { useEffect, useState } from "react";
import OrdersDashboard from "./OrdersDashboard";
import { sessionApi } from "./api";
import type { Actor } from "./api";
import "./App.css";

export default function App() {
  const [actor, setActor] = useState<Actor | null>(null);
  const [actors, setActors] = useState<Actor[]>([]);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [retry, setRetry] = useState(0);
  useEffect(() => {
    let active = true;
    Promise.all([sessionApi.current(), sessionApi.actors()]).then(([current, list]) => {
      if (active) { setActor(current); setActors(list); setError(""); }
    }).catch((reason: Error) => { if (active) setError(reason.message); })
      .finally(() => { if (active) setLoading(false); });
    return () => { active = false; };
  }, [retry]);

  async function select(id: number) {
    if (busy) return;
    setBusy(true); setError("");
    try { setActor(await sessionApi.select(id)); }
    catch (reason) { setError(reason instanceof Error ? reason.message : "Could not select participant."); }
    finally { setBusy(false); }
  }
  async function logout() {
    setBusy(true);
    try { await sessionApi.logout(); setActor(null); }
    finally { setBusy(false); }
  }
  if (actor) return <OrdersDashboard key={actor.id} actorId={actor.id} onSwitch={logout} switching={busy} onSessionExpired={() => setActor(null)} />;
  return <main className="welcome">
    <section className="welcome-card">
      <h1>Orders Demo</h1>
      <p>Select a participant to view their balance and orders.</p>
      <div className="demo-banner">Demo access · no password required. Changes are saved.</div>
      {error && <div role="alert" className="error-message">{error} <button onClick={() => { setLoading(true); setRetry((value) => value + 1); }}>Retry</button></div>}
      {loading ? <p role="status">Loading participants…</p> : <div className="actor-list">
        {actors.map((item) => <button key={item.id} disabled={busy} onClick={() => void select(item.id)}>
          <span className="avatar" aria-hidden="true">{item.name[0]}</span><strong>{item.name}</strong><span aria-hidden="true">↗</span>
        </button>)}
        {!actors.length && !error && <p>No participants are available yet.</p>}
      </div>}
    </section>
  </main>;
}
