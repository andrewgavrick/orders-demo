# frozen_string_literal: true

class AllowOpeningBalances < ActiveRecord::Migration[8.1]
  def up
    remove_check_constraint :account_transactions, name: "account_transactions_valid_kind"
    remove_check_constraint :account_transactions, name: "account_transactions_reversal_consistency"
    change_column_null :account_transactions, :order_id, true
    add_check_constraint :account_transactions,
      "kind IN ('charge', 'reversal', 'opening_balance')", name: "account_transactions_valid_kind"
    add_check_constraint :account_transactions, <<~SQL.squish, name: "account_transactions_reversal_consistency"
      (kind IN ('charge', 'opening_balance') AND reversal_of_id IS NULL)
      OR (kind = 'reversal' AND reversal_of_id IS NOT NULL)
    SQL
    add_check_constraint :account_transactions, <<~SQL.squish, name: "account_transactions_order_consistency"
      (kind = 'opening_balance' AND order_id IS NULL)
      OR (kind IN ('charge', 'reversal') AND order_id IS NOT NULL)
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Opening balances are immutable ledger history"
  end
end
