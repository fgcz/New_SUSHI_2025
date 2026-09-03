# frozen_string_literal: true

require 'rails_helper'

# An authorization `code` is a single-use credential: anyone who reads it out of a retained
# log before the legitimate exchange can trade it for a token. It arrives in a QUERY STRING,
# so it lands in the `Started GET "..."` line rather than in a request body.
#
# MECHANISM (verified against railties 8.0.5, lib/rails/rack/logger.rb): that line is built
# from `request.filtered_path`, so config.filter_parameters genuinely scrubs the log and not
# merely the params hash. These examples pin the OUTCOME rather than the railties internals,
# which we do not control.
RSpec.describe 'request log filtering of OAuth parameters', type: :request do
  def filtered_path_for(query)
    env = Rack::MockRequest.env_for("/api/v1/auth/bfabric/callback?#{query}")
    request = ActionDispatch::Request.new(env)
    request.set_header('action_dispatch.parameter_filter', Rails.application.config.filter_parameters)
    request.filtered_path
  end

  it 'masks an authorization code' do
    path = filtered_path_for('code=SUPER-SECRET-CODE&state=abc')
    expect(path).not_to include('SUPER-SECRET-CODE')
    expect(path).to include('[FILTERED]')
  end

  it 'masks the state, the PKCE verifier and the device-code values' do
    {
      'state' => 'STATE-SECRET',
      'code_verifier' => 'VERIFIER-SECRET',
      'device_code' => 'DEVICE-SECRET',
      'user_code' => 'USER-SECRET'
    }.each do |param, value|
      expect(filtered_path_for("#{param}=#{value}")).not_to include(value)
    end
  end

  # The entries are ANCHORED regexps rather than bare symbols on purpose: a symbol is a
  # PARTIAL match, so `:code` would also blank out unrelated parameters and quietly make
  # other logs less useful. This is the example that would fail if someone "simplified"
  # them back to symbols.
  it 'does not blank out unrelated parameters that merely contain the word code' do
    path = filtered_path_for('barcode=ABC123&zipcode=8057&app_code=STAR')
    expect(path).to include('ABC123')
    expect(path).to include('8057')
    expect(path).to include('STAR')
  end
end
