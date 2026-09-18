# frozen_string_literal: true

RSpec.describe S1 do
  describe ".to_state" do
    it "wraps anything in a Subject, via #to_s1 when the object has one" do
      S1.config.provider = S1::Providers::Stub.new(noul: 0.9)
      expect(S1.to_state("Michael")).to be_a(S1::Subject)
      expect(S1.to_state("x", threshold: 0.95).noul?("q?")).to be(false)
      custom = Class.new { def to_s1(**) = S1::Subject.new("converted", **) }.new
      expect(S1.to_state(custom).state).to eq("converted")
      expect(Object.private_method_defined?(:ψ)).to be(false)
    end
  end

  it "has a version number" do
    expect(S1::VERSION).to match(/\A\d+\.\d+\.\d+/)
  end

  describe ".configure" do
    it "yields the config and returns it" do
      yielded = nil
      returned = described_class.configure { |c| yielded = c }

      expect(yielded).to be_a(S1::Config)
      expect(returned).to be(yielded)
      expect(returned).to be(described_class.config)
    end

    it "persists assignments, including provider sections" do
      described_class.configure do |c|
        c.threshold = 0.9
        c.typesafe.model = "jev-2026"
        c.cua.checkpoint = "ckpt"
      end
      expect(described_class.config.threshold).to eq(0.9)
      expect(described_class.config.typesafe.model).to eq("jev-2026")
      expect(described_class.config.cua.checkpoint).to eq("ckpt")
    end
  end

  describe ".reset_config!" do
    it "restores defaults" do
      described_class.configure do |c|
        c.provider = :stub
        c.typesafe.model = "other"
        c.threshold = 0.9
      end

      described_class.reset_config!

      expect(described_class.config.provider).to eq(:typesafe)
      expect(described_class.config.threshold).to eq(0.5)
      expect(described_class.config.timeout).to eq(30)
      expect(described_class.config.typesafe.model).to eq("jev-latest")
      expect(described_class.config.typesafe.base_url).to eq("https://api.typesafe.ai")
      expect(described_class.config.typesafe.max_retries).to eq(2)
      expect(described_class.config).not_to respond_to(:api_key)
      expect(described_class.config).not_to respond_to(:model)
    end
  end

  describe S1::Config do
    it "exposes each provider's section, with ENV defaults read when the config is built" do
      expect(S1.config.typesafe.to_h.keys).to eq(%i[api_key base_url model max_retries])
      expect(S1.config.cua.to_h).to eq(checkpoint: nil, python: "python3", device: "auto")
      expect(S1.config.typesafe.api_key).to eq(ENV.fetch("TYPESAFE_API_KEY", nil))
    end

    it "hands a section to its provider as constructor keywords, and {} to one without settings" do
      expect(S1.config.section(:typesafe)).to eq(S1.config.typesafe.to_h)
      expect(S1.config.section(:stub)).to eq({})
      expect(S1.config.section(nil)).to eq({})
    end

    it "declares a section from a provider class" do
      klass = Class.new(S1::Providers::Base) { settings :probe, region: "us", key: -> { "from-env" } }
      expect(klass.settings_name).to eq(:probe)
      S1.reset_config!
      expect(S1.config.probe.to_h).to eq(region: "us", key: "from-env")
      S1.config.probe.region = "eu"
      expect(S1.config.section(:probe)).to eq(region: "eu", key: "from-env")
    ensure
      S1::Config.sections.delete(:probe)
      S1::Config.send(:remove_method, :probe)
    end
  end
end
