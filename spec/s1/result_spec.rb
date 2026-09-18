# frozen_string_literal: true

RSpec.describe S1::Result do
  describe "#collapse" do
    it "collapses every answer at once" do
      S1.config.provider = S1::Providers::Stub.new(escalate: 0.9, department: :billing, severity: 2)
      result = S1::Subject.new("x").ask do |q|
        q.noul :escalate, "e?"
        q.choice :department, "d?", returns: "r", billing: "b"
        q.score :severity, "s?", "low", "mid", "high"
      end
      expect(result.collapse).to eq(escalate: true, department: :billing, severity: 2)
      expect(result.collapse[:severity]).to be_a(S1::Level)
      expect(result.collapse[:severity]).to eq("high")
      expect(result.collapse(0.95)[:escalate]).to be(false)
    end

    it "is also #to_h" do
      S1.config.provider = S1::Providers::Stub.new(escalate: 0.9, severity: 2)
      result = S1::Subject.new("x").ask do |q|
        q.noul :escalate, "e?"
        q.score :severity, "s?", "low", "mid", "high"
      end
      expect(result.to_h).to eq(result.collapse)
      expect(result.to_h).to eq(escalate: true, severity: "high")
    end
  end

  describe "pattern matching" do
    it "deconstructs nouls to booleans, choices to symbols, scores to Levels" do
      S1.config.provider = S1::Providers::Stub.new(escalate: 0.9, department: :billing, severity: 2)
      result = S1::Subject.new("x").ask do |q|
        q.noul :escalate, "e?"
        q.choice :department, "d?", returns: "r", billing: "b"
        q.score :severity, "s?", "low", "mid", "high"
      end
      matched = case result
                in { escalate: true, severity: 2.., department: }
                  department
                end
      expect(matched).to eq(:billing)
      expect(result.deconstruct_keys(nil)).to eq(result.collapse)
      expect(result.deconstruct_keys([:severity])).to eq(severity: "high")
    end

    it "matches a score against an integer range or a label" do
      S1.config.provider = S1::Providers::Stub.new(severity: 2)
      result = S1::Subject.new("x").ask { |q| q.score :severity, "s?", "low", "mid", "high" }
      expect((result in { severity: 2.. })).to be(true)
      expect((result in { severity: 1..1 })).to be(false)
      expect((result in { severity: "high" })).to be(true)
      expect((result in { severity: "low" })).to be(false)
    end
  end

  let(:noul) { S1::Answer::Noul.new(id: :escalate, probability: 0.9) }
  let(:choice) do
    S1::Answer::Choice.new(id: :department, choice: "billing", probabilities: { "billing" => 1.0 },
                           confidence: 1.0)
  end
  let(:score) do
    S1::Answer::Score.new(id: :severity, score: 2.0, legend: { 0 => "low", 1 => "mid", 2 => "high" },
                          probabilities: { "2" => 1.0 }, confidence: 1.0)
  end
  let(:result) do
    described_class.new(answers: { "escalate" => noul, department: choice, severity: score },
                        usage: { "input_tokens" => 490, "output_tokens" => 86 }, model: "jev-latest",
                        provider: :jev, raw: { "answers" => {} })
  end

  it "is frozen with symbolized keys" do
    expect(result).to be_frozen
    expect(result.answers).to be_frozen
    expect(result.answers.keys).to eq(%i[escalate department severity])
    expect(result.usage).to eq(input_tokens: 490, output_tokens: 86)
    expect(result.model).to eq("jev-latest")
    expect(result.provider).to eq(:jev)
    expect(result.raw).to eq("answers" => {})
    expect(result.duration_ms).to be_nil
  end

  describe "#[]" do
    it "looks up by symbol or string" do
      expect(result[:escalate]).to be(noul)
      expect(result["department"]).to be(choice)
    end

    it "raises a KeyError naming the known ids" do
      expect { result[:missing] }
        .to raise_error(KeyError, "no answer for :missing (have [:escalate, :department, :severity])")
    end
  end

  it "thresholds a noul by id with #true?" do
    expect(result.true?(:escalate)).to be(true)
    expect(result.true?("escalate", 0.95)).to be(false)
    expect { result.true?(:department) }.to raise_error(S1::ValidationError, /not a noul/)
  end

  it "answers #key? by symbol or string" do
    expect(result.key?(:severity)).to be(true)
    expect(result.key?("severity")).to be(true)
    expect(result.key?(:nope)).to be(false)
  end

  it "partitions answers by type" do
    expect(result.nouls).to eq(escalate: noul)
    expect(result.choices).to eq(department: choice)
    expect(result.scores).to eq(severity: score)
  end

  it "reads token usage" do
    expect(result.input_tokens).to eq(490)
    expect(result.output_tokens).to eq(86)
    expect(described_class.new(answers: {}).input_tokens).to eq(0)
    expect(described_class.new(answers: {}, usage: nil).output_tokens).to eq(0)
  end

  it "enumerates id/answer pairs" do
    expect(result.size).to eq(3)
    expect(result.map { |id, answer| [id, answer.class] })
      .to eq([[:escalate, S1::Answer::Noul], [:department, S1::Answer::Choice],
              [:severity, S1::Answer::Score]])
    expect(result.to_a.map(&:first)).to eq(%i[escalate department severity])
  end

  describe "#with" do
    it "returns a new Result with the change and everything else preserved" do
      timed = result.with(duration_ms: 398)

      expect(timed).not_to be(result)
      expect(timed).to be_a(described_class)
      expect(timed.duration_ms).to eq(398)
      expect(result.duration_ms).to be_nil
      expect(timed.answers).to eq(result.answers)
      expect(timed.usage).to eq(result.usage)
      expect(timed.model).to eq("jev-latest")
      expect(timed.provider).to eq(:jev)
      expect(timed.raw).to eq(result.raw)
    end
  end
end

RSpec.describe S1::Request do
  let(:questions) { { q: S1::Question::Noul.new(instructions: "Q?") } }

  it "defaults model, timeout and options" do
    request = described_class.new(state: "hello", questions: questions)
    expect(request.state).to eq("hello")
    expect(request.questions).to eq(questions)
    expect(request.model).to be_nil
    expect(request.timeout).to be_nil
    expect(request.options).to eq({})
    expect(request.options).to be_frozen
  end

  it "freezes the options it is given" do
    options = { owner: "firm-1" }
    request = described_class.new(state: "hello", questions: questions, model: "m", timeout: 5, options: options)
    expect(request.options).to be_frozen
    expect(request.options).to eq(owner: "firm-1")
    expect(request.model).to eq("m")
    expect(request.timeout).to eq(5)
  end
end
