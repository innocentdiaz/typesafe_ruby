# frozen_string_literal: true

require_relative "system_one_http"

module S1
  module Providers
    # TypeSafe's jev, over its hosted System One API (SystemOneHTTP). Needs a key.
    #
    #   S1.configure { |c| c.typesafe.api_key = ENV["TYPESAFE_API_KEY"] }
    class TypeSafe < Base
      include SystemOneHTTP

      DEFAULT_MODEL = "jev-latest"

      settings :typesafe, api_key: -> { ENV.fetch("TYPESAFE_API_KEY", nil) }, base_url: "https://api.typesafe.ai",
                          model: DEFAULT_MODEL, max_retries: 2

      def initialize(api_key: nil, base_url: nil, model: nil, max_retries: nil, logger: nil)
        super()
        section = S1.config.typesafe
        @api_key = api_key || section.api_key
        @base_url = base_url || section.base_url
        @model = model || section.model || DEFAULT_MODEL
        @max_retries = max_retries || section.max_retries
        @logger = logger || S1.config.logger
      end

      def call(request)
        raise AuthenticationError, "no API key: set S1.config.typesafe.api_key or TYPESAFE_API_KEY" if @api_key.to_s.empty?

        super
      end
    end
  end
end
