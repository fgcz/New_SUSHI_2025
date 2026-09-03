# frozen_string_literal: true

require 'rails_helper'

# The node's OIDC posture. Every example here pins a FAIL-CLOSED property: the feature is
# off unless it was both asked for and fully configured, and it never raises during boot.
RSpec.describe BfabricOidc::Config do
  # A method, not a constant: a constant inside a describe block leaks to Object and
  # collides with the identically-named one in the sibling spec.
  def oidc_vars
    %w[
      BFABRIC_OIDC_ENABLED BFABRIC_OIDC_BASE_URL BFABRIC_OIDC_AUDIENCE BFABRIC_OIDC_ISSUER
      BFABRIC_OIDC_JWKS_URI BFABRIC_OIDC_CLIENT_ID BFABRIC_OIDC_ALLOWED_CLIENT_IDS
      BFABRIC_OIDC_REQUIRED_SCOPE BFABRIC_OIDC_HTTP_TIMEOUT BFABRIC_OIDC_LEEWAY
    ]
  end

  around do |example|
    saved = oidc_vars.to_h { |v| [v, ENV[v]] }
    oidc_vars.each { |v| ENV.delete(v) }
    BfabricOidc.reset!
    begin
      example.run
    ensure
      saved.each { |v, value| value.nil? ? ENV.delete(v) : ENV[v] = value }
      BfabricOidc.reset!
    end
  end

  def configure(**vars)
    vars.each { |k, v| v.nil? ? ENV.delete(k.to_s) : ENV[k.to_s] = v }
    BfabricOidc.reset!
    BfabricOidc.config
  end

  def enable_fully(**overrides)
    configure(
      BFABRIC_OIDC_ENABLED: '1',
      BFABRIC_OIDC_BASE_URL: 'https://bfabric.example/bfabric',
      BFABRIC_OIDC_AUDIENCE: 'bfabric-api',
      **overrides
    )
  end

  describe 'when nothing is set (every node that has not opted in)' do
    it 'is off, was not requested, and reports no errors' do
      config = configure
      expect(config.enabled?).to be(false)
      expect(config.requested?).to be(false)
      expect(config.errors).to eq([])
    end
  end

  describe 'fail-closed validation' do
    it 'refuses to enable without a base URL' do
      config = configure(BFABRIC_OIDC_ENABLED: '1', BFABRIC_OIDC_AUDIENCE: 'bfabric-api')
      expect(config.enabled?).to be(false)
      expect(config.requested?).to be(true)
      expect(config.errors.join).to include('BFABRIC_OIDC_BASE_URL')
    end

    # The hard gate. Without an expected `aud`, any B-Fabric token verifies here on
    # signature alone — the confused-deputy case the whole endpoint is shaped to avoid.
    it 'refuses to enable without an expected audience, and says how to obtain one' do
      config = configure(BFABRIC_OIDC_ENABLED: '1',
                         BFABRIC_OIDC_BASE_URL: 'https://bfabric.example/bfabric')
      expect(config.enabled?).to be(false)
      expect(config.errors.join).to include('BFABRIC_OIDC_AUDIENCE')
      expect(config.errors.join).to include('measure_token_claims.sh')
    end

    it 'rejects a base URL that is not http(s)' do
      config = enable_fully(BFABRIC_OIDC_BASE_URL: 'ftp://bfabric.example')
      expect(config.enabled?).to be(false)
      expect(config.errors.join).to include('http(s)')
    end

    it 'treats a present-but-blank enable flag as not requested' do
      config = configure(BFABRIC_OIDC_ENABLED: '   ')
      expect(config.requested?).to be(false)
      expect(config.enabled?).to be(false)
    end

    it 'does not raise for any malformed input' do
      expect { configure(BFABRIC_OIDC_ENABLED: '1', BFABRIC_OIDC_BASE_URL: ':::not a url:::') }
        .not_to raise_error
    end
  end

  describe 'when fully configured' do
    it 'is enabled with no errors' do
      config = enable_fully
      expect(config.enabled?).to be(true)
      expect(config.errors).to eq([])
    end

    it 'strips a trailing slash off the base URL so discovery_url is well formed' do
      config = enable_fully(BFABRIC_OIDC_BASE_URL: 'https://bfabric.example/bfabric/')
      expect(config.base_url).to eq('https://bfabric.example/bfabric')
      expect(config.discovery_url).to eq('https://bfabric.example/bfabric/.well-known/openid-configuration')
    end

    it 'defaults the required scope, the timeout and the leeway' do
      config = enable_fully
      expect(config.required_scope).to eq('api:read')
      expect(config.http_timeout).to eq(5)
      expect(config.leeway).to eq(30)
    end

    it 'is frozen, so nothing can change the posture mid-process' do
      expect(enable_fully).to be_frozen
    end
  end

  describe 'the client allow-list' do
    it 'is not enforced when unset — stated plainly rather than implied' do
      expect(enable_fully.enforce_client_allow_list?).to be(false)
    end

    it 'is enforced, and parsed as a comma list, when set' do
      config = enable_fully(BFABRIC_OIDC_ALLOWED_CLIENT_IDS: 'CLI, new-sushi ,')
      expect(config.enforce_client_allow_list?).to be(true)
      expect(config.allowed_client_ids).to eq(%w[CLI new-sushi])
    end
  end
end
