# frozen_string_literal: true

require "spec_helper"
require_relative "../../app/services/base_service"

RSpec.describe BaseService do
  let(:service) do
    Class.new(described_class) do
      def call(value, factor:, &block)
        block.call(value * factor)
      end
    end
  end

  it "forwards positional arguments, keyword arguments and the block" do
    expect(service.call(3, factor: 2) { |value| value + 1 }).to eq(7)
  end
end
