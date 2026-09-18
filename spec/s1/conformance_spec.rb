# frozen_string_literal: true

require "s1/rspec"

RSpec.describe "S1 provider conformance" do
  describe S1::Providers::Stub do
    it_behaves_like "an S1 provider", -> { S1::Providers::Stub.new(yes: 0.8, which: :b, how: 1) }
  end

  describe S1::Providers::Cua do
    it_behaves_like "an S1 provider", lambda {
      S1::Providers::Cua.new(checkpoint: "fake", python: RbConfig.ruby, script: File.expand_path("../support/fake_cua_sidecar.rb", __dir__))
    }, supports: %i[choice]
  end

  describe S1::Providers::TypeSafe do
    it_behaves_like "an S1 provider", lambda {
      S1.config.typesafe.api_key = "sk-test"
      stub_request(:post, "https://api.typesafe.ai/v1/systemone").to_return(
        status: 200, headers: { "Content-Type" => "application/json" },
        body: JSON.generate(model: "jev-latest", usage: { input_tokens: 10, output_tokens: 1 }, answers: {
                              yes: { noul: 0.8 },
                              which: { choice: "b", probabilities: { a: 0.1, b: 0.8, c: 0.1 }, confidence: 0.8 },
                              how: { score: 1.1, legend: { "0" => "low", "1" => "mid", "2" => "high" },
                                     probabilities: { "0" => 0.2, "1" => 0.6, "2" => 0.2 }, confidence: 0.6 }
                            })
      )
      S1::Providers::TypeSafe.new
    }
  end

  let(:questions) do
    S1::Questions.coerce do |q|
      q.noul :escalate, "Human?"
      q.choice :department, "Which?", returns: "R", billing: "B", shipping: "S"
      q.score :severity, "How?", "Cosmetic", "Degraded", "Blocking"
    end
  end
  let(:request) { S1::Request.new(state: "text", questions: questions, model: "jev-latest", timeout: 30) }

  let(:stub_result) do
    S1::Providers::Stub.new(escalate: 0.94, department: :billing, severity: 2).call(request)
  end
  let(:typesafe_result) do
    S1.config.typesafe.api_key = "sk-test"
    body = JSON.generate(
      model: "jev-latest", usage: { input_tokens: 490, output_tokens: 86 },
      answers: {
        escalate: { noul: 0.94 },
        department: { choice: "billing", probabilities: { returns: 0.1, billing: 0.85, shipping: 0.05 },
                      confidence: 0.85 },
        severity: { score: 1.68, legend: { "0" => "Cosmetic", "1" => "Degraded", "2" => "Blocking" },
                    probabilities: { "0" => 0.05, "1" => 0.22, "2" => 0.73 }, confidence: 0.73 }
      }
    )
    stub_request(:post, "https://api.typesafe.ai/v1/systemone").to_return(status: 200, body: body)
    S1::Providers::TypeSafe.new.call(request)
  end

  let(:surfaces) do
    {
      escalate: %i[to_f true? false? confident? probabilities confidence id type <=> coerce],
      department: %i[to_s to_sym [] == confident? probabilities confidence id type],
      severity: %i[to_f index level levels legend confident? probabilities confidence id type]
    }
  end

  it "tags results with their provider" do
    expect(stub_result.provider).to eq(:stub)
    expect(typesafe_result.provider).to eq(:typesafe)
  end

  it "answers the same ids in the same order" do
    expect(stub_result.answers.keys).to eq(typesafe_result.answers.keys)
    expect(stub_result.answers.keys).to eq(%i[escalate department severity])
  end

  it "yields identical answer classes per id" do
    questions.each_key do |id|
      expect(stub_result[id].class).to eq(typesafe_result[id].class)
    end
    expect(stub_result[:escalate]).to be_a(S1::Answer::Noul)
    expect(stub_result[:department]).to be_a(S1::Answer::Choice)
    expect(stub_result[:severity]).to be_a(S1::Answer::Score)
  end

  it "exposes identical method surfaces" do
    surfaces.each do |id, methods|
      methods.each do |m|
        expect(stub_result[id]).to respond_to(m), "stub #{id} lacks ##{m}"
        expect(typesafe_result[id]).to respond_to(m), "typesafe #{id} lacks ##{m}"
      end
    end
  end

  it "keeps type-specific methods off the other types" do
    [stub_result, typesafe_result].each do |result|
      expect(result[:escalate]).not_to respond_to(:to_sym)
      expect(result[:escalate]).not_to respond_to(:level)
      expect(result[:department]).not_to respond_to(:to_f)
      expect(result[:department]).not_to respond_to(:level)
      expect(result[:severity]).not_to respond_to(:to_sym)
      expect(result[:severity]).not_to respond_to(:true?)
    end
  end

  it "yields identical probability key sets" do
    questions.each_key do |id|
      expect(stub_result[id].probabilities.keys.sort).to eq(typesafe_result[id].probabilities.keys.sort)
    end
    expect(stub_result[:escalate].probabilities.keys).to match_array(%w[true false])
    expect(stub_result[:department].probabilities.keys).to match_array(%w[returns billing shipping])
    expect(stub_result[:severity].probabilities.keys).to match_array(%w[0 1 2])
  end

  it "agrees on the headline reading of each answer" do
    expect(stub_result[:escalate].true?).to eq(typesafe_result[:escalate].true?)
    expect(stub_result[:department].to_sym).to eq(typesafe_result[:department].to_sym)
    expect(stub_result[:severity].level).to eq(typesafe_result[:severity].level)
    expect(stub_result[:severity].levels).to eq(typesafe_result[:severity].levels)
    expect(stub_result[:severity].legend).to eq(typesafe_result[:severity].legend)
  end

  it "normalizes both through the same rail" do
    S1.config.typesafe.api_key = "sk-test"
    stub_request(:post, "https://api.typesafe.ai/v1/systemone")
      .to_return(status: 200, body: JSON.generate(answers: { noul: { noul: 0.7 } }))

    via_typesafe = S1.state("text", provider: :typesafe).noul("Human?")
    via_stub = S1.state("text", provider: S1::Providers::Stub.new(noul: 0.7)).noul("Human?")

    expect(via_typesafe.class).to eq(via_stub.class)
    expect(via_typesafe.to_f).to eq(via_stub.to_f)
    expect(via_typesafe.probabilities).to eq(via_stub.probabilities)
  end

  it "yields the same Answer::Choice shape from a choice-only local provider (cua)" do
    cua = S1::Providers::Cua.new(checkpoint: "fake", python: RbConfig.ruby,
                                 script: File.expand_path("../support/fake_cua_sidecar.rb", __dir__))
    choice_only = S1::Request.new(state: "billing question", questions: questions.slice(:department), model: nil, timeout: 30)
    cua_answer = cua.call(choice_only)[:department]
    expect(cua_answer.class).to eq(stub_result[:department].class)
    expect(cua_answer.probabilities.keys).to eq(stub_result[:department].probabilities.keys)
    expect(cua_answer.public_methods(false).sort).to eq(stub_result[:department].public_methods(false).sort)
    expect(cua.supports?(questions[:escalate])).to be(false)
  ensure
    cua&.close
  end
end
