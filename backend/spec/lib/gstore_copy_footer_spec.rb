require 'rails_helper'
require 'tmpdir'
require Rails.root.join('lib', 'sushi_fabric').to_s

# Regression for task #6: the gStore copy footer.
#
# The emitter used to end every job script with
#
#     for f in *; do
#       if [ -e "$f" ]; then
#         g-req -w copy \"$f\" /srv/gstore/projects/p35611/<run>
#       fi
#     done
#
# which published the WHOLE scratch temp dir. Measured against the legacy oracles in
# p35611: 16.1 MB of a STAR result dir (93% of it) was undeclared payload — trimmed
# FASTQs, fastp.html/json, adapters.fa, Log.out, SJ.out.tab, Chimeric.out.junction —
# and FeatureCounts re-published a name-sorted copy of its own input BAM. Legacy's
# job_footer (sushi_fabric/sushiApp.rb:600-648) copies only the declared outputs; the
# rest dies with the `rm -rf`. Across 8 runs the difference was 32.8 MiB.
#
# Legacy derives the declared set itself in set_output_files (sushiApp.rb:322-333) —
# every next_dataset header tagged [File]. NO legacy app writes @output_files by hand
# (grep over all 17 allow-listed apps: zero hits), so the set must be derived, never read
# off the app.
RSpec.describe 'SushiApp gStore copy footer' do
  let(:project)  { create(:project, number: 35611) }
  let(:data_set) { create(:data_set, project: project) }
  let(:scratch)  { Dir.mktmpdir('sushi-copy-footer-spec') }

  # Mirrors STARApp's real next_dataset shape, including the multi-tag headers that are
  # the whole reason String#tag? had to be fixed first.
  let(:app_class) do
    Class.new(SushiFabric::SushiApp) do
      def commands = "echo work"

      def next_dataset
        {
          'Name'                      => 'mut11',
          'BAM [File]'                => File.join(@result_dir, 'mut11.bam'),
          'BAI [File]'                => File.join(@result_dir, 'mut11.bam.bai'),
          'IGV [Link,File]'           => File.join(@result_dir, 'mut11-igv.html'),
          'StrandFile [Link,File]'    => File.join(@result_dir, 'mut11_strand.txt'),
          'PreprocessingLog [File,Link]' => File.join(@result_dir, 'mut11_preprocessing.log'),
          'Species'                   => 'Mus musculus',
          'Genotype [Factor]'         => 'mut',
          'Static Report [Link]'      => File.join(@result_dir, 'report/00index.html'),
          'BFabric Info [B-Fabric]'   => 'test1',
          'Empty [File]'              => ''
        }
      end
    end
  end

  let(:app) { app_class.new }

  # Everything the app declares as [File], in declaration order. Note the three
  # multi-tag headers and that the blank one is excluded.
  let(:declared) do
    %w[mut11.bam mut11.bam.bai mut11-igv.html mut11_strand.txt mut11_preprocessing.log]
  end

  before do
    allow(SushiConfigHelper).to receive(:scratch_dir).and_return(scratch)
    allow(SushiConfigHelper).to receive(:copy_method).and_return('g-req')
    app.name = 'STAR'
    app.dataset_sushi_id = data_set.id
    app.dataset = { 'Name' => 'mut11' }
    app.prepare_result_dir
  end

  after { FileUtils.remove_entry(scratch) if File.directory?(scratch) }

  def footer = app.send(:gstore_copy_lines).join("\n")

  describe 'what gets copied' do
    it 'copies exactly the [File]-tagged declared outputs and nothing else' do
      expect(app.send(:declared_output_copies).map(&:first)).to eq(declared)
    end

    it 'includes multi-tag headers such as [Link,File] and [File,Link]' do
      # These are 10 of the 28 File-bearing headers across the allow-listed apps. With the
      # old String#tag? (include?("[File]")) they were all invisible, which would have made
      # FeatureCounts and CellRangerMulti publish an EMPTY result dir.
      expect(footer).to include('mut11-igv.html', 'mut11_strand.txt', 'mut11_preprocessing.log')
    end

    it 'excludes Link-only, Factor, B-Fabric and untagged columns' do
      expect(footer).not_to include('00index.html')
      expect(footer).not_to include('Mus musculus', 'test1')
    end

    it 'skips headers whose value is blank' do
      expect(app.send(:declared_output_copies).map(&:first)).not_to include('')
    end

    it 'no longer globs the scratch directory' do
      script = app.generate_job_script
      expect(script).not_to include('for f in *')
      expect(script).not_to match(/\$f/)
    end
  end

  describe 'the emitted command' do
    it 'batches every output sharing a destination into ONE g-req, as legacy does' do
      lines = app.send(:gstore_copy_lines)
      expect(lines.size).to eq(1)
      expect(lines.first).to eq("g-req -w copy #{declared.join(' ')} #{app.gstore_result_dir}")
    end

    it 'passes bare basenames with no literal backslash-quotes' do
      # The old form shipped \"$f\" — literal quote characters that travelled through
      # g-req's unquoted $@ all the way into the transfer daemon's argv.
      expect(footer).not_to include('\\"')
      expect(footer).not_to include('"')
    end

    it 'emits no [ -e ] guard, so a declared-but-unwritten output fails the job loudly' do
      # Legacy has no guard and ezRun relies on that: a silently skipped copy would leave a
      # job reporting COMPLETED without its output, and the `rm -rf` then destroys the
      # scratch evidence.
      expect(footer).not_to include('[ -e')
    end

    it 'sends everything to the absolute gstore result dir' do
      expect(app.send(:declared_output_copies).map(&:last).uniq).to eq([app.gstore_result_dir])
      expect(app.gstore_result_dir).to start_with('/')
    end

    it 'still cleans up the scratch temp dir afterwards' do
      script = app.generate_job_script
      expect(script).to include("cd #{app.scratch_dir}")
      expect(script).to match(/rm -rf .+ \|\| exit 1/)
    end
  end

  describe 'when the copy method is not g-req' do
    before { allow(SushiConfigHelper).to receive(:copy_method).and_return('rsync') }

    it 'falls back to one command per file, as legacy does for non-g-req servers' do
      lines = app.send(:gstore_copy_lines)
      expect(lines.size).to eq(declared.size)
      expect(lines.first).to eq("rsync -r mut11.bam #{app.gstore_result_dir}/")
      expect(lines.join("\n")).not_to include('\\"')
    end
  end

  describe 'when the app declares no [File] outputs' do
    let(:app_class) do
      Class.new(SushiFabric::SushiApp) do
        def commands = "echo work"
        def next_dataset = { 'Name' => 'mut11', 'Species' => 'Mus musculus' }
      end
    end

    it 'copies nothing and says so, rather than falling back to copying everything' do
      expect(Rails.logger).to receive(:error).with(/no \[File\]-tagged headers/)
      lines = app.send(:gstore_copy_lines)
      expect(lines.join).not_to include('g-req')
      expect(lines.join).to include('nothing to copy')
    end
  end

  describe 'when a declared value does not resolve into the result dir' do
    let(:app_class) do
      Class.new(SushiFabric::SushiApp) do
        def commands = "echo work"
        def next_dataset
          # An absolute value is the pre-9663a8c result_dir bug resurfacing.
          { 'BAM [File]' => '/srv/gstore/projects/p35611/elsewhere/mut11.bam' }
        end
      end
    end

    it 'warns instead of silently copying to the wrong place' do
      expect(Rails.logger).to receive(:warn).with(/not the result dir/)
      app.send(:declared_output_copies)
    end
  end
end
