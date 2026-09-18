# frozen_string_literal: true

RSpec.describe S1::Providers::Stub do
  let(:questions) do
    S1::Questions.coerce do |q|
      q.noul :escalate, "Human?"
      q.choice :department, "Which?", returns: "R", billing: "B", shipping: "S"
      q.score :severity, "How?", "Cosmetic", "Degraded", "Blocking"
    end
  end
  let(:request) { S1::Request.new(state: "text", questions: questions, model: "m") }

  it "names itself" do
    expect(described_class.new.name).to eq(:stub)
  end

  it "returns a Result with model stub, provider :stub and zero usage" do
    result = described_class.new.call(request)
    expect(result).to be_a(S1::Result)
    expect(result.model).to eq("stub")
    expect(result.provider).to eq(:stub)
    expect(result.usage).to eq(input_tokens: 0, output_tokens: 0)
    expect(result.input_tokens).to eq(0)
    expect(result.answers.keys).to eq(%i[escalate department severity])
  end

  describe "neutral defaults" do
    let(:result) { described_class.new.call(request) }

    it "answers a noul at 0.5" do
      expect(result[:escalate].to_f).to eq(0.5)
    end

    it "picks the first option at 1.0" do
      choice = result[:department]
      expect(choice.to_sym).to eq(:returns)
      expect(choice.probabilities).to eq("returns" => 1.0, "billing" => 0.0, "shipping" => 0.0)
      expect(choice.confidence).to eq(1.0)
    end

    it "picks the first level at 1.0" do
      score = result[:severity]
      expect(score.index).to eq(0)
      expect(score.level).to eq("Cosmetic")
      expect(score.to_f).to eq(0.0)
      expect(score.levels).to eq(%w[Cosmetic Degraded Blocking])
      expect(score.probabilities).to eq("0" => 1.0, "1" => 0.0, "2" => 0.0)
      expect(score.confidence).to eq(1.0)
    end
  end

  describe "shorthand values" do
    it "takes a float for a noul" do
      result = described_class.new("escalate" => 0.9).call(request)
      expect(result[:escalate].to_f).to eq(0.9)
      expect(result[:escalate].probabilities["false"]).to be_within(1e-9).of(0.1)
    end

    it "takes a symbol or string for a choice" do
      expect(described_class.new(department: :billing).call(request)[:department].to_s).to eq("billing")
      shipping = described_class.new(department: "shipping").call(request)[:department]
      expect(shipping.to_sym).to eq(:shipping)
      expect(shipping[:shipping]).to eq(1.0)
      expect(shipping[:returns]).to eq(0.0)
    end

    it "takes an integer index for a score" do
      score = described_class.new(severity: 2).call(request)[:severity]
      expect(score.index).to eq(2)
      expect(score.level).to eq("Blocking")
      expect(score.to_f).to eq(2.0)
      expect(score.probabilities).to eq("0" => 0.0, "1" => 0.0, "2" => 1.0)
    end
  end

  describe "full-hash values" do
    it "passes noul fields through" do
      result = described_class.new(escalate: { "probability" => 0.33 }).call(request)
      expect(result[:escalate].to_f).to eq(0.33)
    end

    it "passes choice fields through" do
      choice = described_class.new(
        department: { choice: :billing, probabilities: { returns: 0.2, billing: 0.7, shipping: 0.1 }, confidence: 0.7 }
      ).call(request)[:department]
      expect(choice.to_sym).to eq(:billing)
      expect(choice[:billing]).to eq(0.7)
      expect(choice.confidence).to eq(0.7)
    end

    it "passes score fields through" do
      score = described_class.new(
        severity: { score: 1.4, legend: { 0 => "a", 1 => "b", 2 => "c" },
                    probabilities: { "0" => 0.1, "1" => 0.4, "2" => 0.5 }, confidence: 0.5 }
      ).call(request)[:severity]
      expect(score.to_f).to eq(1.4)
      expect(score.index).to eq(2)
      expect(score.level).to eq("c")
      expect(score.confidence).to eq(0.5)
    end
  end

  describe "block form" do
    it "receives the Request and its map wins over canned answers" do
      seen = nil
      stub = described_class.new(escalate: 0.1) do |req|
        seen = req
        { escalate: 0.8, department: :shipping }
      end

      result = stub.call(request)

      expect(seen).to be(request)
      expect(result[:escalate].to_f).to eq(0.8)
      expect(result[:department].to_sym).to eq(:shipping)
      expect(result[:severity].index).to eq(0)
    end

    it "tolerates a block returning nil" do
      result = described_class.new(escalate: 0.1) { nil }.call(request)
      expect(result[:escalate].to_f).to eq(0.1)
    end
  end
end
