# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module S1
  module Providers
    # The System One HTTP contract, as jev defined it and others adopted it
    # (Laya). A provider includes this and supplies @base_url, @api_key (may be
    # empty), @model, @max_retries, @logger — see TypeSafe and Laya. Stdlib only.
    #
    #   POST {base_url}/v1/systemone
    #   { "state": ..., "model": "...", "questions": { id: { type, instructions, criteria } } }
    #   { "model": "...", "usage": { input_tokens, output_tokens },
    #     "answers": { id: { noul } | { choice, probabilities, confidence } | { score, legend?, probabilities, confidence } } }
    #
    # Transient failures (429, 5xx, connection, timeout) retry with backoff and
    # honor Retry-After; everything else maps straight onto the error taxonomy.
    module SystemOneHTTP
      PATH = "/v1/systemone"

      def call(request)
        body = JSON.generate(state: request.state, model: request.model || @model,
                             questions: request.questions.transform_values(&:to_h))
        response = with_retries { post(body, timeout: request.timeout) }
        parse(request, response)
      end

      private

      def post(body, timeout:)
        uri = URI.join(@base_url, PATH)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = timeout
        http.read_timeout = timeout

        req = Net::HTTP::Post.new(uri.path)
        req["Authorization"] = "Bearer #{@api_key}" unless @api_key.to_s.empty?
        req["Content-Type"] = "application/json"
        req["Accept"] = "application/json"
        req["User-Agent"] = "s1-ruby/#{S1::VERSION}"
        req.body = body

        @logger&.debug { "[s1:typesafe] POST #{uri} (#{body.bytesize} bytes)" }
        http.request(req)
      rescue Net::OpenTimeout, Net::ReadTimeout => e
        raise TimeoutError, e.message
      rescue SocketError, Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH, OpenSSL::SSL::SSLError => e
        raise ConnectionError, e.message
      end

      def with_retries
        attempt = 0
        begin
          response = yield
          raise_for(response) unless response.is_a?(Net::HTTPSuccess)
          response
        rescue TransientError => e
          attempt += 1
          raise if attempt > @max_retries

          delay = e.is_a?(RateLimitError) && e.retry_after ? e.retry_after : [0.5 * (2**(attempt - 1)), 5.0].min
          @logger&.warn { "[s1:typesafe] #{e.class} — retry #{attempt}/#{@max_retries} in #{delay}s" }
          sleep(delay)
          retry
        end
      end

      def raise_for(response)
        status = response.code.to_i
        detail = error_detail(response.body)
        message = "typesafe #{status}: #{detail}"
        case status
        when 401, 403 then raise AuthenticationError, message
        when 422      then raise ValidationError, message
        when 429      then raise RateLimitError.new(message, retry_after: response["Retry-After"]&.to_f)
        when 500..599 then raise ServerError, message
        else               raise InvalidRequestError, message
        end
      end

      def error_detail(body)
        parsed = JSON.parse(body.to_s)
        detail = parsed.is_a?(Hash) ? parsed["detail"] : parsed
        detail.is_a?(Array) ? detail.map { |d| d["msg"] || d.to_s }.join("; ") : detail.to_s
      rescue JSON::ParserError
        body.to_s[0, 300]
      end

      def parse(request, response)
        payload = JSON.parse(response.body)
        wire = payload["answers"] if payload.is_a?(Hash)
        raise ValidationError, "response has no answers" unless wire.is_a?(Hash)

        answers = request.questions.to_h do |id, question|
          a = wire[id.to_s] or raise ValidationError, "no answer returned for #{id.inspect}"
          [id, answer(id, question, raw: a, **fields_from(question, a))]
        end
        build_result(answers: answers, model: payload["model"], usage: payload.fetch("usage", {}), raw: payload)
      rescue JSON::ParserError => e
        raise ValidationError, "unparseable response: #{e.message}"
      end

      def fields_from(question, a)
        case question
        when Question::Noul   then { probability: a.fetch("noul") }
        when Question::Choice then { choice: a.fetch("choice"), probabilities: a.fetch("probabilities"), confidence: a["confidence"] }
        when Question::Score # a server that sends no legend gets one from the question's levels
          { score: a.fetch("score"), legend: a["legend"] || question.levels.each_with_index.to_h { |l, i| [i.to_s, l] },
            probabilities: a.fetch("probabilities"), confidence: a["confidence"] }
        end
      rescue KeyError => e
        raise ValidationError, "malformed answer for #{question.type}: #{e.message}"
      end
    end
  end
end
