namespace :ldap do
  desc "Test LDAP connection"
  task test: :environment do
    puts "Testing bfabric LDAP connection..."
    
    # Load LDAP configuration
    ldap_config = YAML.load(ERB.new(File.read(Rails.root.join('config', 'ldap.yml'))).result, aliases: true)[Rails.env]
    
    puts "Host: #{ldap_config['host']}"
    puts "Port: #{ldap_config['port']}"
    puts "Base: #{ldap_config['base']}"
    puts "Attribute: #{ldap_config['attribute']}"
    puts "SSL: #{ldap_config['ssl']}"
    
    begin
      # Create LDAP connection
      ldap = Net::LDAP.new(
        host: ldap_config['host'],
        port: ldap_config['port'],
        base: ldap_config['base'],
        encryption: ldap_config['ssl'] ? :simple_tls : nil,
        verify_mode: ldap_config['ssl_verify'] ? OpenSSL::SSL::VERIFY_PEER : OpenSSL::SSL::VERIFY_NONE
      )
      
      # Test connection
      if ldap.bind
        puts "✅ LDAP connection successful!"
        
        # Test search for masaomi user
        filter = Net::LDAP::Filter.eq(ldap_config['attribute'], 'masaomi')
        ldap.search(filter: filter, base: ldap_config['base']) do |entry|
          puts "✅ Found user: #{entry.dn}"
          puts "Email: #{entry.mail&.first}"
          puts "Available attributes: #{entry.attribute_names.join(', ')}"
        end
      else
        puts "❌ LDAP connection failed!"
        puts "Error: #{ldap.get_operation_result.message}"
      end
    rescue => e
      puts "❌ LDAP connection error: #{e.message}"
    end
  end
end 