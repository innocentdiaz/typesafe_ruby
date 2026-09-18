# frozen_string_literal: true

module S1
  # Opt-in core extension: the state itself becomes the receiver.
  #
  #   S1.configure { |c| c.primitives = true }              # String, Hash, Array
  #   S1.configure { |c| c.primitives = [String] }          # or a subset
  #   require "s1/core_ext"                                 # or the require-style opt-in
  #
  #   "Can I talk to a real person?".noul?("Is the customer asking for a human agent?")
  #   { ticket: text }.choose("Which team?", returns: "Refunds", billing: "Charges")   # => Answer::Choice
  #   { ticket: text }.choice("Which team?", returns: "Refunds", billing: "Charges")   # => :returns
  #   { ticket: text }.ask { |q| q.noul :escalate, "..." }
  #
  # Each method delegates to S1::Subject.new(self); #to_s1 gives you the
  # Subject when you need per-call options. The vocabulary matches Subject —
  # the verb measures, the noun collapses: judge/judge?, choose/choice,
  # score/level, ask (aliases noul/noul?/ask?, batch/ask_about). A class's own method
  # of one of those names always wins, since the module is included below it.
  # is? / same_as? / given stay on Subject — reach them through #to_s1 or ψ.
  #
  # Naming Kernel in the targets also adds receiver-less forms that act on the
  # ambient subject. Opt in separately: bare `score` / `ask` / `choice` shadow
  # any DSL that resolves those names through method_missing (FactoryBot
  # attributes, for one).
  #
  #   S1.configure { |c| c.primitives = [String, Hash, Array, Kernel] }
  #   S1.about(phone_call) do
  #     noul?("Is the caller asking for a human agent?")
  #     ask { |q| q.noul :escalate, "..." }
  #   end
  module Primitives
    TARGETS = [String, Hash, Array].freeze

    def to_s1(**) = Subject.new(self, **)
    def judge(instructions, **kw) = to_s1.judge(instructions, **kw)
    alias noul judge
    def judge?(instructions, **kw) = to_s1.judge?(instructions, **kw)
    alias noul? judge?
    alias ask? noul?
    def choose(instructions, **kw) = to_s1.choose(instructions, **kw)
    def choice(instructions, **kw) = to_s1.choice(instructions, **kw)
    def score(instructions, *levels, **kw) = to_s1.score(instructions, *levels, **kw)
    def level(instructions, *levels, **kw) = to_s1.level(instructions, *levels, **kw)
    def ask(questions = nil, &) = to_s1.ask(questions, &)
    alias measure ask
    alias batch ask
    alias ask_about ask

    # Kernel-level: no receiver, acts on S1.subject.
    module Bare
      private

      def judge(instructions, **kw) = S1.subject.judge(instructions, **kw)
      alias noul judge
      def judge?(instructions, **kw) = S1.subject.judge?(instructions, **kw)
      alias noul? judge?
      alias ask? noul?
      def choose(instructions, **kw) = S1.subject.choose(instructions, **kw)
      def choice(instructions, **kw) = S1.subject.choice(instructions, **kw)
      def score(instructions, *levels, **kw) = S1.subject.score(instructions, *levels, **kw)
      def level(instructions, *levels, **kw) = S1.subject.level(instructions, *levels, **kw)
      def ask(questions = nil, &) = S1.subject.ask(questions, &)
      alias measure ask
      alias batch ask
      alias ask_about ask
    end

    class << self
      # Idempotent. `true` installs on all TARGETS; an array narrows or extends
      # it (classes, or their names; Kernel adds the bare forms). Returns the
      # modules extended.
      def install!(targets = true)
        modules = if targets == true
                    TARGETS
                  else
                    Array(targets).map do |t|
                      t.is_a?(Module) ? t : Object.const_get(t.to_s)
                    end
                  end
        modules.each do |mod|
          ext = mod == Kernel ? Bare : self
          mod.include(ext) unless mod.include?(ext)
        end
        modules
      end

      def installed?(mod) = mod.include?(mod == Kernel ? Bare : self)
    end
  end
end
