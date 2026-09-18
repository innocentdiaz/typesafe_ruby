# frozen_string_literal: true

require "open3"

# Primitives extend core classes irreversibly, so each case runs in its own process.
RSpec.describe S1::Primitives do
  def run(script)
    out, err, status = Open3.capture3(RbConfig.ruby, "-I", File.expand_path("../../lib", __dir__), "-e", script)
    raise "#{err}\n#{out}" unless status.success?

    out.strip
  end

  STUB = "S1::Providers::Stub.new(noul: 0.9, choice: :billing, score: 2, e: 0.8)"

  it "is off by default" do
    expect(run('require "s1"; print "x".respond_to?(:noul?)')).to eq("false")
  end

  it "installs via config on String, Hash and Array" do
    script = <<~RUBY
      require "s1"
      S1.configure { |c| c.primitives = true; c.provider = #{STUB} }
      print [
        "text".noul?("q?"),
        { a: 1 }.choose("t?", returns: "R", billing: "B").to_sym,
        [1].score("n?", "few", "some", "many").level,
        { a: 1 }.ask { |q| q.noul :e, "x?" }.true?(:e),
        "text".to_s1(threshold: 0.95).noul?("q?")
      ].inspect
    RUBY
    expect(run(script)).to eq('[true, :billing, "many", true, false]')
  end

  it "defines ψ with c.symbol = true, or any identifier given, and removes it when switched" do
    script = <<~RUBY
      require "s1"
      S1.configure { |c| c.symbol = true; c.provider = #{STUB} }
      out = [ψ("x").noul?("q?"), ψ("x", threshold: 0.95).noul?("q?")]
      S1.configure { |c| c.symbol = "⍣" }
      out << Object.private_method_defined?(:ψ) << ⍣("x").noul?("q?")
      S1.configure { |c| c.symbol = false }
      out << Object.private_method_defined?(:⍣)
      out << (begin; S1.configure { |c| c.symbol = "not an identifier" }; rescue ArgumentError => e; e.message[/identifier/]; end)
      print out.inspect
    RUBY
    expect(run(script)).to eq('[true, false, false, true, false, "identifier"]')
  end

  it "ψ with a block is S1.about, with the bare forms inside" do
    script = <<~RUBY
      require "s1"
      S1.configure { |c| c.symbol = true; c.primitives = [Kernel]; c.provider = #{STUB} }
      out = ψ({ chat: "x" }) { [noul?("q?"), S1.subject.state] }
      out << (begin; S1.subject; rescue S1::InvalidRequestError; :restored; end)
      print out.inspect
    RUBY
    expect(run(script)).to eq('[true, {:chat=>"x"}, :restored]')
  end

  it "ψ with no argument is the predicate builder" do
    script = <<~RUBY
      require "s1"
      S1.configure { |c| c.symbol = true; c.provider = #{STUB} }
      print [ψ.is("x").class.name, %w[a b].select(&ψ.is("x")).size, ψ("a").class.name].inspect
    RUBY
    expect(run(script)).to eq('["S1::Predicate", 2, "S1::Subject"]')
  end

  it "does not put is? on core classes" do
    expect(run('require "s1"; S1.configure { |c| c.primitives = true }; print "x".respond_to?(:is?)')).to eq("false")
  end

  it "adds ask? as noul?, and yields to a class's own ask?" do
    script = <<~RUBY
      require "s1"
      class Hash; def ask?(*) = :mine; end
      S1.configure { |c| c.primitives = true; c.provider = #{STUB} }
      print ["text".ask?("q?"), { a: 1 }.ask?("q?")].inspect
    RUBY
    expect(run(script)).to eq("[true, :mine]")
  end

  it "installs a subset by name" do
    script = <<~RUBY
      require "s1"
      S1.configure { |c| c.primitives = ["String"] }
      print [String, Hash].map { |k| k.include?(S1::Primitives) }.inspect
    RUBY
    expect(run(script)).to eq("[true, false]")
  end

  it "installs via require" do
    expect(run('require "s1/core_ext"; print S1::Primitives.installed?(Hash)')).to eq("true")
  end

  it "leaves Kernel alone unless asked" do
    script = <<~RUBY
      require "s1"
      S1.configure { |c| c.primitives = true }
      print [Object.private_method_defined?(:noul?), S1::Primitives.installed?(Kernel)].inspect
    RUBY
    expect(run(script)).to eq("[false, false]")
  end

  it "adds receiver-less forms on the ambient subject when Kernel is a target" do
    script = <<~RUBY
      require "s1"
      S1.configure { |c| c.primitives = [String, Hash, Array, Kernel]; c.provider = #{STUB} }
      out = []
      out << (begin; noul?("q?"); rescue S1::InvalidRequestError; :no_subject; end)
      S1.about({ transcript: "hi" }) do
        out << noul?("q?") << choose("t?", a: "1", billing: "2").to_sym << score("n?", "a", "b", "c").index << ask { |q| q.noul :e, "x?" }[:e].to_f
        S1.about("inner") { out << S1.subject.state }
        out << S1.subject.state
      end
      out << (begin; noul?("q?"); rescue S1::InvalidRequestError; :restored; end)
      S1.subject = "console"
      out << noul?("q?") << Object.new.respond_to?(:noul?)
      print out.inspect
    RUBY
    expect(run(script)).to eq('[:no_subject, true, :billing, 2, 0.8, "inner", {:transcript=>"hi"}, :restored, true, false]')
  end
end
