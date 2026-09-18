# frozen_string_literal: true

module S1
  # A question not yet bound to a state, so it can go where Ruby expects a
  # block or a pattern. Built by ψ with no argument (or S1.predicates):
  #
  #   angry = ψ.is "an angry customer"
  #   calls.select(&angry)                 calls.grep(angry)               calls.count(&angry)
  #   calls.group_by(&ψ.choose "Which team?", returns: "…", billing: "…")   # => { returns: [...], ... }
  #   tickets.sort_by(&ψ.score "How severe?", "cosmetic", "degraded", "blocking")
  #   calls.sum(&ψ.judge "the customer is angry")                           # expected count, calibrated
  #
  # Define a question once, apply it to one or many:
  #   team = ψ.choose "Which team?", returns: "…", support: "…"
  #   team[ticket]  team.measure(ticket)  tickets.group_by(&team)
  #
  # Builders mirror Subject: is, noul/judge, noul?/judge?/ask?, choice/choose,
  # score, same_as?. Each element is one call. Applied to an element, a predicate returns what
  # Enumerable wants: is/judge?/noul? a boolean, judge/noul the probability (so
  # `sum` counts), choose the symbol, score the S1::Level (so `sort_by` / `max_by`
  # order by position). `given:` is the context every element is judged against —
  # the stream is the data, `given:` is the knob:
  #
  #   qualified = ψ.is("qualified for the role, per `qualifications`", given: { qualifications: role.requirements })
  #   candidates.select(&qualified)
  # Options split by side: `given:` and `as:` (a typesafe-rails form) shape
  # the state; everything else is the question's (clarification, choices,
  # threshold, enum).
  STATE_OPTIONS = %i[given as].freeze

  Predicate = Data.define(:name, :args, :options) do
    # The measurement itself, un-collapsed: the Answer with its distribution.
    def measure(state)
      subject = options[:as] ? S1.to_state(state, as: options[:as]) : S1.to_state(state)
      subject = subject.given(**options[:given]) if options[:given]
      subject.public_send(name, *args, **options.except(*STATE_OPTIONS))
    end

    # Applied to one subject, as Enumerable would: the collapsed value.
    #   team = ψ.choose "Which team?", returns: "…", support: "…"
    #   team[ticket]               # => :returns      tickets.group_by(&team)
    def call(state) = unwrap(measure(state))
    alias_method :[], :call

    def to_proc = method(:call).to_proc
    def ===(state) = call(state)

    private

    # A noul stays the probability; every other collapsable collapses.
    def unwrap(answer)
      case answer
      when Answer::Noul then answer.to_f
      when Collapsable  then answer.collapse
      else answer
      end
    end
  end

  # Same rule as on a Subject: the verb (judge / choose / score) measures, the
  # noun or `?` collapses. Applied through Enumerable both collapse to a value;
  # `measure(x)` gives the verb's collapsable, the noun's value.
  module Predicates
    module_function

    def is(predicate, **options) = Predicate.new(:is?, [predicate], options)
    def judge(instructions, **options) = Predicate.new(:judge, [instructions], options)
    def judge?(instructions, **options) = Predicate.new(:judge?, [instructions], options)
    def choose(instructions, **options) = Predicate.new(:choose, [instructions], options)
    def choice(instructions, **options) = Predicate.new(:choice, [instructions], options)
    def score(instructions, *levels, **options) = Predicate.new(:score, [instructions, *levels], options)
    def level(instructions, *levels, **options) = Predicate.new(:level, [instructions, *levels], options)
    def same_as?(other, **options) = Predicate.new(:same_as?, [other], options)

    alias noul judge
    alias noul? judge?
    alias ask? judge?
    class << self
      alias noul judge
      alias noul? judge?
      alias ask? judge?
    end
  end

  def self.predicates = Predicates
end
