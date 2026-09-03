# frozen_string_literal: true

require 'rails_helper'

# Fetching and caching B-Fabric's discovery document and signing keys.
#
# This sits on the login path and every miss is a network call to a service we do not own,
# so the caching behaviour is a correctness property, not an optimisation.
RSpec.describe BfabricOidc::JwksCache do
  def base_url     = 'https://bfabric.example/bfabric'
  def discovery_url = "#{base_url}/.well-known/openid-configuration"
  def jwks_url      = "#{base_url}/rest/oauth/jwks"

  def oidc_vars
    %w[BFABRIC_OIDC_ENABLED BFABRIC_OIDC_BASE_URL BFABRIC_OIDC_AUDIENCE
       BFABRIC_OIDC_ISSUER BFABRIC_OIDC_JWKS_URI BFABRIC_OIDC_HTTP_TIMEOUT]
  end

  around do |example|
    saved = oidc_vars.to_h { |v| [v, ENV[v]] }
    oidc_vars.each { |v| ENV.delete(v) }
    ENV['BFABRIC_OIDC_ENABLED']  = '1'
    ENV['BFABRIC_OIDC_BASE_URL'] = base_url
    ENV['BFABRIC_OIDC_AUDIENCE'] = 'bfabric-api'
    BfabricOidc.reset!
    begin
      example.run
    ensure
      saved.each { |v, value| value.nil? ? ENV.delete(v) : ENV[v] = value }
      BfabricOidc.reset!
    end
  end

  def stub_discovery(issuer: base_url, jwks_uri: jwks_url)
    stub_request(:get, discovery_url)
      .to_return(status: 200,
                 body: { issuer: issuer, jwks_uri: jwks_uri }.to_json,
                 headers: { 'Content-Type' => 'application/json' })
  end

  def stub_jwks(body: BfabricOidcTestKeys.jwks_hash, status: 200)
    stub_request(:get, jwks_url)
      .to_return(status: status,
                 body: body.is_a?(String) ? body : body.to_json,
                 headers: { 'Content-Type' => 'application/json' })
  end

  describe 'the happy path' do
    it 'discovers the jwks_uri and returns the key set' do
      stub_discovery
      stub_jwks
      expect(described_class.key_set['keys'].first['kid']).to eq(BfabricOidcTestKeys.kid)
    end

    # Without this, every login costs two round trips to B-Fabric.
    it 'caches both documents, so a second read makes no further request' do
      stub_discovery
      stub_jwks
      3.times { described_class.key_set }
      expect(a_request(:get, discovery_url)).to have_been_made.once
      expect(a_request(:get, jwks_url)).to have_been_made.once
    end

    it 'skips discovery entirely when the jwks_uri is configured explicitly' do
      ENV['BFABRIC_OIDC_JWKS_URI'] = jwks_url
      BfabricOidc.reset!
      stub_jwks
      described_class.key_set
      expect(a_request(:get, discovery_url)).not_to have_been_made
    end
  end

  describe 'the expected issuer' do
    it 'comes from the discovery document when it is not configured' do
      stub_discovery(issuer: 'https://issuer.example/realm')
      expect(described_class.expected_issuer).to eq('https://issuer.example/realm')
    end

    it 'is overridden by an explicit setting, without a network call' do
      ENV['BFABRIC_OIDC_ISSUER'] = 'https://pinned.example'
      BfabricOidc.reset!
      expect(described_class.expected_issuer).to eq('https://pinned.example')
      expect(a_request(:get, discovery_url)).not_to have_been_made
    end
  end

  describe 'key rotation' do
    # A rotated `kid` that is not in the cached set would otherwise lock every login out
    # for a full TTL (one hour) — a gotcha documented in bfabricPy itself.
    it 'refetches immediately when a kid is missing' do
      stub_discovery
      stub_jwks
      described_class.key_set
      described_class.key_set(force: true)
      expect(a_request(:get, jwks_url)).to have_been_made.twice
    end

    # Without the rate limit, a stream of tokens carrying an unknown kid turns this cache
    # into a request amplifier pointed at B-Fabric.
    it 'rate-limits forced refetches and keeps serving the set it has' do
      stub_discovery
      stub_jwks
      described_class.key_set
      5.times { described_class.key_set(force: true) }
      expect(a_request(:get, jwks_url)).to have_been_made.twice
    end

    it 'exposes a loader in the shape the jwt gem calls, honouring :kid_not_found' do
      stub_discovery
      stub_jwks
      loader = described_class.jwks_loader
      loader.call({})
      loader.call({ kid_not_found: true })
      expect(a_request(:get, jwks_url)).to have_been_made.twice
    end
  end

  describe 'when B-Fabric misbehaves' do
    # Every one of these must surface as Unreachable (→ 503), never as a bad credential
    # (→ 401) and never as a 500. A network fault is not an authentication failure.
    it 'raises Unreachable on a non-2xx discovery response' do
      stub_request(:get, discovery_url).to_return(status: 502, body: 'nope')
      expect { described_class.key_set }.to raise_error(BfabricOidc::Unreachable, /502/)
    end

    it 'raises Unreachable when the connection fails' do
      stub_request(:get, discovery_url).to_raise(Errno::ECONNREFUSED)
      expect { described_class.key_set }.to raise_error(BfabricOidc::Unreachable)
    end

    it 'raises Unreachable when the response is not JSON' do
      stub_request(:get, discovery_url).to_return(status: 200, body: '<html>oops</html>')
      expect { described_class.key_set }.to raise_error(BfabricOidc::Unreachable, /did not return JSON/)
    end

    it 'raises Unreachable when the JWKS has no keys array' do
      stub_discovery
      stub_jwks(body: { 'not_keys' => [] })
      expect { described_class.key_set }.to raise_error(BfabricOidc::Unreachable, /keys/)
    end

    it 'raises Unreachable rather than fetching a non-http(s) URL' do
      stub_discovery(jwks_uri: 'file:///etc/passwd')
      expect { described_class.key_set }.to raise_error(BfabricOidc::Unreachable, /non-http/)
    end

    it 'raises Unreachable when no base URL is configured at all' do
      ENV.delete('BFABRIC_OIDC_BASE_URL')
      BfabricOidc.reset!
      expect { described_class.key_set }.to raise_error(BfabricOidc::Unreachable)
    end
  end
end
