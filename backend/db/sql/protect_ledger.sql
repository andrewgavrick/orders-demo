CREATE FUNCTION ledger_guard_transaction() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'DELETE' OR (TG_OP = 'UPDATE' AND OLD.posted_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Ledger transactions are immutable after posting; deletion is forbidden' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER ledger_transaction_guard BEFORE UPDATE OR DELETE ON account_transactions
FOR EACH ROW EXECUTE FUNCTION ledger_guard_transaction();

CREATE FUNCTION ledger_guard_entry() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE parent_posted timestamp;
BEGIN
  IF TG_OP <> 'INSERT' THEN
    RAISE EXCEPTION 'Ledger entries are immutable' USING ERRCODE = '23514';
  END IF;
  -- Serializing the parent prevents a concurrent insert racing with posting.
  SELECT posted_at INTO parent_posted FROM account_transactions
    WHERE id = NEW.account_transaction_id FOR UPDATE;
  IF parent_posted IS NOT NULL THEN
    RAISE EXCEPTION 'Cannot append to a posted transaction' USING ERRCODE = '23514';
  END IF;
  -- Account locks serialize balance checks and account metadata changes.
  -- Services must acquire every affected account in id order before writing.
  IF current_setting('transaction_isolation') <> 'read committed' THEN
    RAISE EXCEPTION 'Ledger writes require READ COMMITTED isolation' USING ERRCODE = '23514';
  END IF;
  PERFORM id FROM accounts WHERE id = NEW.account_id FOR UPDATE;
  RETURN NEW;
END;
$$;
CREATE TRIGGER ledger_entry_guard BEFORE INSERT OR UPDATE OR DELETE ON entries
FOR EACH ROW EXECUTE FUNCTION ledger_guard_entry();

CREATE FUNCTION ledger_guard_account() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF (NEW.actor_id, NEW.currency, NEW.account_type, NEW.purpose)
     IS DISTINCT FROM (OLD.actor_id, OLD.currency, OLD.account_type, OLD.purpose)
     AND EXISTS (SELECT 1 FROM entries WHERE account_id = OLD.id) THEN
    RAISE EXCEPTION 'Cannot reinterpret an account with ledger history' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER ledger_account_guard BEFORE UPDATE ON accounts
FOR EACH ROW EXECUTE FUNCTION ledger_guard_account();

CREATE FUNCTION ledger_validate() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE journal account_transactions%ROWTYPE; original account_transactions%ROWTYPE;
BEGIN
  SELECT * INTO journal FROM account_transactions WHERE id = NEW.id;
  IF journal.posted_at IS NULL THEN
    RAISE EXCEPTION 'A ledger transaction must be posted before commit' USING ERRCODE = '23514';
  END IF;
  IF (SELECT count(*) FROM entries WHERE account_transaction_id = journal.id) < 2 THEN
    RAISE EXCEPTION 'A ledger transaction requires at least two entries' USING ERRCODE = '23514';
  END IF;
  IF EXISTS (
    SELECT a.currency FROM entries e JOIN accounts a ON a.id = e.account_id
    WHERE e.account_transaction_id = journal.id GROUP BY a.currency
    HAVING sum(CASE WHEN e.direction = 'debit' THEN e.amount_minor ELSE -e.amount_minor END) <> 0
  ) THEN
    RAISE EXCEPTION 'Unbalanced ledger transaction by currency' USING ERRCODE = '23514';
  END IF;
  IF journal.kind = 'reversal' THEN
    SELECT * INTO original FROM account_transactions WHERE id = journal.reversal_of_id;
    IF original.id IS NULL OR original.id = journal.id OR original.kind <> 'charge'
       OR original.posted_at IS NULL OR original.order_id <> journal.order_id THEN
      RAISE EXCEPTION 'Reversal must reference a posted charge of the same order' USING ERRCODE = '23514';
    END IF;
    IF EXISTS (
      (SELECT account_id, amount_minor, direction FROM entries WHERE account_transaction_id = journal.id
       EXCEPT ALL
       SELECT account_id, amount_minor, CASE direction WHEN 'debit' THEN 'credit' ELSE 'debit' END
       FROM entries WHERE account_transaction_id = original.id)
      UNION ALL
      (SELECT account_id, amount_minor, CASE direction WHEN 'debit' THEN 'credit' ELSE 'debit' END
       FROM entries WHERE account_transaction_id = original.id
       EXCEPT ALL
       SELECT account_id, amount_minor, direction FROM entries WHERE account_transaction_id = journal.id)
    ) THEN
      RAISE EXCEPTION 'Reversal must exactly mirror the original entries' USING ERRCODE = '23514';
    END IF;
  END IF;
  IF EXISTS (
    SELECT a.id FROM accounts a JOIN entries e ON e.account_id = a.id
    JOIN account_transactions t ON t.id = e.account_transaction_id
    WHERE a.purpose = 'wallet' AND t.posted_at IS NOT NULL
      AND a.id IN (SELECT account_id FROM entries WHERE account_transaction_id = journal.id)
    GROUP BY a.id
    HAVING sum(CASE e.direction WHEN 'credit' THEN e.amount_minor ELSE -e.amount_minor END) < 0
  ) THEN
    RAISE EXCEPTION 'Insufficient funds in wallet' USING ERRCODE = '23514';
  END IF;
  RETURN NULL;
END;
$$;
CREATE CONSTRAINT TRIGGER ledger_commit AFTER INSERT OR UPDATE ON account_transactions
DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION ledger_validate();
