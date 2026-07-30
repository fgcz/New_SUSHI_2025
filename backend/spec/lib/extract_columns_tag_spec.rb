require 'rails_helper'
require Rails.root.join('lib', 'sushi_fabric').to_s

# Regression for the inherited-column tag-doubling bug: get_columns_with_tag must strip
# the tag from the matched key so extract_column re-adds it exactly once. Before the fix
# an inherited "Genotype [Factor]" became "Genotype [Factor] [Factor]" (and in SAMPLE mode
# the @dataset lookup missed, yielding nil), corrupting every output dataset that inherits
# Factor/B-Fabric columns.
RSpec.describe 'GlobalVariables#extract_columns tag handling' do
  let(:app) { SushiFabric::SushiApp.new }

  before do
    app.instance_variable_set(:@dataset_hash, [
      { 'Name' => 's1', 'Genotype [Factor]' => 'mut', 'Order Id [B-Fabric]' => '123' },
      { 'Name' => 's2', 'Genotype [Factor]' => 'wt',  'Order Id [B-Fabric]' => '124' }
    ])
  end

  it 'DATASET mode: single tag, values aggregated across samples' do
    app.params['process_mode'] = 'DATASET'
    app.instance_variable_set(:@dataset, app.instance_variable_get(:@dataset_hash))
    out = app.extract_columns(tags: %w[Factor B-Fabric])
    expect(out.keys).to contain_exactly('Genotype [Factor]', 'Order Id [B-Fabric]')
    expect(out['Genotype [Factor]']).to eq('mut,wt')
  end

  it 'SAMPLE mode: single tag, per-sample value (cleaned @dataset hash)' do
    app.params['process_mode'] = 'SAMPLE'
    app.instance_variable_set(:@dataset, { 'Name' => 's1', 'Genotype' => 'mut', 'Order Id' => '123' })
    out = app.extract_columns(tags: %w[Factor B-Fabric])
    expect(out.keys).to contain_exactly('Genotype [Factor]', 'Order Id [B-Fabric]')
    expect(out['Genotype [Factor]']).to eq('mut')
    expect(out['Order Id [B-Fabric]']).to eq('123')
  end

  it 'normalizes an already-doubled input tag to a single tag' do
    app.instance_variable_set(:@dataset_hash, [{ 'Name' => 's1', 'Genotype [Factor] [Factor]' => 'mut' }])
    app.params['process_mode'] = 'DATASET'
    app.instance_variable_set(:@dataset, app.instance_variable_get(:@dataset_hash))
    out = app.extract_columns(tags: %w[Factor])
    expect(out.keys).to eq(['Genotype [Factor]'])
  end
end

# Follow-up from the 2026-07-21 oracle diff: legacy inherits [Characteristic] columns too,
# but the test input used back then had none, so that path was unverified. Every expectation
# below was produced by running the SAME inputs through the REAL legacy implementation
# (legacy lib/global_variables.rb plus SushiApp#get_columns_with_tag taken verbatim from
# lib/sushi_fabric/lib/sushi_fabric/sushiApp.rb) and is reproduced here byte-for-byte.
# If one of these ever needs "fixing", check legacy first — matching it is the contract.
RSpec.describe 'GlobalVariables#extract_columns [Characteristic] inheritance (legacy oracle)' do
  let(:app) { SushiFabric::SushiApp.new }

  let(:dataset_hash) do
    [
      { 'Name' => 's1', 'Species' => 'Homo sapiens', 'Genotype [Factor]' => 'mut',
        'Tissue [Characteristic]' => 'liver', 'Age [Characteristic]' => '55',
        'Order Id [B-Fabric]' => '123', 'Read1 [File]' => 'p/s1_R1.fastq.gz' },
      { 'Name' => 's2', 'Species' => 'Homo sapiens', 'Genotype [Factor]' => 'wt',
        'Tissue [Characteristic]' => 'brain', 'Age [Characteristic]' => '61',
        'Order Id [B-Fabric]' => '124', 'Read1 [File]' => 'p/s2_R1.fastq.gz' }
    ]
  end

  let(:tags) { %w[Factor Characteristic B-Fabric] }

  before do
    app.instance_variable_set(:@dataset_hash, dataset_hash)
  end

  def dataset_mode!
    app.params['process_mode'] = 'DATASET'
    app.instance_variable_set(:@dataset, dataset_hash)
  end

  # legacy sample_mode hands next_dataset a single tag-stripped row
  def sample_mode!(row)
    app.params['process_mode'] = 'SAMPLE'
    app.instance_variable_set(
      :@dataset, Hash[*row.map { |k, v| [k.gsub(/\[.+\]/, '').strip, v] }.flatten]
    )
  end

  it 'DATASET mode: inherits Characteristic alongside Factor and B-Fabric' do
    dataset_mode!
    expect(app.extract_columns(tags: tags)).to eq(
      'Genotype [Factor]' => 'mut,wt',
      'Tissue [Characteristic]' => 'liver,brain',
      'Age [Characteristic]' => '55,61',
      'Order Id [B-Fabric]' => '123,124'
    )
  end

  it 'DATASET mode: Characteristic on its own keeps every Characteristic column' do
    dataset_mode!
    expect(app.extract_columns(tags: %w[Characteristic])).to eq(
      'Tissue [Characteristic]' => 'liver,brain',
      'Age [Characteristic]' => '55,61'
    )
  end

  it 'DATASET mode: sample_name picks that row rather than aggregating' do
    dataset_mode!
    expect(app.extract_columns(tags: tags, sample_name: 's2')).to eq(
      'Genotype [Factor]' => 'wt',
      'Tissue [Characteristic]' => 'brain',
      'Age [Characteristic]' => '61',
      'Order Id [B-Fabric]' => '124'
    )
  end

  it 'SAMPLE mode: per-sample Characteristic value, single tag' do
    sample_mode!(dataset_hash[0])
    expect(app.extract_columns(tags: tags)).to eq(
      'Genotype [Factor]' => 'mut',
      'Tissue [Characteristic]' => 'liver',
      'Age [Characteristic]' => '55',
      'Order Id [B-Fabric]' => '123'
    )
  end

  it 'colnames path re-attaches each column own tag (DESeq2App style)' do
    dataset_mode!
    expect(app.extract_columns(colnames: ['Order Id', 'Tissue'])).to eq(
      'Tissue [Characteristic]' => 'liver,brain',
      'Order Id [B-Fabric]' => '123,124'
    )
  end

  it 'positional-args form is treated as tags (CellBenderApp style)' do
    dataset_mode!
    expect(app.extract_columns(%w[Factor Characteristic])).to eq(
      'Genotype [Factor]' => 'mut,wt',
      'Tissue [Characteristic]' => 'liver,brain',
      'Age [Characteristic]' => '55,61'
    )
  end

  # Legacy quirk, deliberately preserved: extract_columns is `if tags ... elsif colnames`,
  # so passing both silently drops colnames. Verified against legacy — do NOT "fix" this
  # in isolation, it would make output datasets diverge from the legacy system.
  it 'tags win over colnames when both are given, and colnames are dropped' do
    dataset_mode!
    expect(app.extract_columns(tags: %w[Characteristic], colnames: ['Order Id'])).to eq(
      'Tissue [Characteristic]' => 'liver,brain',
      'Age [Characteristic]' => '55,61'
    )
  end
end
