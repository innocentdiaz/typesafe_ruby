# frozen_string_literal: true

RSpec.describe "TypeSafe provider live smoke", skip: !(ENV["TYPESAFE_LIVE"] == "1" && !ENV["TYPESAFE_API_KEY"].to_s.empty?) do
  around do |example|
    WebMock.allow_net_connect!
    example.run
  ensure
    WebMock.disable_net_connect!
  end

  before { S1.config.typesafe.api_key = ENV.fetch("TYPESAFE_API_KEY") }

  it "answers a 3-question batch against api.typesafe.ai" do
    state = S1::Subject.new("I have asked three times now. Can I just talk to a real person?")

    result = state.ask do |q|
      q.noul :escalate, "Is the customer asking for a human agent?"
      q.choice :department, "Which team should handle this?",
               returns: "Exchanges, refunds", shipping: "Delivery status", billing: "Charges, invoices"
      q.score :severity, "How severe is the reported issue?",
              "Cosmetic; no impact", "Degraded, workaround exists", "Blocking; no workaround"
    end

    expect(result.provider).to eq(:typesafe)
    expect(result.model).to be_a(String)
    expect(result.duration_ms).to be_a(Integer)
    expect(result.input_tokens).to be >= 0

    noul = result[:escalate]
    expect(noul).to be_a(S1::Answer::Noul)
    expect(noul.to_f).to be_between(0.0, 1.0)
    expect([true, false]).to include(noul.true?)

    choice = result[:department]
    expect(choice).to be_a(S1::Answer::Choice)
    expect(%w[returns shipping billing]).to include(choice.to_s)
    expect(choice.probabilities.keys).to match_array(%w[returns shipping billing])
    choice.probabilities.each_value { |p| expect(p).to be_between(0.0, 1.0) }
    expect(choice.confidence).to be_between(0.0, 1.0) if choice.confidence

    score = result[:severity]
    expect(score).to be_a(S1::Answer::Score)
    expect(score.index).to be_between(0, 2)
    expect(score.levels.size).to eq(3)
    expect(score.levels).to include(score.level)
    expect(score.to_f).to be_between(0.0, 2.0)
    score.probabilities.each_value { |p| expect(p).to be_between(0.0, 1.0) }
    expect(score.confidence).to be_between(0.0, 1.0) if score.confidence
  end
end
