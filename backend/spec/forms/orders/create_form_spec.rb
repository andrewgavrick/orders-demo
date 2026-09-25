# frozen_string_literal: true

require "spec_helper"
require "active_model"
require_relative "../../../app/forms/orders/create_form"

RSpec.describe Orders::CreateForm do
  subject(:form) { described_class.new(attributes) }

  let(:attributes) { { seller_id: 1, amount_minor: 250, currency: "USD" } }

  it { is_expected.to be_valid }

  it "preserves JSON scalar types" do
    expect(form.attributes.symbolize_keys).to eq(attributes)
  end

  { seller_id: [ "1", 1.5, [], {} ], amount_minor: [ "250", 1.5, [], {} ],
    currency: [ 1, [], {}, nil ] }.each do |attribute, values|
    values.each do |value|
      context "when #{attribute} is #{value.inspect}" do
        let(:attributes) { super().merge(attribute => value) }

        it { is_expected.not_to be_valid }
      end
    end
  end
end
