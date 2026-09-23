# frozen_string_literal: true

module DatabaseConstraintHelpers
  def rejected(error = ActiveRecord::StatementInvalid, &block)
    expect { ApplicationRecord.transaction(requires_new: true, &block) }.to raise_error(error)
  end
end

RSpec.configure { |config| config.include DatabaseConstraintHelpers, database_constraints: true }
