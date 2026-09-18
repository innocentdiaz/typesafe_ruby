# frozen_string_literal: true

module S1
  # What a measurement returns: a probabilistic breakdown that can also just
  # collapse. Answer::Noul, Answer::Choice and Answer::Score are collapsables (one
  # measurement each); a Result is one too (several, from `measure { … }`).
  #
  # Collapsables carry the nouns. One contract, `collapse(threshold)` — the
  # threshold only matters to a noul; the others take and ignore it, so a Result
  # collapses every answer through one call. Each kind names its collapse and
  # exposes Ruby's own conversions:
  #
  #   kind             collapse →                its own name   Ruby idioms
  #   Answer::Noul     true / false               true?          !  !!  to_f  Comparable  & | ~
  #   Answer::Choice   a Symbol                   choice         to_sym  to_s  ==
  #   Answer::Score    an S1::Level               level          index  to_f  levels
  #   Result           { id => collapsed value }  to_h           deconstruct_keys (case … in)
  #
  # A `?` method returns a boolean, as in Ruby, so `?` exists only for a noul.
  # The shorthands on a measurable are verb + noun in one call, and the identity
  # holds everywhere: x.noun(args) == x.verb(args).collapse.
  #
  # The distribution is the information; `collapse` is the lossy summary — take it last.
  module Collapsable
    def collapse(*)
      raise NotImplementedError, "#{self.class}#collapse"
    end

    def collapsable? = true
  end
end
