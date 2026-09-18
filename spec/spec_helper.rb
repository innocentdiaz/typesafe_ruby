# frozen_string_literal: true

require "json"

require "s1"
require "webmock/rspec"

WebMock.disable_net_connect!

RSpec.configure do |config|
  config.example_status_persistence_file_path = ".rspec_status"
  config.disable_monkey_patching!
  config.expect_with(:rspec) { |c| c.syntax = :expect }

  config.before do
    S1.reset_config!
    S1.clear_hooks!
  end
end
