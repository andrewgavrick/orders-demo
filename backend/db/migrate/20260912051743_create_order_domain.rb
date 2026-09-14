class CreateOrderDomain < ActiveRecord::Migration[8.1]
  def change
    create_table :actors do |t|
      t.string :kind, null: false
      t.string :name, null: false

      t.timestamps
    end

    create_table :accounts do |t|
      t.references :actor, null: false, foreign_key: true

      t.string :account_type, null: false
      t.string :purpose, null: false
      t.string :currency, null: false, limit: 3

      t.timestamps
    end

    create_table :orders do |t|
      t.references :buyer,
                   null: false,
                   foreign_key: { to_table: :actors }

      t.references :seller,
                   null: false,
                   foreign_key: { to_table: :actors }

      t.bigint :amount_minor, null: false
      t.string :currency, null: false, limit: 3
      t.string :status, null: false, default: "created"

      t.timestamps
    end

    create_table :account_transactions do |t|
      t.references :order, null: false, foreign_key: true

      t.string :kind, null: false

      t.references :reversal_of,
                   foreign_key: { to_table: :account_transactions },
                   index: { unique: true }

      t.datetime :created_at, null: false
    end

    create_table :entries do |t|
      t.references :account, null: false, foreign_key: true
      t.references :account_transaction, null: false, foreign_key: true

      t.string :direction, null: false
      t.bigint :amount_minor, null: false

      t.datetime :created_at, null: false
    end

    # Actors
    add_check_constraint :actors,
                         "kind IN ('user', 'system')",
                         name: "actors_valid_kind"

    # Accounts
    add_check_constraint :accounts,
                         "account_type IN ('asset', 'liability', 'equity', 'revenue', 'expense')",
                         name: "accounts_valid_account_type"

    add_check_constraint :accounts,
                         "currency ~ '^[A-Z]{3}$'",
                         name: "accounts_currency_format"

    add_index :accounts,
              %i[actor_id purpose currency],
              unique: true,
              name: "index_accounts_on_actor_purpose_currency"

    # Orders
    add_check_constraint :orders,
                         "amount_minor > 0",
                         name: "orders_positive_amount"

    add_check_constraint :orders,
                         "status IN ('created', 'successful', 'cancelled')",
                         name: "orders_valid_status"

    add_check_constraint :orders,
                         "currency ~ '^[A-Z]{3}$'",
                         name: "orders_currency_format"

    # Account transactions
    add_check_constraint :account_transactions,
                         "kind IN ('charge', 'reversal')",
                         name: "account_transactions_valid_kind"

    add_check_constraint :account_transactions,
                         <<~SQL.squish,
                           (
                             kind = 'charge' AND reversal_of_id IS NULL
                           )
                           OR
                           (
                             kind = 'reversal' AND reversal_of_id IS NOT NULL
                           )
                         SQL
                         name: "account_transactions_reversal_consistency"

    add_index :account_transactions,
              :order_id,
              unique: true,
              where: "kind = 'charge'",
              name: "index_unique_charge_per_order"

    # Entries
    add_check_constraint :entries,
                         "amount_minor > 0",
                         name: "entries_positive_amount"

    add_check_constraint :entries,
                         "direction IN ('debit', 'credit')",
                         name: "entries_valid_direction"
  end
end
