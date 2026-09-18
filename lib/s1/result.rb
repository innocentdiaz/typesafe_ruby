# frozen_string_literal: true

module S1
  # One call's worth of answers, keyed by question id. Pattern-matches
  # (#deconstruct_keys): nouls as booleans, choices as symbols, scores as
  # Levels — which match integer ranges and labels alike:
  # `case result in { escalate: true, severity: 2.. }`, `in { severity: "Blocking" }`.
  class Result
    include Enumerable
    include Collapsable

    attr_reader :answers, :usage, :model, :provider, :duration_ms, :raw

    def initialize(answers:, usage: {}, model: nil, provider: nil, duration_ms: nil, raw: nil)
      @answers = answers.to_h.transform_keys(&:to_sym).freeze
      @usage = (usage || {}).transform_keys(&:to_sym).freeze
      @model = model
      @provider = provider
      @duration_ms = duration_ms
      @raw = raw
      freeze
    end

    # Every answer collapsed at once: nouls as booleans at the threshold, choices
    # as symbols, scores as Levels. `to_h` is the same; pattern matching sees
    # this view, so integer ranges and labels both work as patterns:
    #   case state.batch { |q| ... }
    #   in { escalate: true, severity: 2.. }   then page_someone
    #   in { severity: "Blocking" }            then ...
    #   in { department: :billing }            then ...
    #   end
    def collapse(threshold = S1.config.threshold)
      answers.transform_values { |a| a.collapse(threshold) }
    end
    alias to_h collapse

    def deconstruct_keys(keys) = keys ? collapse.slice(*keys.map(&:to_sym)) : collapse

    def [](id)
      answers.fetch(id.to_sym) { raise KeyError, "no answer for #{id.inspect} (have #{answers.keys.inspect})" }
    end

    def key?(id) = answers.key?(id.to_sym)

    def true?(id, threshold = S1.config.threshold)
      answer = self[id]
      raise ValidationError, "#{id.inspect} is a #{answer.type}, not a noul" unless answer.is_a?(Answer::Noul)

      answer.true?(threshold)
    end

    def each(&) = answers.each(&)
    def size = answers.size

    def nouls   = answers.select { |_, a| a.is_a?(Answer::Noul) }
    def choices = answers.select { |_, a| a.is_a?(Answer::Choice) }
    def scores  = answers.select { |_, a| a.is_a?(Answer::Score) }

    def input_tokens  = usage[:input_tokens].to_i
    def output_tokens = usage[:output_tokens].to_i

    def with(**changes)
      self.class.new(answers: answers, usage: usage, model: model, provider: provider, duration_ms: duration_ms,
                     raw: raw, **changes)
    end
  end

  # What a provider receives: the state, the id => Question map, and options.
  Request = Data.define(:state, :questions, :model, :timeout, :options) do
    def initialize(state:, questions:, model: nil, timeout: nil, options: {})
      super(state: state, questions: questions, model: model, timeout: timeout, options: options.freeze)
    end
  end
end
