require 'rails_helper'

# Regression for the multi-tag blindness found on 2026-08-07 while porting legacy's
# gStore copy contract.
#
# config/initializers/string_extensions.rb was `self.include?("[#{tag_name}]")`, which
# requires the tag to be the ENTIRE bracket content. Legacy
# (sushi_fabric/sushiApp.rb:180-182) matches the tag as a substring of the bracket
# contents:
#
#     scan(/\[(.*)\]/).flatten.join =~ /#{tag}/
#
# so every real multi-tag header disagreed. 10 of the 28 File-bearing headers across the
# 17 allow-listed apps are multi-tag, and the divergence was not theoretical: it made
# DataSet#paths, #sample_paths, #file_paths and #recount_completed_samples blind to the
# IGV / log / metrics columns of datasets New SUSHI itself had just produced, and it
# would have made the derived gStore copy set EMPTY for FeatureCounts (Count [File,Link],
# Stats [File,Link]) and CellRangerMulti (ResultDir [File,Link]).
RSpec.describe 'String#tag?' do
  # Verbatim headers taken from real dataset.tsv files under /srv/gstore/projects/p35611
  # produced by New SUSHI runs on 2026-08-06/07.
  MULTI_TAG_FILE_HEADERS = [
    'IGV [Link,File]',              # STAR
    'StrandFile [Link,File]',       # STAR
    'IGV [File,Link]',              # Bowtie2
    'PreprocessingLog [File,Link]', # Bowtie2
    'Bowtie2Log [File,Link]',       # Bowtie2
    'DupMetrics [File,Link]',       # Bowtie2
    'Count [File,Link]',            # FeatureCounts
    'Stats [File,Link]',            # FeatureCounts
    'ResultDir [File,Link]'         # CellRangerMulti
  ].freeze

  it 'recognises a single-tag File header' do
    expect('BAM [File]'.tag?('File')).to be true
  end

  it 'recognises File in every real multi-tag header' do
    MULTI_TAG_FILE_HEADERS.each do |header|
      expect(header.tag?('File')).to be(true), "#{header.inspect} should be a File column"
    end
  end

  it 'recognises the other tag of a multi-tag header too' do
    expect('IGV [Link,File]'.tag?('Link')).to be true
    expect('Static Report [Link]'.tag?('Link')).to be true
  end

  it 'does not treat non-File columns as File columns' do
    ['Name', 'Species', 'Genotype [Factor]', 'BFabric Info [B-Fabric]',
     'Static Report [Link]', 'Read Count'].each do |header|
      expect(header.tag?('File')).to be(false), "#{header.inspect} is not a File column"
    end
  end

  it 'matches legacy SushiApp#tag? on every header shape we ship' do
    legacy = lambda { |s, tag| !(s.scan(/\[(.*)\]/).flatten.join =~ /#{tag}/).nil? }
    headers = MULTI_TAG_FILE_HEADERS + [
      'BAM [File]', 'BAI [File]', 'Name', 'Species', 'Genotype [Factor]',
      'BFabric Info [B-Fabric]', 'Order Id [B-Fabric]', 'Static Report [Link]',
      'Report [File]', 'Read1 [File]', 'Read2 [File]'
    ]
    headers.each do |header|
      %w[File Link Factor B-Fabric].each do |tag|
        expect(header.tag?(tag)).to eq(legacy.call(header, tag)),
                                    "#{header.inspect}.tag?(#{tag.inspect}) diverges from legacy"
      end
    end
  end

  it 'returns a real boolean, not the regex match offset legacy returns' do
    # Legacy returns 0 (truthy) or nil. Callers here only use it in boolean context, but
    # `expect(...).to be true` should mean what it says.
    expect('BAM [File]'.tag?('File')).to be_in([true, false])
    expect('Name'.tag?('File')).to be_in([true, false])
  end
end
