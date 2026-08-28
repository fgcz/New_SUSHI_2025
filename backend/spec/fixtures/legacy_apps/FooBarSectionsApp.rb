#!/usr/bin/env ruby
# encoding: utf-8
# Fixture for the form-shape contract: section headers ('hr-header') and a
# Hash-valued selector, the two things every real app form is built out of.
require 'sushi_fabric'
require_relative 'global_variables'
include GlobalVariables

class FooBarSectionsApp < SushiFabric::SushiApp
  def initialize
    super
    @name = 'FooBarSections'
    @params['process_mode'] = 'DATASET'
    @analysis_category = 'Test'
    @description = 'Fixture with section headers and a Hash-valued selector'
    @required_columns = ['Name']

    # Leading fields, before any header: they form the unnamed first section.
    @params['cores'] = [1, 2, 4]
    @params['refBuild'] = {
      'select' => '',
      'Homo_sapiens/GENCODE/GRCh38.p13' => 'Homo_sapiens/GENCODE/GRCh38.p13'
    }

    # A header rides ON a real parameter — legacy draws the header row and then
    # the field itself (set_parameters.html.erb:78-84 then :135-136).
    @params['generate_ai_summary'] = false
    @params['generate_ai_summary', 'hr-header'] = 'AI summaries'
    @params['ai_model'] = 'claude'

    @params['mail'] = ''
    @params['mail', 'hr-header'] = 'Notification'
  end

  def next_dataset
    { 'Name' => 'foobar_sections_out' }
  end
end
