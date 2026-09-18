# frozen_string_literal: true

RSpec.describe S1::Subject do
  let(:stub) { S1::Providers::Stub.new(noul: 0.9) }

  before { S1.config.provider = stub }

  it "rejects a nil state" do
    expect { described_class.new(nil) }.to raise_error(S1::ValidationError, /nil/)
  end

  it "exposes the state and options" do
    state = described_class.new({ transcript: "hi" }, owner: "firm-1")
    expect(state.state).to eq(transcript: "hi")
    expect(state.options).to eq(owner: "firm-1")
    expect(state.options).to be_frozen
  end

  describe "#noul" do
    it "returns an Answer::Noul with id :noul" do
      answer = described_class.new("text").noul("Is it?")
      expect(answer).to be_a(S1::Answer::Noul)
      expect(answer.id).to eq(:noul)
      expect(answer.to_f).to eq(0.9)
    end

    it "sends clarification as criteria" do
      captured = nil
      S1.on_result { |_result, request| captured = request }
      described_class.new("text").noul("Before?", true: "ticket", false: "none")
      expect(captured.questions[:noul].criteria).to eq("true" => "ticket", "false" => "none")
    end
  end

  describe "#noul?" do
    it "phrases #is / #is? as a question" do
      asked = nil
      S1.config.provider = S1::Providers::Stub.new { |req| asked = req.questions[:noul].instructions and { noul: 0.9 } }
      expect(described_class.new("Michael").is?("a man's name")).to be(true)
      expect(asked).to eq("Is this a man's name?")
      expect(described_class.new("Michael").is("a man's name").to_f).to eq(0.9)
    end

    it "asks whether two states describe the same thing with #same_as?" do
      seen = nil
      S1.config.provider = S1::Providers::Stub.new { |req| seen = req and { noul: 0.95 } }
      expect(described_class.new("Acme Inc", owner: :me).same_as?("ACME, Incorporated")).to be(true)
      expect(seen.state).to eq(this: "Acme Inc", other: "ACME, Incorporated")
      expect(seen.options[:owner]).to eq(:me)
      expect(described_class.new("Acme Inc").same_as?("Acme", threshold: 0.99)).to be(false)
      expect(described_class.new("Acme Inc").same_as("Acme").to_f).to eq(0.95)
    end

    it "matches semantically with ===, and only there" do
      S1.config.provider = S1::Providers::Stub.new { |req| { noul: req.state[:other].start_with?("ACME") ? 0.95 : 0.05 } }
      acme = described_class.new("Acme Inc")
      candidate = "ACME, Incorporated"
      matched = case candidate
                when acme then :same
                else :different
                end
      expect(matched).to eq(:same)
      expect(["ACME Corp", "Beaver Dam"].grep(acme)).to eq(["ACME Corp"])
      expect(acme == "ACME, Incorporated").to be(false)
      expect([acme, acme].uniq.size).to eq(1)
    end

    it "judges against context with #given" do
      seen = nil
      S1.config.provider = S1::Providers::Stub.new { |req| seen = req and { noul: 0.9 } }
      expect(described_class.new("call", owner: :me).given(prefs: { min: 2 }).is?("qualified per `prefs`")).to be(true)
      expect(seen.state).to eq(this: "call", prefs: { min: 2 })
      expect(seen.questions[:noul].instructions).to eq("Is this qualified per `prefs`?")
      expect(seen.options[:owner]).to eq(:me)
      expect(described_class.new("call").against(prefs: 1).state).to eq(this: "call", prefs: 1)
    end

    it "batches under #batch too" do
      S1.config.provider = S1::Providers::Stub.new(e: 0.9)
      expect(described_class.new("x").batch { |q| q.noul :e, "q?" }.true?(:e)).to be(true)
      expect(described_class.new("x").ask_about { |q| q.noul :e, "q?" }.true?(:e)).to be(true)
      expect(described_class.new("x").measure { |q| q.noul :e, "q?" }.true?(:e)).to be(true)
    end

    it "is also #ask? and #judge?, and #noul is #judge" do
      S1.config.provider = S1::Providers::Stub.new(noul: 0.8)
      expect(described_class.new("x").ask?("q?")).to be(true)
      expect(described_class.new("x").judge?("q?")).to be(true)
      expect(described_class.new("x").judge("q?").to_f).to eq(0.8)
    end

    it "takes a per-call threshold" do
      S1.config.provider = S1::Providers::Stub.new(noul: 0.8)
      expect(described_class.new("x").noul?("q?", threshold: 0.9)).to be(false)
      expect(described_class.new("x").noul?("q?", threshold: 0.7)).to be(true)
    end

    it "thresholds at the global threshold" do
      expect(described_class.new("text").noul?("Is it?")).to be(true)
      S1.config.threshold = 0.95
      expect(described_class.new("text").noul?("Is it?")).to be(false)
    end

    it "thresholds at a per-Subject override" do
      expect(described_class.new("text", threshold: 0.95).noul?("Is it?")).to be(false)
      expect(described_class.new("text", threshold: 0.5).noul?("Is it?")).to be(true)
      expect(described_class.new("text", threshold: 0.95).threshold).to eq(0.95)
      expect(described_class.new("text").threshold).to eq(0.5)
    end
  end

  describe "the rule: a verb measures, a noun collapses" do
    before { S1.config.provider = S1::Providers::Stub.new(noul: 0.9, choice: :b, score: 2) }

    let(:subject_) { described_class.new("x") }

    it "judge → Noul, judge? → boolean" do
      expect(subject_.judge("q?")).to be_a(S1::Answer::Noul)
      expect(subject_.judge?("q?")).to be(true)
    end

    it "choose → Choice, choice → the option" do
      expect(subject_.choose("q?", a: "1", b: "2")).to be_a(S1::Answer::Choice)
      expect(subject_.choice("q?", a: "1", b: "2")).to eq(:b)
    end

    it "score → Score, level → the level, an S1::Level" do
      expect(subject_.score("q?", "low", "mid", "high")).to be_a(S1::Answer::Score)
      expect(subject_.level("q?", "low", "mid", "high")).to eq("high")
      expect(subject_.level("q?", "low", "mid", "high")).to be_a(S1::Level)
    end

    it "holds as the identity: the noun is the verb, collapsed" do
      expect(subject_.judge?("q?")).to eq(subject_.judge("q?").collapse)
      expect(subject_.judge?("q?", threshold: 0.95)).to eq(subject_.judge("q?").collapse(0.95))
      expect(subject_.choice("q?", a: "1", b: "2")).to eq(subject_.choose("q?", a: "1", b: "2").collapse)
      expect(subject_.level("q?", "low", "mid", "high")).to eq(subject_.score("q?", "low", "mid", "high").collapse)
    end

    it "holds for predicates: measure gives the verb's collapsable, the noun's value" do
      p = S1.predicates
      expect(p.choose("q?", a: "1", b: "2").measure("x")).to be_a(S1::Answer::Choice)
      expect(p.choice("q?", a: "1", b: "2").measure("x")).to eq(:b)
      expect(p.level("q?", "low", "mid", "high").measure("x")).to eq("high")
      expect(%w[x].map(&p.choose("q?", a: "1", b: "2"))).to eq([:b]) # through Enumerable both collapse
    end
  end

  describe "#choice" do
    it "takes choices: as criteria, including a bare list of options" do
      S1.config.provider = S1::Providers::Stub.new(choice: :b, pick: :a)
      expect(described_class.new("x").choose("q?", choices: { a: "1", b: "2" }).to_sym).to eq(:b)
      expect(described_class.new("x").choose("q?", choices: %w[a b]).probabilities.keys).to eq(%w[a b])
      expect(described_class.new("x").ask { |q| q.choose :pick, "q?", choices: %w[a b] }[:pick].to_sym).to eq(:a)
      expect { described_class.new("x").choose("q?", choices: [{ name: "a" }, { name: "b" }]) }.to raise_error(S1::ValidationError)
    end

    it "uses the state as the options when it is options-shaped and none are given" do
      S1.config.provider = S1::Providers::Stub.new(choice: :bob)
      expect(described_class.new({ "ann" => "a farmer", "bob" => "a pilot" }).choose("Who flies?").probabilities.keys).to eq(%w[ann bob])
      expect(described_class.new(%w[ann bob]).choose("Who flies?").to_sym).to eq(:bob)
      expect do
        described_class.new({ transcript: "hi", case: { a: 1 } }).choose("Which?")
      end.to raise_error(S1::ValidationError, /at least 2/)
      expect { described_class.new("just text").choose("Which?") }.to raise_error(S1::ValidationError, /at least 2/)
    end

    it "is also #choose, in Subject and in the batch builder" do
      S1.config.provider = S1::Providers::Stub.new(choice: :b, pick: :a)
      expect(described_class.new("x").choose("q?", a: "1", b: "2").to_sym).to eq(:b)
      expect(described_class.new("x").ask { |q| q.choose :pick, "q?", a: "1", b: "2" }[:pick].to_sym).to eq(:a)
      expect(described_class.new("x").measure { |q| q.judge :e, "q?" }[:e]).to be_a(S1::Answer::Noul)
    end

    it "returns an Answer::Choice" do
      S1.config.provider = S1::Providers::Stub.new(choice: :billing)
      answer = described_class.new("text").choose("Which?", returns: "R", billing: "B")
      expect(answer).to be_a(S1::Answer::Choice)
      expect(answer.id).to eq(:choice)
      expect(answer.to_sym).to eq(:billing)
      expect(answer.probabilities.keys).to eq(%w[returns billing])
    end
  end

  describe "#score" do
    it "returns an Answer::Score" do
      S1.config.provider = S1::Providers::Stub.new(score: 2)
      answer = described_class.new("text").score("How?", "low", "mid", "high")
      expect(answer).to be_a(S1::Answer::Score)
      expect(answer.id).to eq(:score)
      expect(answer.level).to eq("high")
      expect(answer.levels).to eq(%w[low mid high])
    end
  end

  describe "#ask" do
    let(:state) { described_class.new("text") }

    it "accepts a block" do
      result = state.ask do |q|
        q.noul :a, "A?"
        q.choice :b, "B?", x: "X", y: "Y"
      end
      expect(result).to be_a(S1::Result)
      expect(result.answers.keys).to eq(%i[a b])
    end

    it "accepts a Questions" do
      questions = S1::Questions.new
      questions.noul(:a, "A?")
      expect(state.ask(questions).answers.keys).to eq([:a])
    end

    it "accepts a Hash of Question" do
      result = state.ask("a" => S1::Question::Noul.new(instructions: "A?"))
      expect(result[:a]).to be_a(S1::Answer::Noul)
    end

    it "raises without questions" do
      expect { state.ask }.to raise_error(S1::ValidationError, /no questions/)
    end

    it "rides extra options along on the Request" do
      captured = nil
      S1.on_result { |_result, request| captured = request }
      described_class.new("text", owner: "firm-1", trace: 7).ask { |q| q.noul(:a, "A?") }
      expect(captured.options).to eq(owner: "firm-1", trace: 7)
    end
  end

  describe "per-Subject overrides" do
    it "uses provider: over the config" do
      other = S1::Providers::Stub.new(noul: 0.1)
      expect(described_class.new("text", provider: other).noul("Is it?").to_f).to eq(0.1)
      expect(described_class.new("text", provider: :stub).noul("Is it?").to_f).to eq(0.5)
    end

    it "uses model: and timeout: over the config" do
      captured = nil
      S1.on_result { |_result, request| captured = request }

      described_class.new("text").noul("Is it?")
      expect(captured.model).to be_nil
      expect(captured.timeout).to eq(30)

      described_class.new("text", model: "jev-2026", timeout: 3).noul("Is it?")
      expect(captured.model).to eq("jev-2026")
      expect(captured.timeout).to eq(3)
    end
  end
end
