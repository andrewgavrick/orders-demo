SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: ledger_guard_account(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.ledger_guard_account() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF (NEW.actor_id, NEW.currency, NEW.account_type, NEW.purpose)
     IS DISTINCT FROM (OLD.actor_id, OLD.currency, OLD.account_type, OLD.purpose)
     AND EXISTS (SELECT 1 FROM entries WHERE account_id = OLD.id) THEN
    RAISE EXCEPTION 'Cannot reinterpret an account with ledger history' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: ledger_guard_entry(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.ledger_guard_entry() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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


--
-- Name: ledger_guard_order(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.ledger_guard_order() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF (NEW.amount_minor, NEW.currency, NEW.buyer_id, NEW.seller_id)
     IS DISTINCT FROM (OLD.amount_minor, OLD.currency, OLD.buyer_id, OLD.seller_id)
     AND EXISTS (SELECT 1 FROM account_transactions WHERE order_id = OLD.id AND posted_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Posted order financial attributes cannot change' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: ledger_guard_transaction(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.ledger_guard_transaction() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF TG_OP = 'DELETE' OR (TG_OP = 'UPDATE' AND OLD.posted_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Ledger transactions are immutable after posting; deletion is forbidden' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: ledger_lock_order(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.ledger_lock_order() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  -- Serialize journal creation with changes to the order's financial fields.
  PERFORM id FROM orders WHERE id = NEW.order_id FOR UPDATE;
  RETURN NEW;
END;
$$;


--
-- Name: ledger_validate(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.ledger_validate() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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


--
-- Name: ledger_validate_order(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.ledger_validate_order() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE target_id bigint; target orders%ROWTYPE; charge_id bigint; reversal_id bigint;
BEGIN
  IF TG_TABLE_NAME = 'orders' THEN
    target_id := NEW.id;
  ELSE
    target_id := NEW.order_id;
  END IF;
  SELECT * INTO target FROM orders WHERE id = target_id FOR UPDATE;
  IF NOT FOUND THEN RETURN NULL; END IF;

  SELECT id INTO charge_id FROM account_transactions
    WHERE order_id = target.id AND kind = 'charge' AND posted_at IS NOT NULL;
  SELECT id INTO reversal_id FROM account_transactions
    WHERE order_id = target.id AND kind = 'reversal' AND posted_at IS NOT NULL;

  IF (target.status = 'created' AND (charge_id IS NOT NULL OR reversal_id IS NOT NULL))
    OR (target.status = 'successful' AND (charge_id IS NULL OR reversal_id IS NOT NULL))
    OR (target.status = 'cancelled' AND ((charge_id IS NULL) <> (reversal_id IS NULL))) THEN
    RAISE EXCEPTION 'Order status must match its posted charge and reversal' USING ERRCODE = '23514';
  END IF;

  IF charge_id IS NOT NULL AND (
    target.buyer_id = target.seller_id
    OR (SELECT count(*) FROM entries WHERE account_transaction_id = charge_id) <> 2
    OR (SELECT count(*) FROM entries e JOIN accounts a ON a.id = e.account_id
      WHERE e.account_transaction_id = charge_id
        AND e.amount_minor = target.amount_minor AND a.currency = target.currency
        AND a.purpose = 'wallet' AND a.account_type = 'liability'
        AND ((e.direction = 'debit' AND a.actor_id = target.buyer_id)
          OR (e.direction = 'credit' AND a.actor_id = target.seller_id))) <> 2
  ) THEN
    RAISE EXCEPTION 'Charge must debit the buyer wallet and credit the seller wallet for the order amount and currency' USING ERRCODE = '23514';
  END IF;
  RETURN NULL;
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: account_transactions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.account_transactions (
    id bigint NOT NULL,
    order_id bigint,
    kind character varying NOT NULL,
    reversal_of_id bigint,
    created_at timestamp(6) without time zone NOT NULL,
    posted_at timestamp(6) without time zone,
    CONSTRAINT account_transactions_order_consistency CHECK (((((kind)::text = 'opening_balance'::text) AND (order_id IS NULL)) OR (((kind)::text = ANY ((ARRAY['charge'::character varying, 'reversal'::character varying])::text[])) AND (order_id IS NOT NULL)))),
    CONSTRAINT account_transactions_reversal_consistency CHECK (((((kind)::text = ANY ((ARRAY['charge'::character varying, 'opening_balance'::character varying])::text[])) AND (reversal_of_id IS NULL)) OR (((kind)::text = 'reversal'::text) AND (reversal_of_id IS NOT NULL)))),
    CONSTRAINT account_transactions_valid_kind CHECK (((kind)::text = ANY ((ARRAY['charge'::character varying, 'reversal'::character varying, 'opening_balance'::character varying])::text[])))
);


--
-- Name: account_transactions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.account_transactions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: account_transactions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.account_transactions_id_seq OWNED BY public.account_transactions.id;


--
-- Name: accounts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.accounts (
    id bigint NOT NULL,
    actor_id bigint NOT NULL,
    account_type character varying NOT NULL,
    purpose character varying NOT NULL,
    currency character varying(3) NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT accounts_currency_format CHECK (((currency)::text ~ '^[A-Z]{3}$'::text)),
    CONSTRAINT accounts_valid_account_type CHECK (((account_type)::text = ANY ((ARRAY['asset'::character varying, 'liability'::character varying, 'equity'::character varying, 'revenue'::character varying, 'expense'::character varying])::text[]))),
    CONSTRAINT wallets_are_liabilities CHECK ((((purpose)::text <> 'wallet'::text) OR ((account_type)::text = 'liability'::text)))
);


--
-- Name: accounts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.accounts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: accounts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.accounts_id_seq OWNED BY public.accounts.id;


--
-- Name: actors; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.actors (
    id bigint NOT NULL,
    kind character varying NOT NULL,
    name character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT actors_valid_kind CHECK (((kind)::text = ANY ((ARRAY['user'::character varying, 'system'::character varying])::text[])))
);


--
-- Name: actors_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.actors_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: actors_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.actors_id_seq OWNED BY public.actors.id;


--
-- Name: ar_internal_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: entries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.entries (
    id bigint NOT NULL,
    account_id bigint NOT NULL,
    account_transaction_id bigint NOT NULL,
    direction character varying NOT NULL,
    amount_minor bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT entries_positive_amount CHECK ((amount_minor > 0)),
    CONSTRAINT entries_valid_direction CHECK (((direction)::text = ANY ((ARRAY['debit'::character varying, 'credit'::character varying])::text[])))
);


--
-- Name: entries_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.entries_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: entries_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.entries_id_seq OWNED BY public.entries.id;


--
-- Name: orders; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.orders (
    id bigint NOT NULL,
    buyer_id bigint NOT NULL,
    seller_id bigint NOT NULL,
    amount_minor bigint NOT NULL,
    currency character varying(3) NOT NULL,
    status character varying DEFAULT 'created'::character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT orders_currency_format CHECK (((currency)::text ~ '^[A-Z]{3}$'::text)),
    CONSTRAINT orders_positive_amount CHECK ((amount_minor > 0)),
    CONSTRAINT orders_valid_status CHECK (((status)::text = ANY ((ARRAY['created'::character varying, 'successful'::character varying, 'cancelled'::character varying])::text[])))
);


--
-- Name: orders_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.orders_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: orders_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.orders_id_seq OWNED BY public.orders.id;


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: account_transactions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.account_transactions ALTER COLUMN id SET DEFAULT nextval('public.account_transactions_id_seq'::regclass);


--
-- Name: accounts id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounts ALTER COLUMN id SET DEFAULT nextval('public.accounts_id_seq'::regclass);


--
-- Name: actors id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.actors ALTER COLUMN id SET DEFAULT nextval('public.actors_id_seq'::regclass);


--
-- Name: entries id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.entries ALTER COLUMN id SET DEFAULT nextval('public.entries_id_seq'::regclass);


--
-- Name: orders id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orders ALTER COLUMN id SET DEFAULT nextval('public.orders_id_seq'::regclass);


--
-- Name: account_transactions account_transactions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.account_transactions
    ADD CONSTRAINT account_transactions_pkey PRIMARY KEY (id);


--
-- Name: accounts accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounts
    ADD CONSTRAINT accounts_pkey PRIMARY KEY (id);


--
-- Name: actors actors_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.actors
    ADD CONSTRAINT actors_pkey PRIMARY KEY (id);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: entries entries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.entries
    ADD CONSTRAINT entries_pkey PRIMARY KEY (id);


--
-- Name: orders orders_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: index_account_transactions_on_order_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_account_transactions_on_order_id ON public.account_transactions USING btree (order_id);


--
-- Name: index_account_transactions_on_reversal_of_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_account_transactions_on_reversal_of_id ON public.account_transactions USING btree (reversal_of_id);


--
-- Name: index_accounts_on_actor_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_accounts_on_actor_id ON public.accounts USING btree (actor_id);


--
-- Name: index_accounts_on_actor_purpose_currency; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_accounts_on_actor_purpose_currency ON public.accounts USING btree (actor_id, purpose, currency);


--
-- Name: index_entries_on_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_entries_on_account_id ON public.entries USING btree (account_id);


--
-- Name: index_entries_on_account_transaction_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_entries_on_account_transaction_id ON public.entries USING btree (account_transaction_id);


--
-- Name: index_orders_on_buyer_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_orders_on_buyer_id ON public.orders USING btree (buyer_id);


--
-- Name: index_orders_on_seller_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_orders_on_seller_id ON public.orders USING btree (seller_id);


--
-- Name: index_unique_charge_per_order; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_unique_charge_per_order ON public.account_transactions USING btree (order_id) WHERE ((kind)::text = 'charge'::text);


--
-- Name: accounts ledger_account_guard; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER ledger_account_guard BEFORE UPDATE ON public.accounts FOR EACH ROW EXECUTE FUNCTION public.ledger_guard_account();


--
-- Name: account_transactions ledger_commit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE CONSTRAINT TRIGGER ledger_commit AFTER INSERT OR UPDATE ON public.account_transactions DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.ledger_validate();


--
-- Name: orders ledger_commit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE CONSTRAINT TRIGGER ledger_commit AFTER INSERT OR UPDATE ON public.orders DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.ledger_validate_order();


--
-- Name: entries ledger_entry_guard; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER ledger_entry_guard BEFORE INSERT OR DELETE OR UPDATE ON public.entries FOR EACH ROW EXECUTE FUNCTION public.ledger_guard_entry();


--
-- Name: account_transactions ledger_order_commit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE CONSTRAINT TRIGGER ledger_order_commit AFTER INSERT OR UPDATE ON public.account_transactions DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.ledger_validate_order();


--
-- Name: orders ledger_order_guard; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER ledger_order_guard BEFORE UPDATE ON public.orders FOR EACH ROW EXECUTE FUNCTION public.ledger_guard_order();


--
-- Name: account_transactions ledger_order_lock; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER ledger_order_lock BEFORE INSERT ON public.account_transactions FOR EACH ROW EXECUTE FUNCTION public.ledger_lock_order();


--
-- Name: account_transactions ledger_transaction_guard; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER ledger_transaction_guard BEFORE DELETE OR UPDATE ON public.account_transactions FOR EACH ROW EXECUTE FUNCTION public.ledger_guard_transaction();


--
-- Name: entries fk_rails_37a3feaeb6; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.entries
    ADD CONSTRAINT fk_rails_37a3feaeb6 FOREIGN KEY (account_id) REFERENCES public.accounts(id);


--
-- Name: entries fk_rails_4a563fe1c9; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.entries
    ADD CONSTRAINT fk_rails_4a563fe1c9 FOREIGN KEY (account_transaction_id) REFERENCES public.account_transactions(id);


--
-- Name: accounts fk_rails_634faa3c95; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounts
    ADD CONSTRAINT fk_rails_634faa3c95 FOREIGN KEY (actor_id) REFERENCES public.actors(id);


--
-- Name: account_transactions fk_rails_8b685df1e2; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.account_transactions
    ADD CONSTRAINT fk_rails_8b685df1e2 FOREIGN KEY (reversal_of_id) REFERENCES public.account_transactions(id);


--
-- Name: orders fk_rails_d3775977e3; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT fk_rails_d3775977e3 FOREIGN KEY (buyer_id) REFERENCES public.actors(id);


--
-- Name: orders fk_rails_f569184c98; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT fk_rails_f569184c98 FOREIGN KEY (seller_id) REFERENCES public.actors(id);


--
-- Name: account_transactions fk_rails_f6c0f78923; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.account_transactions
    ADD CONSTRAINT fk_rails_f6c0f78923 FOREIGN KEY (order_id) REFERENCES public.orders(id);


--
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
('20260914045327'),
('20260913031208'),
('20260912142652'),
('20260912063819'),
('20260912051743');
