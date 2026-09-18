#!/usr/bin/env ruby
# frozen_string_literal: true

# Speaks the cua_s1_sidecar.py protocol without a model: config first, then
# for each request the option whose text contains a word of the context wins.
require "json"

$stdout.sync = true
puts JSON.generate(config: { "encoder" => "tinyx", "context_tokens" => 224, "option_tokens" => 96, "checkpoint" => ARGV[0] })
while (line = $stdin.gets)
  req = JSON.parse(line)
  hits = req["options"].map { |o| req["context"].split.count { |w| o.downcase.include?(w.downcase) } + 0.1 }
  total = hits.sum
  puts JSON.generate(probabilities: hits.map { |h| (h / total).round(4) })
end
