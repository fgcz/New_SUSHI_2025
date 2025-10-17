# Minimal SushiFabric stub for parsing SUSHI App files
# This stub provides the minimum necessary classes and methods
# to load and instantiate SUSHI App classes without requiring
# the full sushi_fabric gem infrastructure

module SushiFabric
  class SushiApp
    attr_accessor :name, :analysis_category, :description, :required_columns, 
                  :required_params, :modules, :inherit_tags, :inherit_columns
    attr_reader :params
    
    def initialize
      @name = ''
      @analysis_category = ''
      @description = ''
      @required_columns = []
      @required_params = []
      @params = SushiParams.new
      @modules = []
      @inherit_tags = []
      @inherit_columns = []
    end
    
    # Stub methods that apps may call
    def dataset_has_column?(column_name)
      false
    end
    
    def extract_columns(options = {})
      {}
    end
    
    def run_RApp(app_name)
      ""
    end
    
    def run_PyApp(app_name, options = {})
      ""
    end
  end
  
  # SushiParams behaves like a Hash but also tracks metadata
  class SushiParams
    def initialize
      @params = {}
      @metadata = {}
    end
    
    def []=(*args)
      if args.size == 3
        # Handle metadata like @params['ram', 'description'] = "GB"
        # This comes in as ['ram', 'description', 'GB']
        param_name, meta_key, value = args
        @metadata[param_name] ||= {}
        @metadata[param_name][meta_key] = value
      elsif args.size == 2
        # Handle regular param like @params['ram'] = 15
        key, value = args
        @params[key] = value
      else
        raise ArgumentError, "wrong number of arguments (given #{args.size}, expected 2..3)"
      end
    end
    
    def [](key)
      @params[key]
    end
    
    def each(&block)
      @params.each(&block)
    end
    
    def keys
      @params.keys
    end
    
    def to_h
      @params.dup
    end
    
    def metadata_for(key)
      @metadata[key] || {}
    end
    
    def all_metadata
      @metadata
    end
  end
end

