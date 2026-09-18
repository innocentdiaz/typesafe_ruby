# frozen_string_literal: true

require_relative "lib/s1/version"

Gem::Specification.new do |spec|
  spec.name = "s1"
  spec.version = S1::VERSION
  spec.authors = ["innocentdiaz"]
  spec.email = ["sdz.innocent@gmail.com"]

  spec.summary = "Ruby primitives for System One (S1) models: noul, choice, score."
  spec.description = <<~DESC
    A provider-agnostic Ruby interface to System One models — models that answer typed
    questions about a state with calibrated probabilities instead of generating text.
    Ask one question or batch many in a single call; get back normalized answers your
    code can branch on directly. Providers ship for TypeSafe's jev (hosted) and
    cua-s1-forms (local); a Stub answers in tests.
  DESC
  spec.homepage = "https://github.com/innocentdiaz/s1"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["rubygems_mfa_required"] = "true"

  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Zero runtime dependencies: the wire protocol is one JSON POST, served by stdlib.
end
