# frozen_string_literal: true

# Shared input fixtures + case list for the legacy-vs-New-SUSHI extract_columns oracle.
# Both oracle_legacy.rb and oracle_new.rb require this file, so the two sides cannot
# drift apart in what they are asked to compute — the only difference between the runs
# is which implementation is loaded.
#
# See README.md for how to run.

require 'json'

# One input dataset carrying every tag family an output dataset can inherit:
# [Factor], [Characteristic], [B-Fabric], plus a [File] column that must NOT be inherited.
DATASET_HASH = [
  { 'Name' => 's1', 'Species' => 'Homo sapiens', 'Genotype [Factor]' => 'mut',
    'Tissue [Characteristic]' => 'liver', 'Age [Characteristic]' => '55',
    'Order Id [B-Fabric]' => '123', 'Read1 [File]' => 'p/s1_R1.fastq.gz' },
  { 'Name' => 's2', 'Species' => 'Homo sapiens', 'Genotype [Factor]' => 'wt',
    'Tissue [Characteristic]' => 'brain', 'Age [Characteristic]' => '61',
    'Order Id [B-Fabric]' => '124', 'Read1 [File]' => 'p/s2_R1.fastq.gz' }
].freeze

TAGS = %w[Factor Characteristic B-Fabric].freeze

def strip_tags(row)
  Hash[*row.map { |k, v| [k.gsub(/\[.+\]/, '').strip, v] }.flatten]
end

def with_dataset_mode(app)
  app.instance_variable_set(:@dataset_hash, DATASET_HASH)
  app.instance_variable_set(:@dataset, DATASET_HASH)
  app.instance_variable_get(:@params)['process_mode'] = 'DATASET'
  app
end

# legacy SushiApp#sample_mode hands next_dataset a single tag-stripped row
def with_sample_mode(app, row)
  app.instance_variable_set(:@dataset_hash, DATASET_HASH)
  app.instance_variable_set(:@dataset, strip_tags(row))
  app.instance_variable_get(:@params)['process_mode'] = 'SAMPLE'
  app
end

def run_all_cases(app_factory)
  {
    'dataset_mode_tags' =>
      with_dataset_mode(app_factory.call).extract_columns(tags: TAGS),

    'dataset_mode_characteristic_only' =>
      with_dataset_mode(app_factory.call).extract_columns(tags: %w[Characteristic]),

    'dataset_mode_sample_name_s2' =>
      with_dataset_mode(app_factory.call).extract_columns(tags: TAGS, sample_name: 's2'),

    'sample_mode_s1' =>
      with_sample_mode(app_factory.call, DATASET_HASH[0]).extract_columns(tags: TAGS),

    # DESeq2App style: extract_columns(colnames: @inherit_columns)
    'dataset_mode_colnames' =>
      with_dataset_mode(app_factory.call).extract_columns(colnames: ['Order Id', 'Tissue']),

    # both kwargs at once — legacy is `if tags ... elsif colnames`, so colnames is dropped
    'dataset_mode_tags_and_colnames' =>
      with_dataset_mode(app_factory.call).extract_columns(tags: %w[Characteristic],
                                                          colnames: ['Order Id']),

    # CellBenderApp style: extract_columns(@inherit_tags)
    'dataset_mode_positional_tags' =>
      with_dataset_mode(app_factory.call).extract_columns(%w[Factor Characteristic])
  }
end
