# frozen_string_literal: true

module S1
  # What a score collapses to: the level's label, a String that knows its
  # position on the scale. Being a String it interpolates, stores and serializes
  # as the label; knowing its position it compares by that and not by alphabet:
  #
  #   lvl = (ψ text).level "How severe?", "Cosmetic", "Degraded", "Blocking"   # => "Blocking"
  #   lvl >= 1               lvl >= "Degraded"          lvl.to_i   # => 2
  #   case r in { severity: 2.. }   /   in { severity: "Blocking" }
  #   tickets.sort_by(&ψ.score(…))  # by position;  group_by(&ψ.score(…)) keys are the labels
  #
  # Keep the level on the left of a comparison with a label (`"Degraded" <= lvl`
  # is String's own compare). Integer ranges match; ranges of labels do not.
  class Level < String
    attr_reader :index, :scale

    def initialize(text, index, scale)
      super(text)
      @index = index
      @scale = scale.map(&:to_s).freeze
      freeze
    end

    def to_i = index

    # By position: against a Level or an Integer directly, against a label on
    # the scale by that label's position; anything else is incomparable (nil).
    def <=>(other)
      case other
      when Level, Integer then index <=> other.to_i
      when String then scale.index(other)&.then { |position| index <=> position }
      end
    end

    def ==(other) = other.is_a?(Integer) ? index == other : super

    def coerce(number) = [number, index]
  end
end
