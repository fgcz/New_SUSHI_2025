# frozen_string_literal: true

# LEGACY side of the extract_columns oracle.
#
# Loads the REAL legacy GlobalVariables module, and the REAL legacy
# SushiApp#get_columns_with_tag extracted VERBATIM from sushiApp.rb — the method text is
# read out of the file and class_eval'd rather than copied by hand, so the oracle cannot
# drift from legacy through a transcription mistake.
#
# The legacy module references Rails.cache and SushiFabric::Application.config, but only
# inside ref_selector / job-script helpers, so loading it outside Rails is safe as long as
# the oracle only calls the extract_columns family.
#
# Usage: see README.md

require 'json'
require_relative 'oracle_cases'

LEGACY_ROOT = ENV['LEGACY_APPS_DIR'] || '/srv/sushi/masa_test_sushi_20260416/master/lib'

$VERBOSE = nil
load File.join(LEGACY_ROOT, 'global_variables.rb')

SUSHI_APP_RB = File.join(LEGACY_ROOT, 'sushi_fabric/lib/sushi_fabric/sushiApp.rb')
src = File.readlines(SUSHI_APP_RB)
start_i = src.index { |l| l =~ /^\s*def get_columns_with_tag\b/ }
raise "get_columns_with_tag not found in #{SUSHI_APP_RB}" unless start_i

end_i = (start_i + 1...src.size).find { |i| src[i] =~ /^  end\s*$/ }
raise "could not find the end of get_columns_with_tag in #{SUSHI_APP_RB}" unless end_i

METHOD_SRC = src[start_i..end_i].join
warn "--- legacy get_columns_with_tag, verbatim from #{SUSHI_APP_RB}:#{start_i + 1} ---"
warn METHOD_SRC

class LegacyApp
  include GlobalVariables
  attr_accessor :params

  def initialize
    @params = {}
    @dataset_hash = []
    @dataset = []
  end

  class_eval(METHOD_SRC)
end

puts JSON.pretty_generate(run_all_cases(-> { LegacyApp.new }))
