# String extensions for SUSHI compatibility
# The tag? method checks if a string contains a tag in the format [TagName]

class String
  # Check if string contains a specific tag like [File], [Link], [Factor], etc.
  # Example: "Read1 [File]".tag?('File') => true
  def tag?(tag_name)
    self.include?("[#{tag_name}]")
  end
end

