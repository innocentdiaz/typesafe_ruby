# frozen_string_literal: true

module S1
  # The three primitives, as immutable value objects. Provider-agnostic: #to_h is
  # the canonical form every provider translates to its own wire format.
  #
  # `instructions` is a String, or a Hash for structured questions (e.g. a
  # `field` / `extracted_value` / `question` verification). Criteria shapes are
  # deliberately different per type because they mean different things:
  #   Noul   — optional { true: "what counts as yes", false: "what counts as no" }
  #   Choice — { option => description | nil }  an UNORDERED set
  #   Score  — [level, level, ...]               an ORDERED spectrum, worst -> best
  module Question
    Noul = Data.define(:instructions, :criteria) do
      def initialize(instructions:, criteria: nil)
        criteria = Question.normalize_noul_criteria(criteria)
        super(instructions: Question.check_instructions(instructions), criteria: criteria)
      end

      def type = "noul"
      def to_h = { type: type, instructions: instructions, criteria: criteria }.compact
    end

    Choice = Data.define(:instructions, :criteria) do
      # criteria: { option => description } or an Array of options (no descriptions).
      def initialize(instructions:, criteria:)
        options = Question.choice_options(criteria)
        raise ValidationError, "choice needs at least 2 options (got #{options.size})" if options.size < 2

        super(instructions: Question.check_instructions(instructions), criteria: options)
      end

      def type = "choice"
      def options = criteria.keys
      def to_h = { type: type, instructions: instructions, criteria: criteria }
    end

    Score = Data.define(:instructions, :criteria) do
      def initialize(instructions:, criteria:)
        levels = Array(criteria).map(&:to_s)
        raise ValidationError, "score needs at least 2 ordered levels (got #{levels.size})" if levels.size < 2

        super(instructions: Question.check_instructions(instructions), criteria: levels)
      end

      def type = "score"
      def levels = criteria
      def to_h = { type: type, instructions: instructions, criteria: criteria }
    end

    class << self
      # Inverse of #to_h, for questions that crossed a serialization boundary
      # (a job queue, a database).
      def from_h(hash)
        h = hash.to_h.transform_keys(&:to_sym)
        klass = { "noul" => Noul, "choice" => Choice, "score" => Score }.fetch(h[:type].to_s) do
          raise ValidationError, "unknown question type #{h[:type].inspect}"
        end
        klass.new(instructions: h[:instructions], criteria: h[:criteria])
      end

      def check_instructions(instructions)
        case instructions
        when String then instructions.strip.tap do |s|
          raise ValidationError, "instructions can't be blank" if s.empty?
        end
        when Hash then instructions
        else raise ValidationError, "instructions must be a String or a Hash (got #{instructions.class})"
        end
      end

      # { option => description }, or a bare list of options (no descriptions).
      def choice_options(criteria)
        criteria = criteria.to_h { |o| [o, nil] } if criteria.is_a?(Array) && criteria.none?(Hash)
        (criteria || {}).to_h.transform_keys(&:to_s)
      rescue TypeError
        raise ValidationError, "choice options must be { option => description } or a list of options"
      end

      def normalize_noul_criteria(criteria)
        return nil if criteria.nil? || criteria.empty?

        h = criteria.to_h.transform_keys(&:to_s)
        extra = h.keys - %w[true false]
        raise ValidationError, "noul criteria may only clarify true/false (got #{extra.inspect})" if extra.any?

        h
      end
    end
  end

  # The batch builder yielded by Subject#ask. Collects id => Question in order.
  #
  #   state.ask do |q|
  #     q.noul   :repeat,     "Contacted before?", true: "mentions a prior ticket", false: "no sign of one"
  #     q.choice :department, "Which team?", returns: "Refunds", billing: "Charges"
  #     q.score  :severity,   "How severe?", "Cosmetic", "Degraded", "Blocking"
  #   end
  class Questions
    include Enumerable

    def initialize
      @questions = {}
    end

    def noul(id, instructions, criteria: nil, **clarification)
      add(id, Question::Noul.new(instructions: instructions, criteria: criteria || clarification))
    end

    # criteria:, choices:, or the options as keywords.
    def choice(id, instructions, criteria: nil, choices: nil, **options)
      add(id, Question::Choice.new(instructions: instructions, criteria: criteria || choices || options))
    end
    alias choose choice
    alias judge noul # the three measurements, by the theory's names: judge / choose / score

    def score(id, instructions, *levels, criteria: nil)
      add(id, Question::Score.new(instructions: instructions, criteria: criteria || levels))
    end

    def add(id, question)
      key = id.to_sym
      raise ValidationError, "duplicate question id #{key.inspect}" if @questions.key?(key)

      @questions[key] = question
      self
    end

    def each(&) = @questions.each(&)
    def to_h = @questions.dup
    def size = @questions.size
    def empty? = @questions.empty?

    # Accepts a Questions, a Hash of id => Question, or a block; always returns a
    # frozen id => Question map. `into` is the builder the block sees — a
    # subclass can add sugar (typesafe-rails fills choice options from enums).
    def self.coerce(questions = nil, into = new, &block)
      return questions.to_h.freeze if questions.is_a?(Questions) && !questions.empty?

      built = into
      block&.call(built)
      (questions || {}).each { |id, q| built.add(id, q) }
      raise ValidationError, "no questions given" if built.empty?

      built.to_h.freeze
    end
  end
end
