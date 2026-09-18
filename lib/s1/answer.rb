# frozen_string_literal: true

module S1
  # Normalized answers. Consumers read these and never a provider's wire keys —
  # that is what lets a second provider slot in unchanged.
  module Answer
    class Base
      include Collapsable

      attr_reader :id, :probabilities, :confidence, :raw

      def initialize(id:, probabilities:, confidence:, raw: nil)
        @id = id.to_sym
        @probabilities = (probabilities || {}).transform_keys(&:to_s).freeze
        @confidence = confidence
        @raw = raw
        freeze
      end

      # Route on this: act automatically above the threshold, escalate below it.
      def confident?(threshold = S1.config.threshold)
        return true if confidence.nil?

        confidence >= threshold
      end

      def type = self.class.name.split("::").last.downcase
      def inspect = "#<#{self.class.name} #{self}>"
    end

    # "Is this true?" — the probability IS the signal. Compares directly against
    # numbers (`answer >= 0.85`), and thresholds into a boolean via #true?.
    class Noul < Base
      include Comparable

      attr_reader :probability

      def initialize(id:, probability:, raw: nil)
        @probability = probability.to_f
        super(id: id, probabilities: { "true" => @probability,
                                       "false" => 1.0 - @probability }, confidence: nil, raw: raw)
      end

      def to_f = probability
      def to_s = probability.to_s
      def true?(threshold = S1.config.threshold) = probability >= threshold
      def false?(threshold = S1.config.threshold) = !true?(threshold)
      def <=>(other) = probability <=> other.to_f
      def coerce(number) = [number.to_f, probability]

      # A noul is confident when it sits far from the fence on either side.
      def confident?(threshold = S1.config.threshold)
        probability >= threshold || probability <= 1.0 - threshold
      end

      # The collapse, named: the probability becomes a boolean. `?` methods are
      # this same step (noul?, judge?, is?); keep the probability until here.
      def collapse(threshold = S1.config.threshold) = true?(threshold)

      # `!answer` is "not true at the threshold", so `!!answer` is the collapse.
      # A bare `if answer` is still always truthy — Ruby's `if` never calls `!`.
      def ! = !collapse

      # Too close to the fence to act on alone: hand off instead of collapsing.
      def undecided?(margin = 0.1, threshold: S1.config.threshold) = (probability - threshold).abs < margin

      # Probability algebra. Answers from one batch are independent (the model
      # guarantees it), so these are exact for them: both / either / not.
      #   (r[:is_lead] & r[:qualified]) >= 0.8
      #   ~r[:spam]
      def &(other) = Noul.new(id: :"#{id}&#{other.id}", probability: probability * other.to_f)
      def |(other) = Noul.new(id: :"#{id}|#{other.id}", probability: 1 - ((1 - probability) * (1 - other.to_f)))
      def ~ = Noul.new(id: :"~#{id}", probability: 1 - probability)
    end

    # "Which of these options?" — an unordered pick with a distribution over all
    # options. The collapse, named: #choice, the option as a Symbol.
    class Choice < Base
      attr_reader :choice

      def initialize(id:, choice:, probabilities:, confidence:, raw: nil)
        @choice = choice.to_sym
        super(id: id, probabilities: probabilities, confidence: confidence, raw: raw)
      end

      def to_sym = choice
      def to_s = choice.to_s
      def collapse(*) = choice
      # Every option, most likely first: a ranking from one call.
      def ranked = probabilities.sort_by { |_, p| -p }.map(&:first)
      def [](option) = probabilities[option.to_s]
      def ==(other) = other.respond_to?(:to_s) && to_s == other.to_s
    end

    # "Which level?" — a position on an ordered spectrum. #to_f is the
    # probability-weighted position; #index is the most likely level's position.
    # The collapse, named: #level, an S1::Level — the label, knowing its position.
    class Score < Base
      attr_reader :score, :legend, :scale

      def initialize(id:, score:, legend:, probabilities:, confidence:, raw: nil)
        @score = score.to_f
        @legend = legend.to_h.transform_keys { |k| k.to_s.to_i }.freeze
        @scale = @legend.sort.map { |_, text| text.to_s }.freeze
        super(id: id, probabilities: probabilities, confidence: confidence, raw: raw)
      end

      def to_f = score
      def collapse(*) = level
      def to_s = "#{index} #{level.inspect}"
      def index = probabilities.max_by { |_, p| p }&.first.to_i
      def level = Level.new(legend[index], index, scale)
      def levels = scale.each_with_index.map { |text, i| Level.new(text, i, scale) }
    end
  end
end
