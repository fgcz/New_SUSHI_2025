# frozen_string_literal: true

# NEW SUSHI side of the extract_columns oracle.
#
# Loads backend/lib/global_variables.rb standalone. That file carries both the
# extract_columns family and New SUSHI's own get_columns_with_tag override, which is
# exactly what SushiFabric::SushiApp mixes in — so this harness exercises the production
# code path without booting Rails.
#
# Usage: see README.md

require 'json'
require_relative 'oracle_cases'

NEW_ROOT = ENV['NEW_SUSHI_LIB'] ||
           File.expand_path('../../backend/lib', __dir__)

$VERBOSE = nil
load File.join(NEW_ROOT, 'global_variables.rb')

class NewApp
  include GlobalVariables
  attr_accessor :params

  def initialize
    @params = {}
    @dataset_hash = []
    @dataset = []
  end
end

unless NewApp.new.respond_to?(:get_columns_with_tag)
  raise 'harness must exercise New SUSHI get_columns_with_tag, but the mixin did not provide it'
end

puts JSON.pretty_generate(run_all_cases(-> { NewApp.new }))
