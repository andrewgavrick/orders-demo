class ProtectPostedOrders < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE FUNCTION ledger_lock_order() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        -- Serialize journal creation with changes to the order's financial fields.
        PERFORM id FROM orders WHERE id = NEW.order_id FOR UPDATE;
        RETURN NEW;
      END;
      $$;
      CREATE TRIGGER ledger_order_lock BEFORE INSERT ON account_transactions
      FOR EACH ROW EXECUTE FUNCTION ledger_lock_order();

      CREATE FUNCTION ledger_guard_order() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        IF (NEW.amount_minor, NEW.currency, NEW.buyer_id, NEW.seller_id)
           IS DISTINCT FROM (OLD.amount_minor, OLD.currency, OLD.buyer_id, OLD.seller_id)
           AND EXISTS (SELECT 1 FROM account_transactions WHERE order_id = OLD.id AND posted_at IS NOT NULL) THEN
          RAISE EXCEPTION 'Posted order financial attributes cannot change' USING ERRCODE = '23514';
        END IF;
        RETURN NEW;
      END;
      $$;
      CREATE TRIGGER ledger_order_guard BEFORE UPDATE ON orders
      FOR EACH ROW EXECUTE FUNCTION ledger_guard_order();
    SQL
  end

  def down
    execute <<~SQL
      DROP TRIGGER ledger_order_guard ON orders;
      DROP FUNCTION ledger_guard_order();
      DROP TRIGGER ledger_order_lock ON account_transactions;
      DROP FUNCTION ledger_lock_order();
    SQL
  end
end
