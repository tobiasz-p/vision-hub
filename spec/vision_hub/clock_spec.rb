# frozen_string_literal: true

require "spec_helper"

RSpec.describe VisionHub::Clock do
  describe ".now" do
    subject(:now) { described_class.now }

    it "returns current monotonic time as a float" do
      expect(now).to be_a(Float)
      expect(now).to be > 0
    end
  end
end
