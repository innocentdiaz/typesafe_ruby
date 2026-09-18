# frozen_string_literal: true

module S1
  # The symbol: with `c.symbol = true`, ψ(x) is S1.to_state(x), defined on
  # Kernel the way Integer() and Pathname() are. ψ, the wavefunction — a thing
  # that is only probabilities until you ask it a question. ψ makes a thing
  # *measurable*; judge / choose / score / measure take the measurement (a
  # distribution); the trailing `?` on what follows is the collapse. Between
  # them: arithmetic. Any identifier can
  # stand in (`c.symbol = "⍣"`, `c.symbol = "Subject"`). Off by default; the
  # explicit spelling is always S1::Subject.new. With a block it is
  # S1.about: the subject for the bare forms inside.
  #
  #   (ψ"Michael").is? "a man's name"
  #   ψ chat do
  #     escalate if noul?("Is the customer asking for a human agent?")
  #   end
  module Conversion
    IDENTIFIER = /\A[[:^ascii:]a-zA-Z_][[:^ascii:]\w]*\z/

    class << self
      attr_reader :installed

      # Defines the named function on Kernel; removes the previous one when the
      # name changes or `nil` is given. Idempotent.
      def install!(name)
        name = name&.to_s
        raise ArgumentError, "symbol must be a Ruby identifier (got #{name.inspect})" if name && !name.match?(IDENTIFIER)
        return if name == installed

        Kernel.send(:remove_method, installed) if installed
        if name
          Kernel.define_method(name) do |state = (none = true), **options, &block|
            next S1.predicates if none # ψ.is "…", ψ.choose "…": a question with no state yet

            block ? S1.about(state, **options, &block) : S1.to_state(state, **options)
          end
          Kernel.send(:private, name)
        end
        @installed = name
      end
    end
  end
end
