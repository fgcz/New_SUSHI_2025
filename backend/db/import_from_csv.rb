require 'csv'

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
            ActiveRecord::Base.connection.quote(row[col])
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
          VALUES (#{csv.headers.map { |h| ActiveRecord::Base.connection.quote(row[h]) }.join(',')})
        SQL
      end
    end
  end
end

