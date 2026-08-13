#!/usr/bin/env ruby
# encoding: utf-8
# Fixture whose name has FooBar as a strict prefix. It exists ONLY to pin that the
# allow-list is matched by exact (case-insensitive) equality, never by prefix: the real
# legacy dir holds CellRangerApp.rb next to CellRangerARCApp.rb, CellRangerATACApp.rb and
# CellRangerAggrApp.rb, so allow-listing 'CellRanger' must not expose the other three.
require 'sushi_fabric'
require_relative 'global_variables'
include GlobalVariables

class FooBarExtraApp < SushiFabric::SushiApp
  def initialize
    super
    @name = 'FooBarExtra'
    @params['process_mode'] = 'DATASET'
    @analysis_category = 'Test'
    @description = 'Fixture legacy app sharing a prefix with FooBarApp'
    @required_columns = ['Name']
  end

  def next_dataset
    { 'Name' => 'foobarextra_out' }
  end
end
