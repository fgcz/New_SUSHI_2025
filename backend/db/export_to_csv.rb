# db/export_to_csv.rb
require 'csv'
require 'fileutils'

output_dir = Rails.root.join("db", "csv_data")
FileUtils.mkdir_p(output_dir)

ActiveRecord::Base.connection.tables.each do |table|
  next if table.in?(%w[schema_migrations ar_internal_metadata])

  puts "Exporting #{table}..."

  records = ActiveRecord::Base.connection.exec_query("SELECT * FROM #{table}")
  filepath = output_dir.join("#{table}.csv")

  CSV.open(filepath, "w") do |csv|
    csv << records.columns  # ヘッダー
    records.rows.each do |row|
      csv << row
    end
  end
end

