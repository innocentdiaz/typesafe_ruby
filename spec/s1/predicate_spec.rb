# frozen_string_literal: true

RSpec.describe S1::Predicate do
  let(:p) { S1.predicates }
  let(:calls) { ["angry about a bill", "calm return", "angry return", "bill question"] }

  before do
    S1.config.provider = S1::Providers::Stub.new do |req|
      s = req.state.to_s
      { noul: s.include?("angry") ? 0.9 : 0.1, choice: s.include?("bill") ? :billing : :returns, score: s.length % 3 }
    end
  end

  it "filters, counts and greps with a boolean predicate" do
    angry = p.is("an angry customer")
    expect(calls.select(&angry)).to eq(["angry about a bill", "angry return"])
    expect(calls.grep(angry)).to eq(["angry about a bill", "angry return"])
    expect(calls.count(&p.judge?("angry"))).to eq(2)
    expect(calls.partition(&p.ask?("angry")).last).to eq(["calm return", "bill question"])
  end

  it "groups by a choice and sorts by a score" do
    expect(calls.group_by(&p.choose("Which team?", returns: "r", billing: "b")))
      .to eq(billing: ["angry about a bill", "bill question"], returns: ["calm return", "angry return"])
    expect(calls.min_by(&p.score("How severe?", "low", "mid", "high"))).to eq("angry about a bill")
    expect(calls.max_by(&p.score("How severe?", "low", "mid", "high"))).to eq("calm return")
  end

  it "sorts by a score's position, not its label's alphabet" do
    severity = p.score("How severe?", "low", "mid", "high")
    expect(calls.sort_by(&severity).last(2)).to eq(["bill question", "calm return"])
    expect(calls.map(&severity)).to eq(%w[low high low mid])
    expect(calls.map(&severity)).to all(be_a(S1::Level))
    expect(calls.group_by(&severity).keys).to eq(%w[low high mid])
    expect(calls.group_by(&severity)["high"]).to eq(["calm return"])
  end

  it "sums calibrated probabilities into an expected count" do
    expect(calls.sum(&p.judge("angry"))).to eq(2.0)
  end

  it "judges each element against the context in given:" do
    seen = []
    S1.config.provider = S1::Providers::Stub.new { |req| seen << req.state and { noul: req.state[:this].include?("bill") ? 0.9 : 0.1 } }
    qualified = p.is("about the same thing as `topic`", given: { topic: "billing" })
    expect(calls.select(&qualified)).to eq(["angry about a bill", "bill question"])
    expect(seen.first).to eq(this: "angry about a bill", topic: "billing")
  end

  it "applies to one subject with [] and gives the un-collapsed answer with #measure" do
    team = p.choose("Which team?", returns: "r", billing: "b")
    expect(team["angry about a bill"]).to eq(:billing)
    expect(team.call("calm return")).to eq(:returns)
    expect(team.measure("angry about a bill")).to be_a(S1::Answer::Choice)
    expect(team.measure("angry about a bill").probabilities.keys).to eq(%w[returns billing])
    expect(calls.group_by(&team).keys).to eq(%i[billing returns])
  end

  it "carries options through to the state" do
    expect(calls.count(&p.is("angry", threshold: 0.95))).to eq(0)
  end

  it "asks about elements with same_as?" do
    S1.config.provider = S1::Providers::Stub.new { |req| { noul: req.state[:this].include?("bill") ? 0.9 : 0.1 } }
    expect(calls.select(&p.same_as?("a billing call"))).to eq(["angry about a bill", "bill question"])
  end

  it "is what ψ returns with no argument" do
    expect(described_class).to be_a(Class)
    expect(S1.predicates.is("x")).to be_a(described_class)
  end
end
