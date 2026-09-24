# frozen_string_literal: true

class ProtectLedger < ActiveRecord::Migration[8.1]
  def up
    add_column :account_transactions, :posted_at, :datetime
    add_check_constraint :accounts, "purpose <> 'wallet' OR account_type = 'liability'", name: "wallets_are_liabilities"
    execute File.read(File.join(__dir__, "../sql/protect_ledger.sql"))
  end

  def down
    execute <<~SQL
      DROP TRIGGER ledger_commit ON account_transactions;
      DROP TRIGGER ledger_transaction_guard ON account_transactions;
      DROP TRIGGER ledger_entry_guard ON entries;
      DROP TRIGGER ledger_account_guard ON accounts;
      DROP FUNCTION ledger_validate();
      DROP FUNCTION ledger_guard_transaction();
      DROP FUNCTION ledger_guard_entry();
      DROP FUNCTION ledger_guard_account();
    SQL
    remove_check_constraint :accounts, name: "wallets_are_liabilities"
    remove_column :account_transactions, :posted_at
  end
end
