# frozen_string_literal: true

RSpec.describe S1::Providers::Cua do
  subject(:provider) do
    described_class.new(checkpoint: "fake.safetensors", python: RbConfig.ruby,
                        script: File.expand_path("../../support/fake_cua_sidecar.rb", __dir__))
  end

  after { provider.close }

  let(:context) { 'TASK fill the form  ELEMENT Edit "Phone number" value=""' }

  it "answers a choice with one probability per option, the argmax as the pick" do
    result = S1::Subject.new(context, provider: provider).ask do |q|
      q.choice :fill_with, "Which entity?", phone: "555-0100", email: "a@b.c", skip: nil
    end
    answer = result[:fill_with]
    expect(answer.to_sym).to eq(:phone)
    expect(answer.probabilities.keys).to eq(%w[phone email skip])
    expect(answer.probabilities.values.sum).to be_within(0.01).of(1.0)
    expect(answer.confidence).to eq(answer.probabilities["phone"])
    expect(result.provider).to eq(:cua)
    expect(provider.config["context_tokens"]).to eq(224)
  end

  it "translates option descriptions into option text and reuses the sidecar" do
    state = S1::Subject.new(context, provider: provider)
    2.times { state.choose("Which?", phone: "555-0100", skip: nil) }
    expect(state.choose("Which?", choices: %w[phone skip]).to_sym).to eq(:phone)
  end

  it "refuses noul and score before calling, as UnsupportedError" do
    state = S1::Subject.new(context, provider: provider)
    expect { state.noul?("Is this a phone field?") }.to raise_error(S1::UnsupportedError, /cua cannot answer a noul/)
    expect { state.score("How?", "a", "b") }.to raise_error(S1::UnsupportedError, /score/)
    expect(S1::UnsupportedError.ancestors).to include(S1::PermanentError)
  end

  it "enforces the model's context limit" do
    state = S1::Subject.new("x" * 300, provider: provider)
    expect { state.choose("Which?", a: nil, b: nil) }.to raise_error(S1::ValidationError, /224 bytes/)
  end

  it "serializes structured state as JSON context" do
    result = S1::Subject.new({ element: "Phone number" }, provider: provider).choose("Which?", phone: nil, email: nil)
    expect(result.to_sym).to eq(:phone)
  end

  it "reads checkpoint, python and device from S1.config.cua when not given" do
    S1.config.cua.checkpoint = "from-config"
    S1.config.cua.python = RbConfig.ruby
    S1.config.cua.device = "cpu"
    configured = described_class.new(script: File.expand_path("../../support/fake_cua_sidecar.rb", __dir__))
    expect(S1::Subject.new(context, provider: configured).choose("Which?", phone: nil, skip: nil).to_sym).to eq(:phone)
    expect(configured.config["checkpoint"]).to eq("from-config")
  ensure
    configured&.close
  end

  it "refuses to boot without a checkpoint" do
    expect { S1::Subject.new(context, provider: described_class.new).choose("?", a: nil, b: nil) }
      .to raise_error(S1::InvalidRequestError, "no checkpoint: set S1.config.cua.checkpoint")
  end

  it "maps a dead sidecar to ConnectionError" do
    dead = described_class.new(checkpoint: "x", python: RbConfig.ruby, script: "-e", device: "exit 1")
    expect { S1::Subject.new("ctx", provider: dead).choose("?", a: nil, b: nil) }.to raise_error(S1::ConnectionError)
  end
end
