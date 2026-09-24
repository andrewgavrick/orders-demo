# frozen_string_literal: true

class DocumentFinancialColumns < ActiveRecord::Migration[8.1]
  def change
    change_table_comment :accounts, from: nil, to: "Ledger accounts; balances are calculated from posted entries"
    change_table_comment :account_transactions, from: nil, to: "Journals posted atomically by Ledger::Post"
    change_table_comment :entries, from: nil, to: "Debit or credit lines; posted history is reversed with new entries"

    change_column_comment :orders, :amount_minor, from: nil, to: "Positive integer in currency minor units, e.g. USD cents"
    change_column_comment :orders, :status, from: nil, to: "created, successful or cancelled; transitions run through order services"
    change_column_comment :accounts, :account_type, from: nil, to: "Determines balance sign: asset/expense are debit-normal, other types credit-normal"
    change_column_comment :accounts, :purpose, from: nil, to: "wallet for user funds; settlement for initial funding"
    change_column_comment :accounts, :currency, from: nil, to: "Three uppercase currency letters; postings balance separately per currency"
    change_column_comment :account_transactions, :kind, from: nil, to: "charge, reversal or opening_balance"
    change_column_comment :account_transactions, :order_id, from: nil, to: "Absent only for opening balances"
    change_column_comment :account_transactions, :reversal_of_id, from: nil, to: "Original charge reversed by this journal; at most one full reversal"
    change_column_comment :account_transactions, :posted_at, from: nil, to: "Only posted journals contribute to balances; null means draft"
    change_column_comment :entries, :amount_minor, from: nil, to: "Positive minor units in the referenced account's currency"
  end
end
