# frozen_string_literal: true

module S1
  # The thing you ask questions about. A String, or a Hash/Array for structured
  # state — then instructions can point at fields with backticked paths
  # (`transcript`, `case_details.sol_deadline`, `messages[0].text`).
  #
  #   subject = S1::Subject.new(transcript)
  #   subject.judge("Is the caller asking for a human agent?")             # => Answer::Noul, 0.94
  #   subject.judge?("Is the caller asking for a human agent?")            # => true / false
  #   subject.choose("Which team?", returns: "Refunds", billing: "Charges") # => Answer::Choice
  #   subject.choice("Which team?", returns: "Refunds", billing: "Charges") # => :refunds
  #   subject.score("How severe?", "Cosmetic", "Degraded", "Blocking")      # => Answer::Score
  #   subject.level("How severe?", "Cosmetic", "Degraded", "Blocking")      # => "Degraded"
  #
  # Each single-question method is one call. When several questions share the
  # state, batch them — one call, independent answers:
  #
  #   result = subject.ask do |q|
  #     q.judge  :escalate,   "Is the customer asking for a human agent?"
  #     q.choose :department, "Which team?", returns: "Refunds", billing: "Charges"
  #   end
  #   result[:department].to_sym
  #
  # The vocabulary has three layers. A measurable (this class) carries the
  # verbs; a verb measures and returns a collapsable, which carries the nouns
  # (S1::Collapsable); a shorthand is verb + noun in one call, defined as
  # `verb(...).collapse`, so on every measurable x.noun(args) == x.verb(args).collapse.
  # Aliases are plain Ruby `alias`es — a class's own method of the same name always wins.
  #   judge    (noul)                Answer::Noul        judge?  (noul?, ask?)  true / false
  #   is / is? ("a man's name")      the English forms: "Is this …?"
  #   choose                         Answer::Choice      choice                 the option, a Symbol
  #   score                          Answer::Score       level                  the label, an S1::Level
  #   ask      measure batch ask_about   many questions, one call; the Result pattern-matches
  #   same_as / same_as?  ===        "do these describe the same thing?"; === is for case/when and grep
  #   given    against              judge against context: the data becomes `this`
  #
  # With `c.symbol = true`, (ψ x) is Subject.new(x); ψ with no argument builds a
  # Predicate (see S1::Predicate) for select / group_by / sort_by / sum.
  #
  # Options (provider:, model:, timeout:, threshold:) override the global config
  # for this state; anything else in **options rides along on the Request for
  # providers and on_result hooks (e.g. an owner to attribute cost to).
  class Subject
    attr_reader :state, :options

    def initialize(state, provider: nil, model: nil, timeout: nil, threshold: nil, **options)
      raise ValidationError, "state can't be nil" if state.nil?

      @state = state
      @provider = provider
      @model = model
      @timeout = timeout
      @threshold = threshold
      @options = options.freeze
    end

    def threshold = @threshold || S1.config.threshold

    # A Subject is its own conversion: the handle renders once and is reused.
    def to_s1(**) = self

    # The same state with context to judge it against: the data becomes `this`,
    # the context sits beside it, and instructions can name either.
    #   (ψ transcript).given(preferences: prefs).is? "qualified, per `preferences`"
    def given(**context) = Subject.new({ this: state, **context }, provider: @provider, model: @model, timeout: @timeout, **options)
    alias against given # "judged against": the same context, read from the other side

    # Batch: many questions, one call. Accepts a block, a Questions, or a Hash.
    def ask(questions = nil, &)
      S1.ask(state, Questions.coerce(questions, &), provider: @provider, model: @model, timeout: @timeout,
                                                    **options)
    end
    alias measure ask # the theory's verb: take the measurement
    alias batch ask
    alias ask_about ask

    # The rule: a verb measures and returns the collapsable; the noun (or the `?`,
    # for a yes/no) is that measurement collapsed to its value — literally
    # `verb(...).collapse`.
    #
    #   judge  "…"          # => Answer::Noul     judge?  "…"   # => true
    #   choose "…", a:, b:  # => Answer::Choice   choice  "…"   # => :a
    #   score  "…", *lvls   # => Answer::Score    level   "…"   # => "Blocking" (an S1::Level)
    def judge(instructions, criteria: nil, **clarification)
      ask_one(:noul) { |q| q.noul(:noul, instructions, criteria: criteria, **clarification) }
    end
    alias noul judge

    def judge?(instructions, criteria: nil, threshold: self.threshold, **clarification)
      judge(instructions, criteria: criteria, **clarification).collapse(threshold)
    end
    alias noul? judge?
    alias ask? judge?

    # English-first noul: the predicate completes "Is this ...?".
    #   subject.is?("a man's name")   subject.is("asking for a human agent") >= 0.9
    # Only on Subject — never on String/Hash/Array, where `is?` would sit next to
    # equality methods.
    def is(predicate, **) = judge("Is this #{predicate}?", **)
    def is?(predicate, **) = judge?("Is this #{predicate}?", **)

    # Semantic equality, as a method rather than ==: (ψ "Acme Inc").same_as? "ACME, Incorporated"
    # An operator would run inside Hash#[], Array#include?, uniq — a network call in each.
    def same_as(other, **)
      pair = Subject.new({ this: state, other: S1.to_state(other).state }, provider: @provider, model: @model, timeout: @timeout,
                                                                           **options)
      pair.judge("Do `this` and `other` describe the same thing?", **)
    end

    def same_as?(other, threshold: self.threshold, **) = same_as(other, **).collapse(threshold)

    # Case equality is Ruby's "does this match?" operator — Range, Regexp and Proc
    # define it, and only case/when, grep and any?(pattern) call it. So a Subject
    # in a `when` is a semantic match; == stays structural (Hash, uniq, RSpec).
    #   case vendor.name
    #   when (ψ "Acme Inc") then ...
    #   end
    #   names.grep(ψ "Acme Inc")
    def ===(other) = same_as?(other)

    # With no options given, the state itself is the options when it has that
    # shape: { label => description } or a list of labels.
    def choose(instructions, criteria: nil, choices: nil, **options)
      criteria ||= choices || (state if options.empty? && options_shaped?(state))
      ask_one(:choice) { |q| q.choice(:choice, instructions, criteria: criteria, **options) }
    end

    def choice(...) = choose(...).collapse

    def score(instructions, *levels, criteria: nil)
      ask_one(:score) { |q| q.score(:score, instructions, *levels, criteria: criteria) }
    end

    def level(...) = score(...).collapse

    private

    # Single-question calls use the primitive's name as the id, so a Stub keyed
    # noul: / choice: / score: answers each kind.
    def ask_one(id, &) = ask(&)[id]

    def options_shaped?(value)
      case value
      when Hash  then value.size >= 2 && value.values.all? { |v| v.nil? || v.is_a?(String) }
      when Array then value.size >= 2 && value.all?(String)
      else false
      end
    end
  end
end
