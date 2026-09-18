# frozen_string_literal: true

# Require-style opt-in: `require "s1/core_ext"` extends String, Hash and
# Array with noul / noul? / choice / score / ask. Equivalent to
# S1.configure { |c| c.primitives = true }.
require_relative "../s1"

S1::Primitives.install!
