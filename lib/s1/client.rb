# frozen_string_literal: true

module S1
  # The rail: build a Request, resolve the provider by name, get a Result back.
  # Everything above this (Subject, Questions) is sugar; everything below it
  # (Providers) is a cart.
  module Client
    def ask(state, questions, provider: nil, model: nil, timeout: nil, **options)
      request = Request.new(
        state: state,
        questions: Questions.coerce(questions),
        model: model,
        timeout: timeout || S1.config.timeout,
        options: options
      )
      impl = resolve_provider(provider)
      request.questions.each do |id, q| # a bare callable answers everything; Providers::Base declares
        next unless impl.respond_to?(:supports?) && !impl.supports?(q)

        raise UnsupportedError, "#{impl.name} cannot answer a #{q.type} (#{id.inspect})"
      end
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = impl.call(request)
      result = result.with(duration_ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round)
      hooks.each { |hook| hook.call(result, request) }
      result
    end

    def state(state, **) = Subject.new(state, **)

    # Ambient subject for the bare primitives (noul?/choice/score/ask with no
    # receiver). Lives in config.context (Thread.current by default); the block
    # form restores the previous subject.
    #   S1.about(phone_call) { noul?("Is the caller asking for a human?") }
    #   S1.subject = phone_call    # console / long-lived scope
    def about(state, **)
      previous = context[:s1_subject]
      self.subject = S1.to_state(state, **)
      block_given? ? yield(subject) : subject
    ensure
      context[:s1_subject] = previous if block_given?
    end

    def subject=(state)
      context[:s1_subject] = state.nil? ? nil : S1.to_state(state)
    end

    def subject
      context[:s1_subject] or
        raise InvalidRequestError, "no subject: use S1.about(state) { ... } or S1.subject = state"
    end

    def context = S1.config.context || Thread.current

    # A provider is an object responding to #call(Request) -> Result. Pass an
    # instance, or a name that resolves under Providers (:typesafe -> Providers::TypeSafe),
    # built with its section of the config. No registry to maintain.
    def resolve_provider(provider = nil)
      provider ||= S1.config.provider
      return provider if provider.respond_to?(:call)

      wanted = provider.to_s.delete("_").downcase
      const = Providers.constants.find { |c| c.to_s.downcase == wanted } or
        raise InvalidRequestError, "unknown S1 provider: #{provider.inspect}"
      klass = Providers.const_get(const, false)
      klass.new(**S1.config.section(klass.settings_name))
    end

    # Observe every completed call — telemetry, cost ledgers, logging — without
    # the gem knowing anything about where that goes.
    #   S1.on_result { |result, request| record(result.usage, request.options[:owner]) }
    def on_result(&block)
      hooks << block
      block
    end

    def hooks = (@hooks ||= [])
    def clear_hooks! = @hooks = []
  end
end
