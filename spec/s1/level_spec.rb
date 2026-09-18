# frozen_string_literal: true

RSpec.describe S1::Level do
  let(:scale) { ["Cosmetic", "Broken, workaround exists", "Blocking"] }
  let(:level) { described_class.new("Broken, workaround exists", 1, scale) }
  let(:top) { described_class.new("Blocking", 2, scale) }

  it "is its label, a String, frozen, knowing its position and scale" do
    expect(level).to be_a(String)
    expect(level).to eq("Broken, workaround exists")
    expect(level).to be_frozen
    expect(level.index).to eq(1)
    expect(level.to_i).to eq(1)
    expect(level.scale).to eq(scale)
    expect(level.scale).to be_frozen
    expect("#{level}!").to eq("Broken, workaround exists!")
  end

  it "compares by position against a Level, an Integer or a label on the scale" do
    expect(level <=> top).to eq(-1)
    expect(level < top).to be(true)
    expect(level <=> 1).to eq(0)
    expect(level >= 1).to be(true)
    expect(level > 1).to be(false)
    expect(level <=> "Blocking").to eq(-1)
    expect(level >= "Cosmetic").to be(true)
    expect(level >= "Blocking").to be(false)
    expect(level.between?("Cosmetic", "Blocking")).to be(true)
  end

  it "is incomparable with a label off the scale" do
    expect(level <=> "Severe").to be_nil
    expect { level >= "Severe" }.to raise_error(ArgumentError)
  end

  it "equals its index and its label" do
    expect(level == 1).to be(true)
    expect(level == 2).to be(false)
    expect(level == "Broken, workaround exists").to be(true)
    expect(level == "Blocking").to be(false)
    expect(1 == level).to be(true) # rubocop:disable Style/YodaCondition
    expect("Broken, workaround exists" == level).to be(true) # rubocop:disable Style/YodaCondition
  end

  it "coerces, so an Integer on the left and integer ranges work" do
    expect(2 <= level).to be(false) # rubocop:disable Style/YodaCondition
    expect(1 <= level).to be(true) # rubocop:disable Style/YodaCondition
    expect((1..) === level).to be(true) # rubocop:disable Style/CaseEquality
    expect((3..) === level).to be(false) # rubocop:disable Style/CaseEquality
    expect((0..1) === level).to be(true) # rubocop:disable Style/CaseEquality
    expect((2..3) === level).to be(false) # rubocop:disable Style/CaseEquality
    expect(level.coerce(2)).to eq([2, 1])
  end

  it "is a Hash key interchangeable with its label" do
    h = { level => :found }
    expect(h["Broken, workaround exists"]).to eq(:found)
    expect({ "Broken, workaround exists" => :found }[level]).to eq(:found)
    expect(level.hash).to eq("Broken, workaround exists".hash)
    expect(level).to eql("Broken, workaround exists")
  end

  it "sorts by position, not alphabet" do
    labels = %w[low mid high]
    levels = labels.each_with_index.map { |text, i| described_class.new(text, i, labels) }
    expect(levels.shuffle.sort).to eq(%w[low mid high])
    expect(levels.max).to eq("high")
    expect(labels.sort).to eq(%w[high low mid])
  end
end
