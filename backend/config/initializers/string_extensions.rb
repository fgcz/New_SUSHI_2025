# String extensions for SUSHI compatibility
# The tag? method checks whether a dataset column header carries a given tag.

class String
  # Does this header carry `tag_name` among its bracketed tags?
  #
  #   "Read1 [File]".tag?('File')       # => true
  #   "IGV [Link,File]".tag?('File')    # => true   <- multi-tag
  #   "Genotype [Factor]".tag?('File')  # => false
  #
  # Port of legacy SushiApp's String#tag? (sushi_fabric/sushiApp.rb:180-182):
  #
  #   scan(/\[(.*)\]/).flatten.join =~ /#{tag}/
  #
  # i.e. collect the bracket CONTENTS and match the tag as a substring of them.
  # This file used to be `include?("[#{tag_name}]")`, which requires the tag to be
  # the entire bracket content and so returned false for every multi-tag header:
  # IGV [Link,File], StrandFile [Link,File], PreprocessingLog [File,Link],
  # Bowtie2Log [File,Link], DupMetrics [File,Link], Count [File,Link],
  # Stats [File,Link], ResultDir [File,Link], SecondRefCoverage [File,Link] —
  # 10 of the 28 File-bearing headers across the allow-listed apps. That made
  # DataSet#paths / #sample_paths / #file_paths / #recount_completed_samples blind
  # to those columns, and it is why the gStore copy set cannot be derived from
  # next_dataset until this is right: with the old rule FeatureCounts and
  # CellRangerMulti declare zero File outputs and would publish an empty result dir.
  #
  # The tag is interpolated as a regex exactly as legacy does — deliberately NOT
  # Regexp.escape'd, so this stays byte-for-byte the same predicate as the oracle.
  # Safe for the tags actually in use (File, Link, Factor, B-Fabric).
  def tag?(tag_name)
    !(scan(/\[(.*)\]/).flatten.join =~ /#{tag_name}/).nil?
  end
end
