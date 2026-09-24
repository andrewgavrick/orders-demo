# frozen_string_literal: true

class ValidateOrderLedger < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE FUNCTION ledger_validate_order() RETURNS trigger LANGUAGE plpgsql AS $$
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
      CREATE CONSTRAINT TRIGGER ledger_commit AFTER INSERT OR UPDATE ON orders
      DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION ledger_validate_order();
      CREATE CONSTRAINT TRIGGER ledger_order_commit AFTER INSERT OR UPDATE ON account_transactions
      DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION ledger_validate_order();
    SQL
  end

  def down
    execute <<~SQL
      DROP TRIGGER ledger_order_commit ON account_transactions;
      DROP TRIGGER ledger_commit ON orders;
      DROP FUNCTION ledger_validate_order();
    SQL
  end
end
