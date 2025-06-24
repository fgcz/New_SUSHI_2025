require 'csv'

ActiveRecord::Base.connection.disable_referential_integrity do
  Dir.glob("db/csv_data/*.csv").each do |file|
    table = File.basename(file, ".csv")
    puts "Importing #{table}..."

    csv = CSV.read(file, headers: true)
    
    # テーブル固有の処理
    case table
    when 'users'
      csv.each do |row|
        # usersテーブル用の特別な処理
        # emailフィールドがCSVにない場合は、login + @example.com で生成
        # encrypted_passwordフィールドがCSVにない場合はデフォルト値を設定
        email = row['email'] || "#{row['login']}@example.com"
        encrypted_password = row['encrypted_password'] || '$2a$12$dummy.hash.for.imported.users'
        
        # 必要なフィールドのみを抽出
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
      # その他のテーブルは通常通り処理
      csv.each do |row|
        ActiveRecord::Base.connection.execute <<-SQL
          INSERT INTO #{table} (#{csv.headers.join(',')})
          VALUES (#{csv.headers.map { |h| ActiveRecord::Base.connection.quote(row[h]) }.join(',')})
        SQL
      end
    end
  end
end

