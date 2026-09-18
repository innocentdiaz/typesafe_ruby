# frozen_string_literal: true

module S1
  # Errors are grouped by intent so a caller rescues by transient vs permanent, not by HTTP code:
  class Error < StandardError; end

  class TransientError < Error; end

  class RateLimitError < TransientError
    attr_reader :retry_after

    def initialize(message = nil, retry_after: nil)
      super(message)
      @retry_after = retry_after
    end
  end

  class ServerError     < TransientError; end
  class ConnectionError < TransientError; end
  class TimeoutError    < TransientError; end

  class PermanentError       < Error; end
  class AuthenticationError  < PermanentError; end
  class InvalidRequestError  < PermanentError; end
  # a malformed question, before or after the wire
  class ValidationError      < PermanentError; end
  # a question type this provider cannot answer (see Providers::Base#supports?)
  class UnsupportedError     < PermanentError; end
end
