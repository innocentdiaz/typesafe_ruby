# frozen_string_literal: true

require "json"
require "open3"

module S1
  module Providers
    # cua-s1-forms (huggingface.co/cua-ai/cua-s1-forms): a small jev-like
    # one-pass option scorer — context in, one probability per option out.
    # Choice only, local, byte-limited. A different creature from jev in every
    # way but the shape of the answer, which is the point of having it.
    #
    # Transport: a Python sidecar (support/cua_s1_sidecar.py) holding the
    # checkpoint, one JSON line per question. Needs `cua-s1` and torch on the
    # Python side; the checkpoint as safetensors + json.
    #
    #   S1.configure { |c| c.provider = :cua; c.cua.checkpoint = "cua-s1-forms" }
    #
    # Translation this provider owns: the state becomes the context string
    # (as given, or JSON); choice options become option strings — the key, or
    # "key: description" when a description is given — truncated to the
    # model's byte limits; the winner is the argmax and confidence is its
    # probability. noul and score are refused (UnsupportedError) rather than
    # emulated: the model is trained on form elements, not propositions.
    class Cua < Base
      SIDECAR = File.expand_path("../../../support/cua_s1_sidecar.py", __dir__)
      MODEL = "cua-s1-forms"

      settings :cua, checkpoint: nil, python: "python3", device: "auto"

      attr_reader :config

      def initialize(checkpoint: nil, python: nil, script: SIDECAR, device: nil)
        super()
        section = S1.config.cua
        @checkpoint = checkpoint || section.checkpoint
        @command = [python || section.python, script, @checkpoint, device || section.device]
      end

      def supports?(question) = question.is_a?(Question::Choice)

      def call(request)
        boot unless @stdin # the byte limits come from the checkpoint's config
        answers = request.questions.to_h do |id, question|
          options = question.criteria.map { |key, desc| desc ? "#{key}: #{desc}" : key.to_s }
          probs = score(context_for(request.state), options)
          probabilities = question.options.zip(probs).to_h
          pick, confidence = probabilities.max_by { |_, p| p }
          [id, answer(id, question, raw: probs, choice: pick, probabilities: probabilities, confidence: confidence)]
        end
        build_result(answers: answers, model: MODEL, usage: { input_tokens: 0, output_tokens: 0 })
      end

      def close
        @stdin&.close
        @wait&.value
        @stdin = @stdout = @wait = nil
      end

      private

      def context_for(state)
        text = state.is_a?(String) ? state : JSON.generate(state)
        limit = config&.dig("context_tokens")
        raise ValidationError, "cua-s1 context is limited to #{limit} bytes (got #{text.bytesize})" if limit && text.bytesize > limit

        text
      end

      def score(context, options)
        @stdin.puts(JSON.generate(context: context, options: options))
        reply = JSON.parse(@stdout.gets || raise(ConnectionError, "cua-s1 sidecar exited"))
        raise InvalidRequestError, "cua-s1: #{reply["error"]}" if reply["error"]

        reply.fetch("probabilities")
      rescue Errno::EPIPE
        close
        raise ConnectionError, "cua-s1 sidecar died"
      end

      def boot
        raise InvalidRequestError, "no checkpoint: set S1.config.cua.checkpoint" if @checkpoint.to_s.empty?

        @stdin, @stdout, @wait = Open3.popen2(*@command)
        first = @stdout.gets or raise ConnectionError, "cua-s1 sidecar failed to start (#{@command.join(" ")})"
        @config = JSON.parse(first).fetch("config")
      end
    end
  end
end
