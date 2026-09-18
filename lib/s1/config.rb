# frozen_string_literal: true

module S1
  class Config
    attr_accessor :provider, :timeout, :threshold, :logger, :primitives, :context, :cache, :symbol

    # One provider's settings, declared with Providers::Base.settings. A callable
    # default (an ENV lookup) is evaluated when the Config is built.
    class Section
      def initialize(defaults)
        @keys = defaults.keys
        defaults.each do |key, value|
          singleton_class.attr_accessor(key)
          public_send(:"#{key}=", value.respond_to?(:call) ? value.call : value)
        end
      end

      def to_h = @keys.to_h { |k| [k, public_send(k)] }
    end

    class << self
      def sections = (@sections ||= {})

      # Declares a provider section: Config#<name> returns its Section.
      def register(name, defaults)
        sections[name.to_sym] = defaults
        define_method(name) { section_for(name.to_sym) } unless method_defined?(name)
      end
    end

    def initialize
      @provider   = :typesafe      # resolves to S1::Providers::TypeSafe: a name under Providers, or an instance
      @timeout    = 30             # seconds, per request
      @threshold  = 0.5            # a noul at or above this reads as true (noul?, Answer::Noul#true?)
      @logger     = nil
      @primitives = false          # true (String/Hash/Array) or a subset: opt-in core extension, see S1::Primitives
      @context    = nil            # where S1.subject lives: anything with []/[]= (default Thread.current)
      @cache      = nil            # anything with fetch(key) { }; consumers that can version their state use it (typesafe-rails)
      @symbol     = false          # true defines ψ(x) — anything becomes a Subject; or any identifier: "⍣", "Subject"
      @sections   = self.class.sections.transform_values { |defaults| Section.new(defaults) }
    end

    # A provider's settings as constructor keywords; {} when it declared none.
    def section(name)
      self.class.sections.key?(name&.to_sym) ? section_for(name.to_sym).to_h : {}
    end

    # The Kernel function name `symbol` asks for: ψ for true, the given name, or nil when off.
    def symbol_name
      case symbol
      when true       then "ψ"
      when nil, false then nil
      else symbol.to_s
      end
    end

    private

    def section_for(name)
      @sections[name] ||= Section.new(self.class.sections.fetch(name))
    end
  end
end
