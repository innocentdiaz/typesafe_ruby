# frozen_string_literal: true

require "s1/rspec"

RSpec.describe S1::Providers::Laya do
  let(:answers) do
    { yes: { noul: 0.8 },
      which: { choice: "b", probabilities: { a: 0.1, b: 0.8, c: 0.1 }, confidence: 0.8 },
      how: { score: 1.1, probabilities: { "0" => 0.2, "1" => 0.6, "2" => 0.2 }, confidence: 0.6 } } # no legend: Laya's shape
  end

  before do
    stub_request(:post, "http://127.0.0.1:8765/v1/systemone")
      .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                 body: JSON.generate(model: "laya", usage: { input_tokens: 0, output_tokens: 0 }, answers: answers))
  end

  it_behaves_like "an S1 provider", -> { S1::Providers::Laya.new }

  it "speaks the System One HTTP contract over a local server: no key, its own section, its own default model" do
    expect(S1.config.laya.to_h).to include(base_url: "http://127.0.0.1:8765", model: "laya")
    result = S1::Subject.new("text", provider: :laya).measure { |q| q.score :how, "How?", "low", "mid", "high" }
    expect(WebMock).to(have_requested(:post, "http://127.0.0.1:8765/v1/systemone").with do |req|
      !req.headers.key?("Authorization") && JSON.parse(req.body)["model"] == "laya"
    end)
    expect(result.provider).to eq(:laya)
    expect(result[:how].level).to eq("mid") # legend filled from the question's levels
  end

  it "keeps TypeSafe's own key requirement" do
    S1.config.typesafe.api_key = nil
    expect { S1::Subject.new("text", provider: :typesafe).judge?("q?") }.to raise_error(S1::AuthenticationError)
  end
end
