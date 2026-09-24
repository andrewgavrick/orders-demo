# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_09_29_000000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "account_transactions", comment: "Journals posted atomically by Ledger::Post", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "kind", null: false, comment: "charge, reversal or opening_balance"
    t.bigint "order_id", comment: "Absent only for opening balances"
    t.datetime "posted_at", comment: "Only posted journals contribute to balances; null means draft"
    t.bigint "reversal_of_id", comment: "Original charge reversed by this journal; at most one full reversal"
    t.index ["order_id"], name: "index_account_transactions_on_order_id"
    t.index ["order_id"], name: "index_unique_charge_per_order", unique: true, where: "((kind)::text = 'charge'::text)"
    t.index ["reversal_of_id"], name: "index_account_transactions_on_reversal_of_id", unique: true
    t.check_constraint "(kind::text = ANY (ARRAY['charge'::character varying, 'opening_balance'::character varying]::text[])) AND reversal_of_id IS NULL OR kind::text = 'reversal'::text AND reversal_of_id IS NOT NULL", name: "account_transactions_reversal_consistency"
    t.check_constraint "kind::text = 'opening_balance'::text AND order_id IS NULL OR (kind::text = ANY (ARRAY['charge'::character varying, 'reversal'::character varying]::text[])) AND order_id IS NOT NULL", name: "account_transactions_order_consistency"
    t.check_constraint "kind::text = ANY (ARRAY['charge'::character varying, 'reversal'::character varying, 'opening_balance'::character varying]::text[])", name: "account_transactions_valid_kind"
  end

  create_table "accounts", comment: "Ledger accounts; balances are calculated from posted entries", force: :cascade do |t|
    t.string "account_type", null: false, comment: "Determines balance sign: asset/expense are debit-normal, other types credit-normal"
    t.bigint "actor_id", null: false
    t.datetime "created_at", null: false
    t.string "currency", limit: 3, null: false, comment: "Three uppercase currency letters; postings balance separately per currency"
    t.string "purpose", null: false, comment: "wallet for user funds; settlement for initial funding"
    t.datetime "updated_at", null: false
    t.index ["actor_id", "purpose", "currency"], name: "index_accounts_on_actor_purpose_currency", unique: true
    t.index ["actor_id"], name: "index_accounts_on_actor_id"
    t.check_constraint "account_type::text = ANY (ARRAY['asset'::character varying, 'liability'::character varying, 'equity'::character varying, 'revenue'::character varying, 'expense'::character varying]::text[])", name: "accounts_valid_account_type"
    t.check_constraint "currency::text ~ '^[A-Z]{3}$'::text", name: "accounts_currency_format"
    t.check_constraint "purpose::text <> 'wallet'::text OR account_type::text = 'liability'::text", name: "wallets_are_liabilities"
  end

  create_table "actors", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "kind", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.check_constraint "kind::text = ANY (ARRAY['user'::character varying, 'system'::character varying]::text[])", name: "actors_valid_kind"
  end

  create_table "entries", comment: "Debit or credit lines; posted history is reversed with new entries", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "account_transaction_id", null: false
    t.bigint "amount_minor", null: false, comment: "Positive minor units in the referenced account's currency"
    t.datetime "created_at", null: false
    t.string "direction", null: false
    t.index ["account_id"], name: "index_entries_on_account_id"
    t.index ["account_transaction_id"], name: "index_entries_on_account_transaction_id"
    t.check_constraint "amount_minor > 0", name: "entries_positive_amount"
    t.check_constraint "direction::text = ANY (ARRAY['debit'::character varying, 'credit'::character varying]::text[])", name: "entries_valid_direction"
  end

  create_table "orders", force: :cascade do |t|
    t.bigint "amount_minor", null: false, comment: "Positive integer in currency minor units, e.g. USD cents"
    t.bigint "buyer_id", null: false
    t.datetime "created_at", null: false
    t.string "currency", limit: 3, null: false
    t.bigint "seller_id", null: false
    t.string "status", default: "created", null: false, comment: "created, successful or cancelled; transitions run through order services"
    t.datetime "updated_at", null: false
    t.index ["buyer_id"], name: "index_orders_on_buyer_id"
    t.index ["seller_id"], name: "index_orders_on_seller_id"
    t.check_constraint "amount_minor > 0", name: "orders_positive_amount"
    t.check_constraint "currency::text ~ '^[A-Z]{3}$'::text", name: "orders_currency_format"
    t.check_constraint "status::text = ANY (ARRAY['created'::character varying, 'successful'::character varying, 'cancelled'::character varying]::text[])", name: "orders_valid_status"
  end

  add_foreign_key "account_transactions", "account_transactions", column: "reversal_of_id"
  add_foreign_key "account_transactions", "orders"
  add_foreign_key "accounts", "actors"
  add_foreign_key "entries", "account_transactions"
  add_foreign_key "entries", "accounts"
  add_foreign_key "orders", "actors", column: "buyer_id"
  add_foreign_key "orders", "actors", column: "seller_id"
end
