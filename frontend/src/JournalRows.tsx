import { money, walletMovement } from "./api";
import type { Account, Actor, Journal } from "./api";

export default function JournalRows({ journals, account, actors }: { journals: Journal[]; account?: Account; actors: Actor[] }) {
  return journals.map((journal) => {
    const delta = account ? walletMovement(journal, account.id) : 0n;
    return <tr key={journal.id}>
      <td>
        <details className="entry-details">
          <summary><span className={`entry-icon ${delta >= 0 ? "reversal" : "charge"}`} aria-hidden="true">{delta >= 0 ? "↙" : "↗"}</span>
            <span className="entry-title"><strong>TX-{journal.id}</strong><small>{journal.reversal_of_id ? `Reverses TX-${journal.reversal_of_id}` : journal.kind === "opening_balance" ? "Opening balance" : "Order payment"}</small></span>
          </summary>
          <ul aria-label={`Entries for TX-${journal.id}`}>
            {journal.entries.map((entry) => <li key={entry.id}>
              <strong>{entry.direction}</strong> {money(entry.amount_minor, entry.currency)} · {entry.currency}<br />
              {actors.find((actor) => actor.id === entry.actor_id)?.name ?? "Platform"} · Account #{entry.account_id}
            </li>)}
          </ul>
        </details>
      </td>
      <td className="muted">{journal.order_id === null ? "—" : `#${journal.order_id}`}</td>
      <td><span className={`entry-kind ${journal.kind}`}>{journal.kind === "opening_balance" ? "Opening balance" : journal.kind}</span></td>
      <td className="muted">{journal.created_at ? new Intl.DateTimeFormat("en-US", { month: "short", day: "numeric" }).format(new Date(journal.created_at)) : "Today"}</td>
      <td className={`right money ${delta > 0 ? "positive" : ""}`}>{delta < 0 ? "−" : delta > 0 ? "+" : ""}{money(delta < 0n ? -delta : delta, account?.currency ?? "USD")}</td>
    </tr>;
  });
}
