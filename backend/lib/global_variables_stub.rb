# Stub for global_variables.rb
# Provides minimal functionality for loading SUSHI App files

module GlobalVariables
  SUSHI = 'Supercalifragilisticexpialidocious!!'
  
  # Stub method for reference selector
  def ref_selector(options = {})
    # Return empty hash - apps won't actually use this in config parsing
    {}
  end
  
  # Stub for c() method (R-style vector creation)
  def c(*list)
    list
  end
end

# Make c() available globally like in original
def c(*list)
  list
end

