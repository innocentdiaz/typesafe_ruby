# frozen_string_literal: true

module S1
  module Providers
    # The provider contract: #call(Request) -> Result. A provider owns its
    # transport and its wire format, and translates into the normalized Answer
    # types here — consumers never see a vendor's keys.
    class Base
      class << self
        attr_reader :settings_name

        # Declares the provider's section of S1.config, with defaults; a callable
        # default is evaluated when the Config is built. The section is what
        # Client.resolve_provider passes to .new when the provider is named.
        #   settings :typesafe, api_key: -> { ENV.fetch("TYPESAFE_API_KEY", nil) }, model: "jev-latest"
        def settings(name = nil, **defaults)
          @settings_name = (name || self.name.split("::").last.downcase).to_sym
          S1::Config.register(@settings_name, defaults)
        end
      end

      def call(_request)
        raise NotImplementedError, "#{self.class}#call(request) must return a S1::Result"
      end

      def name = self.class.name.split("::").last.downcase.to_sym

      # The question types this provider answers. Client.ask checks before
      # calling; a choice-only model (cua-s1-forms) declares [Question::Choice].
      def supports?(_question) = true

      protected

      def build_result(answers:, model: nil, usage: {}, raw: nil)
        Result.new(answers: answers, usage: usage, model: model, provider: name, raw: raw)
      end

      # Normalized-answer constructor keyed off the question's type, so every
      # provider builds the same objects from its own wire fields.
      def answer(id, question, raw: nil, **fields)
        case question
        when Question::Noul
          Answer::Noul.new(id: id, probability: fields.fetch(:probability), raw: raw)
        when Question::Choice
          Answer::Choice.new(id: id, choice: fields.fetch(:choice), probabilities: fields.fetch(:probabilities),
                             confidence: fields[:confidence], raw: raw)
        when Question::Score
          Answer::Score.new(id: id, score: fields.fetch(:score), legend: fields.fetch(:legend),
                            probabilities: fields.fetch(:probabilities), confidence: fields[:confidence], raw: raw)
        else
          raise ValidationError, "unknown question type #{question.class}"
        end
      end
    end
  end
end
