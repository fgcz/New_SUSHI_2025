#!/usr/bin/env ruby

# LDAP Connection Test Script
# Usage: ruby scripts/test_ldap_connection.rb

require 'net/ldap'
require 'yaml'

# Load LDAP configuration
ldap_config_path = File.join(File.dirname(__FILE__), '..', 'backend', 'config', 'ldap.yml')
ldap_config = YAML.load(ERB.new(File.read(ldap_config_path)).result)[Rails.env]

puts "Testing bfabric LDAP connection..."
puts "Host: #{ldap_config['host']}"
puts "Port: #{ldap_config['port']}"
puts "Base: #{ldap_config['base']}"
puts "Attribute: #{ldap_config['attribute']}"
puts "SSL: #{ldap_config['ssl']}"

begin
  # Create LDAP connection for bfabric
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
    
    # Test search
    filter = Net::LDAP::Filter.eq(ldap_config['attribute'], '*')
    ldap.search(filter: filter, base: ldap_config['base'], scope: Net::LDAP::SearchScope_BaseObject) do |entry|
      puts "✅ LDAP search successful!"
      puts "Found entry: #{entry.dn}"
    end
  else
    puts "❌ LDAP connection failed!"
    puts "Error: #{ldap.get_operation_result.message}"
  end
rescue => e
  puts "❌ LDAP connection error: #{e.message}"
end 