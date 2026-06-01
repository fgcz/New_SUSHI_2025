require 'csv'

# Helper method to convert datetime strings with timezone to MySQL-compatible format
def convert_datetime_for_mysql(value)
  return value if value.nil? || value.empty?
  
  # Check if value looks like a datetime with timezone (e.g., "2025-04-01 15:07:02 +0200")
  if value =~ /\A\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} [+-]\d{4}\z/
    # Parse and convert to MySQL-compatible format (without timezone)
    Time.parse(value).strftime('%Y-%m-%d %H:%M:%S')
  else
    value
  end
rescue ArgumentError
  # If parsing fails, return original value
  value
end

def quote_value(value, column_name = nil)
  converted = convert_datetime_for_mysql(value)
  ActiveRecord::Base.connection.quote(converted)
end

ActiveRecord::Base.connection.disable_referential_integrity do
  Dir.glob("db/csv_data/*.csv").each do |file|
    table = File.basename(file, ".csv")
    puts "Importing #{table}..."

    csv = CSV.read(file, headers: true)
    
    # Table-specific processing
    case table
    when 'users'
      csv.each do |row|
        # Special processing for users table
        # Generate email as login + @example.com if email field is not in CSV
        # Set default value if encrypted_password field is not in CSV
        email = row['email'] || "#{row['login']}@example.com"
        encrypted_password = row['encrypted_password'] || '$2a$12$dummy.hash.for.imported.users'
        
        # Extract only required fields
        available_columns = csv.headers + ['email', 'encrypted_password']
        available_columns = available_columns.uniq
        
        values = available_columns.map do |col|
          case col
          when 'email'
            ActiveRecord::Base.connection.quote(email)
          when 'encrypted_password'
            ActiveRecord::Base.connection.quote(encrypted_password)
          else
            quote_value(row[col], col)
          end
        end
        
        ActiveRecord::Base.connection.execute <<-SQL
          INSERT INTO #{table} (#{available_columns.join(',')})
          VALUES (#{values.join(',')})
        SQL
      end
    else
      # Process other tables normally
      csv.each do |row|
        ActiveRecord::Base.connection.execute <<-SQL
          INSERT INTO #{table} (#{csv.headers.join(',')})
          VALUES (#{csv.headers.map { |h| quote_value(row[h], h) }.join(',')})
        SQL
      end
    end
  end
end
