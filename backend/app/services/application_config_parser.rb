# Service to parse SUSHI Application Ruby files and extract configuration
# This service loads *App.rb files from the apps directory and extracts
# metadata, parameters, and form field definitions
class ApplicationConfigParser
  # Title for the leading group, which legacy leaves unnamed (its form simply
  # starts, and an 'hr-header' introduces every later section).
  DEFAULT_GROUP_TITLE = 'Parameters'.freeze

  class << self
    # Parse a SUSHI application file and return its configuration
    # @param app_name [String] The application name (e.g., 'Fastqc')
    # @return [Hash, nil] Configuration hash or nil if app not found
    def parse(app_name)
      app_class = LegacyAppLoader.load(app_name)
      return nil unless app_class

      begin
        extract_config(app_class)
      rescue StandardError => e
        Rails.logger.error("Error parsing #{app_name}App: #{e.message}")
        Rails.logger.error(e.backtrace.join("\n"))
        nil
      end
    end

    # List all available application names (native + allow-listed legacy)
    # @return [Array<String>] Array of application names
    def list_apps
      LegacyAppLoader.list_apps
    end

    private

    def extract_config(app_class)
      class_name = app_class.name

      # Create an instance to extract configuration
      instance = app_class.new
      form_fields = extract_form_fields(instance)

      # Extract configuration
      {
        name: instance.name,
        class_name: class_name,
        analysis_category: instance.analysis_category,
        description: clean_description(instance.description),
        required_columns: instance.required_columns,
        required_params: instance.required_params,
        form_fields: form_fields,
        param_groups: build_param_groups(form_fields),
        modules: instance.modules,
        inherit_tags: instance.inherit_tags,
        inherit_columns: instance.inherit_columns
      }
    end

    # The same fields as +form_fields+, split into the sections legacy draws.
    # A field carrying an 'hr-header' opens a new section and stays a normal,
    # editable field inside it — legacy renders the header as its own table row
    # and then falls through to the regular input
    # (set_parameters.html.erb:78-84 followed by :128-157).
    def build_param_groups(fields)
      fields.each_with_object([]) do |field, groups|
        header = field[:section_header].to_s.strip

        if header.empty?
          groups << new_param_group(DEFAULT_GROUP_TITLE, groups) if groups.empty?
        else
          groups << new_param_group(header, groups)
        end

        groups.last[:fields] << field
      end
    end

    def new_param_group(title, groups)
      base = title.to_s.parameterize(separator: '_')
      base = "group_#{groups.size + 1}" if base.empty?

      id = base
      suffix = 2
      while groups.any? { |group| group[:id] == id }
        id = "#{base}_#{suffix}"
        suffix += 1
      end

      { id: id, title: title.to_s, fields: [] }
    end
    
    def extract_form_fields(instance)
      params = instance.params
      metadata = params.all_metadata
      fields = []
      
      params.each do |key, value|
        next if key.to_s.empty?
        
        field = build_field_definition(key, value, metadata[key] || {})
        fields << field
      end
      
      fields
    end
    
    def build_field_definition(key, value, meta)
      field = {
        name: key.to_s,
        type: infer_field_type(value, meta),
        default_value: extract_default_value(value),
        description: meta['description'] || meta[:description]
      }
      
      # Special handling for partition field - get options from config/SLURM
      if key.to_s == 'partition'
        partitions = SushiConfigHelper.available_partitions
        field[:type] = 'select'
        field[:options] = partitions
        field[:default_value] = SushiConfigHelper.default_partition
      # Add options for select fields
      elsif value.is_a?(Array)
        field[:options] = value
      # A Hash param (refBuild is the one every app carries) is a label => value
      # selector: legacy submits the VALUE and shows the key
      # (set_parameters.html.erb:133-134, :151-152).
      elsif value.is_a?(Hash)
        field[:options] = value.values.map(&:to_s)
        field[:option_labels] = value.keys.map(&:to_s) if value.keys.map(&:to_s) != value.values.map(&:to_s)
      end
      
      # Add multi_selection flag if present
      if meta['multi_selection'] || meta[:multi_selection]
        field[:multi_selection] = true
        field[:selected] = meta['selected'] || meta[:selected]
      end
      
      # Add hr-header for section headers
      if meta['hr-header'] || meta[:'hr-header']
        field[:section_header] = meta['hr-header'] || meta[:'hr-header']
      end
      
      # Add hr flag for horizontal rule
      if meta['hr'] || meta[:hr]
        field[:horizontal_rule] = true
      end
      
      field.compact
    end
    
    def infer_field_type(value, meta)
      case value
      when Hash
        'select'
      when Array
        if meta['multi_selection'] || meta[:multi_selection]
          'multi_select'
        else
          'select'
        end
      when TrueClass, FalseClass
        'boolean'
      when Integer
        'integer'
      when Float
        'float'
      when Numeric
        'number'
      else
        'text'
      end
    end
    
    def extract_default_value(value)
      case value
      when Array
        value.first
      when Hash
        # Legacy pre-selects nothing, so the first entry wins — for refBuild that
        # is the {'select' => ''} placeholder, i.e. "not chosen yet".
        value.values.first
      else
        value
      end
    end
    
    def clean_description(description)
      return '' if description.nil?
      
      # Remove excessive whitespace and newlines
      description.to_s.strip.gsub(/\s+/, ' ')
    end
  end
end

