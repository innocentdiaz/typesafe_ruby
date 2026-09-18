# frozen_string_literal: true

module S1
  module Providers
    # Canned answers, no network: the test double every consumer of the gem needs,
    # and the second implementation that proves the provider contract.
    #
    #   S1.configure { |c| c.provider = S1::Providers::Stub.new(escalate: 0.9, department: :billing) }
    #
    # Shorthand by question type, or the full fields:
    #   noul   -> 0.9        (probability)
    #   choice -> :billing   (that option at 1.0)  | { choice:, probabilities:, confidence: }
    #   score  -> 2          (that level at 1.0)   | { score:, legend:, probabilities:, confidence: }
    # Unlisted questions get neutral defaults: noul 0.5, first option, first level.
    # A block receives the Request and returns the same map.
    class Stub < Base
      def initialize(answers = {}, &block)
        super()
        @answers = answers.transform_keys(&:to_sym)
        @block = block
      end

      def call(request)
        canned = @answers.merge((@block&.call(request) || {}).transform_keys(&:to_sym))
        answers = request.questions.to_h do |id, question|
          [id, answer(id, question, **fields_for(question, canned[id]))]
        end
        build_result(answers: answers, model: "stub", usage: { input_tokens: 0, output_tokens: 0 })
      end

      private

      def fields_for(question, value)
        return value.transform_keys(&:to_sym) if value.is_a?(Hash)

        case question
        when Question::Noul
          { probability: value.nil? ? 0.5 : value.to_f }
        when Question::Choice
          pick = (value || question.options.first).to_s
          { choice: pick, probabilities: question.options.to_h { |o| [o, o == pick ? 1.0 : 0.0] }, confidence: 1.0 }
        when Question::Score
          idx = (value || 0).to_i
          legend = question.levels.each_with_index.to_h { |lvl, i| [i, lvl] }
          { score: idx.to_f, legend: legend, probabilities: legend.keys.to_h do |i|
            [i.to_s, i == idx ? 1.0 : 0.0]
          end, confidence: 1.0 }
        end
      end
    end
  end
end
