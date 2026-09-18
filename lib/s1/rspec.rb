# frozen_string_literal: true

# The provider conformance suite, for any gem that implements one:
#
#   require "s1/rspec"
#   RSpec.describe MyProvider do
#     it_behaves_like "an S1 provider", -> { MyProvider.new(api_key: "test") }
#   end
#
# The block builds a provider that can answer without the network (a stubbed
# HTTP client, a fake sidecar). Pass `supports:` when it answers only some
# question types.
RSpec.shared_examples "an S1 provider" do |build, supports: %i[noul choice score]|
  let(:provider) { instance_exec(&build) }
  let(:questions) do
    S1::Questions.new.tap do |q|
      q.noul :yes, "Is it?" if supports.include?(:noul)
      q.choice :which, "Which?", a: "one", b: "two", c: "three" if supports.include?(:choice)
      q.score :how, "How much?", "low", "mid", "high" if supports.include?(:score)
    end.to_h
  end
  let(:request) { S1::Request.new(state: "some text", questions: questions, model: nil, timeout: 30) }
  let(:result) { provider.call(request) }

  it "returns a Result — a Collapsable — tagged with its name" do
    expect(result).to be_a(S1::Result)
    expect(result).to be_a(S1::Collapsable)
    expect(result.provider).to eq(provider.name)
  end

  it "answers every question, by id, with the answer class its type demands" do
    expect(result.answers.keys).to match_array(questions.keys)
    questions.each do |id, question|
      klass = { "noul" => S1::Answer::Noul, "choice" => S1::Answer::Choice, "score" => S1::Answer::Score }.fetch(question.type)
      expect(result[id]).to be_a(klass)
      expect(result[id].id).to eq(id)
    end
  end

  it "keeps probabilities as probabilities" do
    result.answers.each_value do |a|
      expect(a.probabilities.values).to all(be_between(0.0, 1.0))
      expect(a.probabilities.values.sum).to be_within(0.02).of(1.0)
    end
  end

  it "keys a choice's distribution by its options and a score's by level index" do
    expect(result[:which].probabilities.keys).to match_array(%w[a b c]) if supports.include?(:choice)
    expect(result[:how].probabilities.keys).to match_array(%w[0 1 2]) if supports.include?(:score)
    expect(result[:how].levels).to eq(%w[low mid high]) if supports.include?(:score)
  end

  it "collapses" do
    expect(result[:yes].collapse).to be(true).or be(false) if supports.include?(:noul)
    expect(%i[a b c]).to include(result[:which].collapse) if supports.include?(:choice)
    expect(0..2).to cover(result[:how].collapse) if supports.include?(:score)
    expect(result[:how].collapse).to be_a(S1::Level) if supports.include?(:score)
  end

  it "declares what it does not support, so ask refuses before calling" do
    %i[noul choice score].each do |type|
      q = { noul: S1::Question::Noul.new(instructions: "q?"),
            choice: S1::Question::Choice.new(instructions: "q?", criteria: { a: nil, b: nil }),
            score: S1::Question::Score.new(instructions: "q?", criteria: %w[x y]) }.fetch(type)
      expect(provider.supports?(q)).to eq(supports.include?(type))
    end
  end

  it "usage, when reported, is integers" do
    expect(result.usage.values).to all(be_a(Integer))
  end
end
