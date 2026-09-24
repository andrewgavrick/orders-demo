# frozen_string_literal: true

class MoveLedgerRulesToServices < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      DROP TRIGGER ledger_commit ON account_transactions;
      DROP TRIGGER ledger_transaction_guard ON account_transactions;
      DROP TRIGGER ledger_entry_guard ON entries;
      DROP TRIGGER ledger_account_guard ON accounts;
      DROP TRIGGER ledger_order_lock ON account_transactions;
      DROP TRIGGER ledger_order_guard ON orders;
      DROP TRIGGER ledger_commit ON orders;
      DROP TRIGGER ledger_order_commit ON account_transactions;
      DROP FUNCTION ledger_validate();
      DROP FUNCTION ledger_guard_transaction();
      DROP FUNCTION ledger_guard_entry();
      DROP FUNCTION ledger_guard_account();
      DROP FUNCTION ledger_lock_order();
      DROP FUNCTION ledger_guard_order();
      DROP FUNCTION ledger_validate_order();
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Restore the previous application and schema together to restore database posting rules"
  end
end
