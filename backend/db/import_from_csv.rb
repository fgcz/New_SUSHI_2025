require 'csv'

ActiveRecord::Base.connection.disable_referential_integrity do
  Dir.glob("db/csv_data/*.csv").each do |file|
    table = File.basename(file, ".csv")
    puts "Importing #{table}..."

    csv = CSV.read(file, headers: true)
    csv.each do |row|
      ActiveRecord::Base.connection.execute <<-SQL
        INSERT INTO #{table} (#{csv.headers.join(',')})
        VALUES (#{csv.headers.map { |h| ActiveRecord::Base.connection.quote(row[h]) }.join(',')})
      SQL
    end
  end
end

