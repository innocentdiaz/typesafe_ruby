# frozen_string_literal: true

require_relative "s1/version"
require_relative "s1/errors"
require_relative "s1/config"
require_relative "s1/question"
require_relative "s1/collapsable"
require_relative "s1/level"
require_relative "s1/answer"
require_relative "s1/result"
require_relative "s1/subject"
require_relative "s1/predicate"
require_relative "s1/client"
require_relative "s1/primitives"
require_relative "s1/providers/base"
require_relative "s1/providers/stub"
require_relative "s1/providers/typesafe"
require_relative "s1/providers/cua"
require_relative "s1/providers/laya"
require_relative "s1/conversion"

# S1 — Ruby primitives for System One (S1) models.
#
#   S1.configure { |c| c.typesafe.api_key = ENV["TYPESAFE_API_KEY"] }
#
#   subject = S1::Subject.new("I have asked three times. Can I talk to a real person?")
#   subject.judge?("Is the customer asking for a human agent?")   # => true
#
#   result = subject.ask do |q|
#     q.judge  :escalate,   "Is the customer asking for a human agent?"
#     q.choose :department, "Which team should handle this?", returns: "Refunds, exchanges", billing: "Charges"
#     q.score  :severity,   "How severe is the issue?", "Cosmetic", "Degraded", "Blocking"
#   end
#   result[:department].to_sym   # => :returns
module S1
  extend Client

  class << self
    def config
      @config ||= Config.new
    end

    def configure
      yield config
      Primitives.install!(config.primitives) if config.primitives
      Conversion.install!(config.symbol_name)
      config
    end

    # Anything becomes an S1 Subject. Objects that know how (#to_s1: primitives,
    # typesafe-rails records) convert themselves. ψ(x) is this, when enabled.
    def to_state(state, **) = state.respond_to?(:to_s1) ? state.to_s1(**) : Subject.new(state, **)

    # Test hook: discard configuration between examples.
    def reset_config!
      @config = nil
    end
  end
end
