# frozen_string_literal: true

RSpec.describe S1::Providers::TypeSafe do
  let(:url) { "https://api.typesafe.ai/v1/systemone" }
  let(:questions) do
    S1::Questions.coerce do |q|
      q.noul :escalate, "Human?", true: "asks for a person", false: "does not"
      q.choice :department, "Which?", returns: "R", billing: "B", shipping: "S"
      q.score :severity, "How?", "Cosmetic", "Degraded", "Blocking"
    end
  end
  let(:request) { S1::Request.new(state: "text", questions: questions, model: "jev-latest", timeout: 30) }
  let(:answers) do
    {
      "escalate" => { "noul" => 0.94 },
      "department" => { "choice" => "billing",
                        "probabilities" => { "returns" => 0.1, "billing" => 0.85, "shipping" => 0.05 },
                        "confidence" => 0.85 },
      "severity" => { "score" => 1.68,
                      "legend" => { "0" => "Cosmetic", "1" => "Degraded", "2" => "Blocking" },
                      "probabilities" => { "0" => 0.05, "1" => 0.22, "2" => 0.73 },
                      "confidence" => 0.73 }
    }
  end
  let(:ok_body) do
    JSON.generate(model: "jev-latest", usage: { input_tokens: 490, output_tokens: 86 }, answers: answers)
  end

  before { S1.config.typesafe.api_key = "sk-test" }

  def stub_ok(body = ok_body)
    stub_request(:post, url).to_return(status: 200, body: body, headers: { "Content-Type" => "application/json" })
  end

  it "names itself" do
    expect(described_class.new.name).to eq(:typesafe)
    expect(described_class.settings_name).to eq(:typesafe)
  end

  describe "request" do
    it "POSTs the state, model and questions with a bearer token" do
      sent = nil
      headers = { "Authorization" => "Bearer sk-test", "Content-Type" => "application/json",
                  "Accept" => "application/json", "User-Agent" => "s1-ruby/#{S1::VERSION}" }
      stub = stub_request(:post, url).with(headers: headers).to_return do |req|
        sent = JSON.parse(req.body)
        { status: 200, body: ok_body }
      end

      described_class.new.call(request)

      expect(stub).to have_been_requested.once
      expect(sent.keys).to eq(%w[state model questions])
      expect(sent["state"]).to eq("text")
      expect(sent["model"]).to eq("jev-latest")
      expect(sent["questions"]).to eq(
        "escalate" => { "type" => "noul", "instructions" => "Human?",
                        "criteria" => { "true" => "asks for a person", "false" => "does not" } },
        "department" => { "type" => "choice", "instructions" => "Which?",
                          "criteria" => { "returns" => "R", "billing" => "B", "shipping" => "S" } },
        "severity" => { "type" => "score", "instructions" => "How?",
                        "criteria" => %w[Cosmetic Degraded Blocking] }
      )
    end

    it "sends its configured model when the request names none, DEFAULT_MODEL when nothing does" do
      sent = []
      stub_request(:post, url).to_return do |req|
        sent << JSON.parse(req.body)["model"]
        { status: 200, body: ok_body }
      end
      bare = request.with(model: nil)

      described_class.new.call(bare)
      S1.config.typesafe.model = "jev-2026"
      described_class.new.call(bare)
      described_class.new(model: "jev-fast").call(bare)
      S1.config.typesafe.model = nil
      described_class.new.call(bare)

      expect(sent).to eq(["jev-latest", "jev-2026", "jev-fast", described_class::DEFAULT_MODEL])
    end

    it "omits criteria for a bare noul" do
      sent = nil
      stub_request(:post, url).to_return do |req|
        sent = JSON.parse(req.body)
        { status: 200, body: ok_body }
      end
      bare = S1::Questions.coerce { |q| q.noul :escalate, "Human?" }
      described_class.new.call(S1::Request.new(state: "text", questions: bare, model: "jev-latest"))
      expect(sent["questions"]["escalate"]).to eq("type" => "noul", "instructions" => "Human?")
    end

    it "passes structured instructions and structured state through" do
      sent = nil
      stub_request(:post, url).to_return do |req|
        sent = JSON.parse(req.body)
        { status: 200, body: ok_body }
      end
      structured = { field: { name: "invoice_number", type: "string" }, extracted_value: "4471",
                     question: "Does `extracted_value` match `source_text`?" }
      qs = S1::Questions.coerce { |q| q.noul :escalate, structured }
      state = { source_text: "Invoice #4471", messages: [{ text: "hi" }] }

      described_class.new.call(S1::Request.new(state: state, questions: qs, model: "jev-latest"))

      expect(sent["state"]).to eq("source_text" => "Invoice #4471", "messages" => [{ "text" => "hi" }])
      expect(sent["questions"]["escalate"]["instructions"]).to eq(
        "field" => { "name" => "invoice_number", "type" => "string" }, "extracted_value" => "4471",
        "question" => "Does `extracted_value` match `source_text`?"
      )
    end

    it "uses a configured or explicit base_url" do
      S1.config.typesafe.base_url = "http://localhost:8000"
      configured = stub_request(:post, "http://localhost:8000/v1/systemone").to_return(status: 200, body: ok_body)
      explicit = stub_request(:post, "https://staging.typesafe.ai/v1/systemone").to_return(status: 200, body: ok_body)

      described_class.new.call(request)
      described_class.new(base_url: "https://staging.typesafe.ai").call(request)

      expect(configured).to have_been_requested.once
      expect(explicit).to have_been_requested.once
    end

    it "sends the request timeout to Net::HTTP" do
      stub_ok
      http = nil
      allow(Net::HTTP).to(receive(:new).and_wrap_original { |m, *args| http = m.call(*args) })

      described_class.new.call(request.with(timeout: 7))

      expect(http.open_timeout).to eq(7)
      expect(http.read_timeout).to eq(7)
      expect(http.use_ssl?).to be(true)
    end

    it "raises AuthenticationError before any HTTP call without an API key" do
      S1.config.typesafe.api_key = nil
      expect { described_class.new.call(request) }.to raise_error(S1::AuthenticationError, /no API key/)
      expect { described_class.new(api_key: "").call(request) }.to raise_error(S1::AuthenticationError)
      expect(a_request(:post, url)).not_to have_been_made
    end
  end

  describe "response parsing" do
    let(:result) do
      stub_ok
      described_class.new.call(request)
    end

    it "builds a Result with usage, model and provider" do
      expect(result).to be_a(S1::Result)
      expect(result.provider).to eq(:typesafe)
      expect(result.model).to eq("jev-latest")
      expect(result.usage).to eq(input_tokens: 490, output_tokens: 86)
      expect(result.input_tokens).to eq(490)
      expect(result.output_tokens).to eq(86)
      expect(result.raw["answers"]).to eq(answers)
      expect(result.answers.keys).to eq(%i[escalate department severity])
    end

    it "normalizes a noul" do
      noul = result[:escalate]
      expect(noul).to be_a(S1::Answer::Noul)
      expect(noul.to_f).to eq(0.94)
      expect(noul.true?).to be(true)
      expect(noul.probabilities["true"]).to eq(0.94)
      expect(noul.probabilities["false"]).to be_within(1e-9).of(0.06)
      expect(noul.raw).to eq("noul" => 0.94)
    end

    it "normalizes a choice" do
      choice = result[:department]
      expect(choice).to be_a(S1::Answer::Choice)
      expect(choice.to_sym).to eq(:billing)
      expect(choice[:returns]).to eq(0.1)
      expect(choice.probabilities.keys).to eq(%w[returns billing shipping])
      expect(choice.confidence).to eq(0.85)
      expect(choice.raw).to eq(answers["department"])
    end

    it "normalizes a score" do
      score = result[:severity]
      expect(score).to be_a(S1::Answer::Score)
      expect(score.to_f).to eq(1.68)
      expect(score.index).to eq(2)
      expect(score.level).to eq("Blocking")
      expect(score.levels).to eq(%w[Cosmetic Degraded Blocking])
      expect(score.legend).to eq(0 => "Cosmetic", 1 => "Degraded", 2 => "Blocking")
      expect(score.confidence).to eq(0.73)
    end

    it "defaults usage when absent" do
      stub_ok(JSON.generate(answers: answers))
      r = described_class.new.call(request)
      expect(r.usage).to eq({})
      expect(r.input_tokens).to eq(0)
      expect(r.model).to be_nil
    end

    it "raises ValidationError when a question has no answer" do
      stub_ok(JSON.generate(answers: answers.except("severity")))
      expect { described_class.new.call(request) }
        .to raise_error(S1::ValidationError, "no answer returned for :severity")
    end

    it "raises ValidationError when an answer is missing its fields" do
      stub_ok(JSON.generate(answers: answers.merge("department" => { "choice" => "billing" })))
      expect { described_class.new.call(request) }
        .to raise_error(S1::ValidationError, /malformed answer for choice.*probabilities/)
    end

    it "raises ValidationError on an unparseable body" do
      stub_ok("<html>nope</html>")
      expect { described_class.new.call(request) }
        .to raise_error(S1::ValidationError, /unparseable response/)
    end
  end

  describe "error mapping" do
    subject(:provider) { described_class.new(max_retries: 0) }

    def stub_error(status, body = { detail: "nope" }, headers = {})
      stub_request(:post, url).to_return(status: status, body: JSON.generate(body), headers: headers)
    end

    it "maps 401 and 403 to AuthenticationError" do
      stub_error(401, detail: "invalid api key")
      expect { provider.call(request) }.to raise_error(S1::AuthenticationError, "typesafe 401: invalid api key")
      stub_error(403)
      expect { provider.call(request) }.to raise_error(S1::AuthenticationError, /403/)
    end

    it "maps 400 to InvalidRequestError" do
      stub_error(400, detail: "bad model")
      expect { provider.call(request) }.to raise_error(S1::InvalidRequestError, "typesafe 400: bad model")
    end

    it "maps 422 to ValidationError with the detail messages joined" do
      stub_error(422, detail: [{ "loc" => %w[body questions], "msg" => "field required" },
                               { "msg" => "value is not a valid float" }])
      expect { provider.call(request) }
        .to raise_error(S1::ValidationError, "typesafe 422: field required; value is not a valid float")
    end

    it "maps 429 to RateLimitError with retry_after from Retry-After" do
      stub_error(429, { detail: "slow down" }, { "Retry-After" => "2" })
      expect { provider.call(request) }.to raise_error(S1::RateLimitError) { |e|
        expect(e.message).to eq("typesafe 429: slow down")
        expect(e.retry_after).to eq(2.0)
        expect(e).to be_a(S1::TransientError)
      }
    end

    it "leaves retry_after nil without the header" do
      stub_error(429)
      expect { provider.call(request) }.to raise_error(S1::RateLimitError) { |e| expect(e.retry_after).to be_nil }
    end

    it "maps 5xx to ServerError" do
      [500, 502, 503, 529].each do |status|
        stub_error(status, detail: "boom")
        expect { provider.call(request) }.to raise_error(S1::ServerError, "typesafe #{status}: boom")
      end
    end

    it "maps other statuses to InvalidRequestError" do
      stub_error(418)
      expect { provider.call(request) }.to raise_error(S1::InvalidRequestError, /418/)
    end

    it "falls back to the raw body when the error body is not JSON" do
      stub_request(:post, url).to_return(status: 502, body: "<html>Bad Gateway</html>")
      expect { provider.call(request) }.to raise_error(S1::ServerError, "typesafe 502: <html>Bad Gateway</html>")
    end

    it "maps timeouts to TimeoutError" do
      stub_request(:post, url).to_timeout
      expect { provider.call(request) }.to raise_error(S1::TimeoutError)
    end

    it "maps connection refused to ConnectionError" do
      stub_request(:post, url).to_raise(Errno::ECONNREFUSED)
      expect { provider.call(request) }.to raise_error(S1::ConnectionError)
    end

    it "maps DNS failures to ConnectionError" do
      stub_request(:post, url).to_raise(SocketError.new("getaddrinfo: nodename nor servname provided"))
      expect { provider.call(request) }.to raise_error(S1::ConnectionError, /getaddrinfo/)
    end
  end

  describe "retries" do
    subject(:provider) { described_class.new(max_retries: 2) }

    before do
      allow_any_instance_of(described_class).to receive(:sleep)
      allow(provider).to receive(:sleep)
    end

    it "recovers from a 503 followed by a 200" do
      stub = stub_request(:post, url).to_return({ status: 503, body: "{}" }, { status: 200, body: ok_body })

      result = provider.call(request)

      expect(result[:escalate].to_f).to eq(0.94)
      expect(stub).to have_been_requested.times(2)
      expect(provider).to have_received(:sleep).with(0.5).once
    end

    it "backs off exponentially" do
      stub_request(:post, url).to_return({ status: 500, body: "{}" }, { status: 502, body: "{}" },
                                         { status: 200, body: ok_body })
      provider.call(request)
      expect(provider).to have_received(:sleep).with(0.5).ordered
      expect(provider).to have_received(:sleep).with(1.0).ordered
    end

    it "honors Retry-After on a 429" do
      stub_request(:post, url).to_return({ status: 429, body: "{}", headers: { "Retry-After" => "3" } },
                                         { status: 200, body: ok_body })
      provider.call(request)
      expect(provider).to have_received(:sleep).with(3.0).once
    end

    it "retries timeouts and connection errors" do
      stub = stub_request(:post, url).to_timeout.then.to_raise(Errno::ECONNRESET).then
                                     .to_return(status: 200, body: ok_body)
      expect(provider.call(request)[:escalate].to_f).to eq(0.94)
      expect(stub).to have_been_requested.times(3)
    end

    it "raises the transient error once retries are exhausted" do
      stub = stub_request(:post, url).to_return(status: 503, body: JSON.generate(detail: "down"))
      expect { provider.call(request) }.to raise_error(S1::ServerError, "typesafe 503: down")
      expect(stub).to have_been_requested.times(3)
      expect(provider).to have_received(:sleep).twice
    end

    it "does not retry a 400" do
      stub = stub_request(:post, url).to_return(status: 400, body: JSON.generate(detail: "bad"))
      expect { provider.call(request) }.to raise_error(S1::InvalidRequestError)
      expect(stub).to have_been_requested.once
      expect(provider).not_to have_received(:sleep)
    end

    it "does not retry a 422 or a 401" do
      stub = stub_request(:post, url).to_return({ status: 422, body: "{}" }, { status: 401, body: "{}" })
      expect { provider.call(request) }.to raise_error(S1::ValidationError)
      expect { provider.call(request) }.to raise_error(S1::AuthenticationError)
      expect(stub).to have_been_requested.times(2)
      expect(provider).not_to have_received(:sleep)
    end

    it "reads max_retries from config by default" do
      S1.config.typesafe.max_retries = 1
      stub = stub_request(:post, url).to_return(status: 503, body: "{}")
      expect { described_class.new.call(request) }.to raise_error(S1::ServerError)
      expect(stub).to have_been_requested.times(2)
    end
  end
end
