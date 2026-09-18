# frozen_string_literal: true

RSpec.describe S1::Answer do
  describe S1::Answer::Noul do
    let(:answer) { described_class.new(id: "escalate", probability: 0.94) }

    it "is frozen and symbolizes its id" do
      expect(answer).to be_frozen
      expect(answer.id).to eq(:escalate)
      expect(answer.type).to eq("noul")
      expect(answer.confidence).to be_nil
    end

    it "reads as a float" do
      expect(answer.to_f).to eq(0.94)
      expect(answer.probability).to eq(0.94)
      expect(described_class.new(id: :x, probability: "0.25").to_f).to eq(0.25)
    end

    it "thresholds at the configured default" do
      expect(answer.true?).to be(true)
      expect(answer.false?).to be(false)
      low = described_class.new(id: :x, probability: 0.3)
      expect(low.true?).to be(false)
      expect(low.false?).to be(true)
      expect(described_class.new(id: :x, probability: 0.5).true?).to be(true)
    end

    it "thresholds with an explicit value" do
      expect(answer.true?(0.95)).to be(false)
      expect(answer.false?(0.95)).to be(true)
      expect(answer.true?(0.9)).to be(true)
    end

    it "follows a changed global threshold" do
      S1.config.threshold = 0.95
      expect(answer.true?).to be(false)
    end

    it "compares against numbers in both directions" do
      expect(answer >= 0.85).to be(true)
      expect(answer > 0.94).to be(false)
      expect(answer).to eq(0.94)
      expect(0.85 <= answer).to be(true) # rubocop:disable Style/YodaCondition
      expect(0.99 > answer).to be(true) # rubocop:disable Style/YodaCondition
      expect(1 < answer).to be(false) # rubocop:disable Style/YodaCondition
    end

    it "sorts by probability" do
      a = described_class.new(id: :a, probability: 0.7)
      b = described_class.new(id: :b, probability: 0.2)
      c = described_class.new(id: :c, probability: 0.9)
      expect([a, b, c].sort.map(&:id)).to eq(%i[b a c])
      expect([a, b, c].max.id).to eq(:c)
      expect(a.between?(0.5, 0.8)).to be(true)
    end

    it "exposes a true/false distribution" do
      expect(answer.probabilities.keys).to eq(%w[true false])
      expect(answer.probabilities["true"]).to eq(0.94)
      expect(answer.probabilities["false"]).to be_within(1e-9).of(0.06)
      expect(answer.probabilities).to be_frozen
    end

    it "is a Collapsable, like every answer and a Result" do
      expect(described_class.new(id: :x, probability: 0.9)).to be_a(S1::Collapsable)
      expect(S1::Answer::Choice.new(id: :x, choice: "a", probabilities: { "a" => 1.0 }, confidence: 1.0)).to be_a(S1::Collapsable)
      expect(S1::Result.new(answers: {})).to be_a(S1::Collapsable)
      expect(S1::Result.new(answers: {}).collapse).to eq({})
    end

    describe "probability algebra and the named collapse" do
      let(:a) { described_class.new(id: :a, probability: 0.9) }
      let(:b) { described_class.new(id: :b, probability: 0.5) }

      it "combines independent nouls as both / either / not" do
        expect((a & b).to_f).to be_within(1e-9).of(0.45)
        expect((a | b).to_f).to be_within(1e-9).of(0.95)
        expect((~a).to_f).to be_within(1e-9).of(0.1)
        expect((a & b).id).to eq(:"a&b")
        expect(a & b).to be_a(described_class)
        expect((a & b) >= 0.4).to be(true)
      end

      it "collapses through !! (and negates through !), but stays truthy to a bare if" do
        expect(!!a).to be(true) # rubocop:disable Style/DoubleNegation
        expect(!a).to be(false)
        expect(!!described_class.new(id: :x, probability: 0.2)).to be(false) # rubocop:disable Style/DoubleNegation
        expect(a ? :truthy : :falsy).to eq(:truthy) # the trap: no `!` involved
      end

      it "collapses to a boolean at a threshold, and knows when it is too close to call" do
        expect(a.collapse).to be(true)
        expect(b.collapse(0.6)).to be(false)
        expect(b.undecided?).to be(true)
        expect(a.undecided?).to be(false)
        expect(b.undecided?(0.01, threshold: 0.6)).to be(false)
      end

      it "routes with plain case/when on ranges" do
        route = case a
                when 0.85.. then :auto
                when 0.5...0.85 then :review
                else :reject
                end
        expect(route).to eq(:auto)
      end
    end

    describe "#confident?" do
      it "is true far from the fence on either side" do
        expect(described_class.new(id: :x, probability: 0.95).confident?(0.8)).to be(true)
        expect(described_class.new(id: :x, probability: 0.05).confident?(0.8)).to be(true)
      end

      it "is false near the fence" do
        expect(described_class.new(id: :x, probability: 0.55).confident?(0.8)).to be(false)
        expect(described_class.new(id: :x, probability: 0.45).confident?(0.8)).to be(false)
      end

      it "uses the configured threshold by default" do
        S1.config.threshold = 0.8
        expect(described_class.new(id: :x, probability: 0.6)).not_to be_confident
        expect(described_class.new(id: :x, probability: 0.85)).to be_confident
      end
    end
  end

  describe S1::Answer::Choice do
    let(:answer) do
      described_class.new(id: :department, choice: :billing,
                          probabilities: { returns: 0.1, "billing" => 0.85, shipping: 0.05 }, confidence: 0.85)
    end

    it "is frozen" do
      expect(answer).to be_frozen
      expect(answer.type).to eq("choice")
      expect(answer.confidence).to eq(0.85)
    end

    it "reads as a string or a symbol; the choice itself is the Symbol" do
      expect(answer.to_s).to eq("billing")
      expect(answer.to_sym).to eq(:billing)
      expect(answer.choice).to be(:billing)
      expect(answer.collapse).to be(:billing)
      expect(answer.collapse(0.9)).to be(:billing)
    end

    it "indexes probabilities by string or symbol" do
      expect(answer[:returns]).to eq(0.1)
      expect(answer["billing"]).to eq(0.85)
      expect(answer[:missing]).to be_nil
      expect(answer.probabilities.keys).to eq(%w[returns billing shipping])
    end

    it "equals a string or a symbol" do
      expect(answer == :billing).to be(true)
      expect(answer == "billing").to be(true)
      expect(answer == :returns).to be(false)
      expect(answer).to eq(described_class.new(id: :x, choice: "billing", probabilities: {}, confidence: nil))
    end

    it "routes on confidence" do
      expect(answer.confident?(0.8)).to be(true)
      expect(answer.confident?(0.9)).to be(false)
      expect(answer).to be_confident
      S1.config.threshold = 0.9
      expect(answer).not_to be_confident
    end

    it "ranks every option, most likely first" do
      answer = described_class.new(id: :x, choice: "b", probabilities: { "a" => 0.2, "b" => 0.7, "c" => 0.1 }, confidence: 0.7)
      expect(answer.ranked).to eq(%w[b a c])
    end

    it "is confident when confidence is unknown" do
      expect(described_class.new(id: :x, choice: "a", probabilities: {}, confidence: nil)).to be_confident
    end
  end

  describe S1::Answer::Score do
    let(:answer) do
      described_class.new(id: :severity, score: 1.68,
                          legend: { "0" => "Cosmetic", "1" => "Degraded", "2" => "Blocking" },
                          probabilities: { "0" => 0.05, "1" => 0.22, "2" => 0.73 }, confidence: 0.73)
    end

    it "is frozen" do
      expect(answer).to be_frozen
      expect(answer.type).to eq("score")
      expect(answer.legend).to be_frozen
    end

    it "reads as the weighted position" do
      expect(answer.to_f).to eq(1.68)
      expect(answer.score).to eq(1.68)
    end

    it "picks the most likely level" do
      expect(answer.index).to eq(2)
      expect(answer.level).to eq("Blocking")
    end

    it "collapses to a Level: the label, knowing its position" do
      level = answer.collapse
      expect(level).to be_a(S1::Level)
      expect(level).to eq("Blocking")
      expect(level.index).to eq(2)
      expect(level.scale).to eq(%w[Cosmetic Degraded Blocking])
      expect(answer.collapse(0.9)).to eq(level)
      expect(answer.level).to be_a(S1::Level)
      expect(answer.scale).to eq(%w[Cosmetic Degraded Blocking])
    end

    it "lists every level as a Level" do
      expect(answer.levels).to all(be_a(S1::Level))
      expect(answer.levels).to eq(%w[Cosmetic Degraded Blocking])
      expect(answer.levels.map(&:index)).to eq([0, 1, 2])
      expect(answer.levels.max).to eq("Blocking")
    end

    it "coerces legend keys to Integer" do
      expect(answer.legend).to eq(0 => "Cosmetic", 1 => "Degraded", 2 => "Blocking")
      sym = described_class.new(id: :x, score: 0, legend: { 1 => "b", :"0" => "a" },
                                probabilities: { 0 => 0.9, 1 => 0.1 }, confidence: 1)
      expect(sym.legend).to eq(1 => "b", 0 => "a")
      expect(sym.index).to eq(0)
      expect(sym.level).to eq("a")
    end

    it "orders levels regardless of legend order" do
      out_of_order = described_class.new(id: :x, score: 0, legend: { "2" => "c", "0" => "a", "1" => "b" },
                                         probabilities: { "1" => 1.0 }, confidence: 1)
      expect(out_of_order.levels).to eq(%w[a b c])
      expect(out_of_order.index).to eq(1)
      expect(out_of_order.level).to eq("b")
    end

    it "routes on confidence" do
      expect(answer.confident?(0.7)).to be(true)
      expect(answer.confident?(0.75)).to be(false)
      expect(answer).to be_confident
    end
  end
end
