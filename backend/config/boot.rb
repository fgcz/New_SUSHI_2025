ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)

require "bundler/setup" # Set up gems listed in the Gemfile.
# Speed up boot time by caching expensive operations (disabled in test to avoid frozen arrays issues)
require "bootsnap/setup" unless ENV["RAILS_ENV"] == "test"
