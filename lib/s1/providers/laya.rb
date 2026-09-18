# frozen_string_literal: true

require_relative "system_one_http"

module S1
  module Providers
    # Laya (github.com/NandhaKishorM/laya, Apache-2.0): a self-hosted S1 model
    # with jev's three primitives, jev's question shapes and jev's answer keys —
    # only the transport differs. support/laya_server.py wraps `pip install laya`
    # in the System One HTTP contract (POST /v1/systemone) on a port you run;
    # no key.
    #
    #   S1.configure { |c| c.provider = :laya; c.laya.base_url = "http://127.0.0.1:8765" }
    #
    # Models: "laya" (English, 512 tokens), "multilingual" (100+ languages, 1024
    # tokens), "typed-decisions". Choice degrades past ~20 options.
    class Laya < Base
      include SystemOneHTTP

      DEFAULT_MODEL = "laya"

      settings :laya, base_url: "http://127.0.0.1:8765", model: DEFAULT_MODEL, max_retries: 2

      def initialize(base_url: nil, model: nil, max_retries: nil, logger: nil)
        super()
        section = S1.config.laya
        @api_key = nil
        @base_url = base_url || section.base_url
        @model = model || section.model || DEFAULT_MODEL
        @max_retries = max_retries || section.max_retries
        @logger = logger || S1.config.logger
      end
    end
  end
end
