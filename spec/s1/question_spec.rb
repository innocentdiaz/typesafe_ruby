# frozen_string_literal: true

RSpec.describe S1::Question do
  describe S1::Question::Noul do
    it "reports its type" do
      expect(described_class.new(instructions: "Is it?").type).to eq("noul")
    end

    it "omits criteria from #to_h when not given" do
      q = described_class.new(instructions: "Is it?")
      expect(q.criteria).to be_nil
      expect(q.to_h).to eq(type: "noul", instructions: "Is it?")
    end

    it "treats empty criteria as omitted" do
      expect(described_class.new(instructions: "Is it?", criteria: {}).criteria).to be_nil
    end

    it "normalizes true:/false: criteria to string keys" do
      q = described_class.new(instructions: "Is it?", criteria: { true: "yes when", false: "no when" })
      expect(q.criteria).to eq("true" => "yes when", "false" => "no when")
      expect(q.to_h).to eq(type: "noul", instructions: "Is it?",
                           criteria: { "true" => "yes when", "false" => "no when" })
    end

    it "accepts a single side" do
      expect(described_class.new(instructions: "Is it?", criteria: { "true" => "yes when" }).criteria)
        .to eq("true" => "yes when")
    end

    it "rejects keys other than true/false" do
      expect { described_class.new(instructions: "Is it?", criteria: { true: "y", maybe: "m" }) }
        .to raise_error(S1::ValidationError, %r{true/false.*maybe})
    end
  end

  describe S1::Question::Choice do
    it "reports its type" do
      expect(described_class.new(instructions: "Which?", criteria: { a: "A", b: "B" }).type).to eq("choice")
    end

    it "stringifies option keys and exposes #options" do
      q = described_class.new(instructions: "Which?", criteria: { returns: "Refunds", billing: "Charges" })
      expect(q.criteria).to eq("returns" => "Refunds", "billing" => "Charges")
      expect(q.options).to eq(%w[returns billing])
      expect(q.to_h).to eq(type: "choice", instructions: "Which?",
                           criteria: { "returns" => "Refunds", "billing" => "Charges" })
    end

    it "allows nil descriptions" do
      q = described_class.new(instructions: "Which?", criteria: { a: nil, b: nil })
      expect(q.criteria).to eq("a" => nil, "b" => nil)
    end

    it "requires at least two options" do
      expect { described_class.new(instructions: "Which?", criteria: { only: "one" }) }
        .to raise_error(S1::ValidationError, /at least 2 options \(got 1\)/)
      expect { described_class.new(instructions: "Which?", criteria: nil) }
        .to raise_error(S1::ValidationError, /got 0/)
    end
  end

  describe S1::Question::Score do
    it "reports its type" do
      expect(described_class.new(instructions: "How?", criteria: %w[low high]).type).to eq("score")
    end

    it "keeps levels ordered and stringified" do
      q = described_class.new(instructions: "How?", criteria: [:low, "mid", 3])
      expect(q.criteria).to eq(%w[low mid 3])
      expect(q.levels).to eq(%w[low mid 3])
      expect(q.to_h).to eq(type: "score", instructions: "How?", criteria: %w[low mid 3])
    end

    it "requires at least two levels" do
      expect { described_class.new(instructions: "How?", criteria: ["only"]) }
        .to raise_error(S1::ValidationError, /at least 2 ordered levels \(got 1\)/)
      expect { described_class.new(instructions: "How?", criteria: nil) }
        .to raise_error(S1::ValidationError, /got 0/)
    end
  end

  describe "instructions" do
    it "strips String instructions" do
      expect(S1::Question::Noul.new(instructions: "  Is it?  \n").instructions).to eq("Is it?")
    end

    it "rejects blank Strings" do
      expect { S1::Question::Noul.new(instructions: "   ") }
        .to raise_error(S1::ValidationError, /blank/)
    end

    it "passes Hash instructions through untouched" do
      structured = { field: { name: "invoice_number" }, extracted_value: "4471", question: "Does it match?" }
      q = S1::Question::Noul.new(instructions: structured)
      expect(q.instructions).to equal(structured)
      expect(q.to_h[:instructions]).to eq(structured)
    end

    it "rejects other types" do
      expect { S1::Question::Noul.new(instructions: 42) }
        .to raise_error(S1::ValidationError, /String or a Hash \(got Integer\)/)
      expect { S1::Question::Noul.new(instructions: nil) }
        .to raise_error(S1::ValidationError, /got NilClass/)
    end
  end
end

RSpec.describe S1::Questions do
  subject(:questions) { described_class.new }

  it "adds questions in order with symbolized ids" do
    questions.noul("escalate", "Human?")
    questions.choice(:department, "Which?", returns: "R", billing: "B")
    questions.score("severity", "How?", "low", "high")

    expect(questions.to_h.keys).to eq(%i[escalate department severity])
    expect(questions.to_h.values.map(&:class))
      .to eq([S1::Question::Noul, S1::Question::Choice, S1::Question::Score])
    expect(questions.size).to eq(3)
    expect(questions).not_to be_empty
    expect(questions.map { |id, _| id }).to eq(%i[escalate department severity])
  end

  it "turns noul clarification kwargs into criteria" do
    questions.noul(:repeat, "Before?", true: "mentions a ticket", false: "no sign")
    expect(questions.to_h[:repeat].criteria).to eq("true" => "mentions a ticket", "false" => "no sign")
  end

  it "leaves noul criteria nil without clarification" do
    questions.noul(:repeat, "Before?")
    expect(questions.to_h[:repeat].criteria).to be_nil
  end

  it "turns choice option kwargs into criteria" do
    questions.choice(:department, "Which?", returns: "Refunds", billing: nil)
    expect(questions.to_h[:department].criteria).to eq("returns" => "Refunds", "billing" => nil)
  end

  it "takes score levels as varargs" do
    questions.score(:severity, "How?", "Cosmetic", "Degraded", "Blocking")
    expect(questions.to_h[:severity].levels).to eq(%w[Cosmetic Degraded Blocking])
  end

  it "prefers explicit criteria: over kwargs and varargs" do
    questions.noul(:n, "N?", criteria: { true: "explicit" }, false: "kwarg")
    questions.choice(:c, "C?", criteria: { x: "X", y: "Y" }, z: "Z")
    questions.score(:s, "S?", "ignored", "also", criteria: %w[a b])

    expect(questions.to_h[:n].criteria).to eq("true" => "explicit")
    expect(questions.to_h[:c].options).to eq(%w[x y])
    expect(questions.to_h[:s].levels).to eq(%w[a b])
  end

  it "raises on a duplicate id" do
    questions.noul(:dup, "One")
    expect { questions.noul("dup", "Two") }.to raise_error(S1::ValidationError, /duplicate question id :dup/)
  end

  it "returns self from add for chaining" do
    expect(questions.add(:a, S1::Question::Noul.new(instructions: "A?"))).to be(questions)
  end

  describe ".coerce" do
    let(:noul) { S1::Question::Noul.new(instructions: "A?") }

    it "accepts a Questions" do
      questions.noul(:a, "A?")
      coerced = described_class.coerce(questions)
      expect(coerced.keys).to eq([:a])
      expect(coerced).to be_frozen
    end

    it "accepts a Hash of Question, symbolizing ids" do
      coerced = described_class.coerce("a" => noul)
      expect(coerced).to eq(a: noul)
      expect(coerced).to be_frozen
    end

    it "accepts a block" do
      coerced = described_class.coerce { |q| q.noul(:a, "A?") }
      expect(coerced.keys).to eq([:a])
      expect(coerced[:a]).to be_a(S1::Question::Noul)
    end

    it "raises when empty" do
      expect { described_class.coerce }.to raise_error(S1::ValidationError, /no questions/)
      expect { described_class.coerce({}) }.to raise_error(S1::ValidationError, /no questions/)
      expect { described_class.coerce { |_q| nil } }.to raise_error(S1::ValidationError, /no questions/)
    end
  end

  describe ".from_h" do
    it "round-trips every type through to_h, with string keys" do
      built = S1::Questions.new
      built.noul(:a, "A?", true: "yes-ish")
      built.choice(:b, "B?", x: "one", y: "two")
      built.score(:c, "C?", "low", "high")
      built.to_h.each_value do |q|
        json = JSON.parse(JSON.generate(q.to_h))
        expect(S1::Question.from_h(json)).to eq(q)
      end
    end

    it "rejects unknown types" do
      expect { S1::Question.from_h(type: "essay", instructions: "x") }.to raise_error(S1::ValidationError, /essay/)
    end
  end
end
