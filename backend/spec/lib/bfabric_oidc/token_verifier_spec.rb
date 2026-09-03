# frozen_string_literal: true

require 'rails_helper'

# What this node will and will not accept as a B-Fabric access token.
#
# The JWKS and the expected issuer are stubbed here on purpose: this file is about the
# ACCEPT CRITERIA. Fetching and caching those two things is jwks_cache_spec.rb's job.
RSpec.describe BfabricOidc::TokenVerifier do
  # Methods, not constants: a constant inside a describe block leaks to Object.
  def issuer   = 'https://bfabric.example/bfabric'
  def audience = 'bfabric-api'

  def oidc_vars
    %w[
      BFABRIC_OIDC_ENABLED BFABRIC_OIDC_BASE_URL BFABRIC_OIDC_AUDIENCE
      BFABRIC_OIDC_ALLOWED_CLIENT_IDS BFABRIC_OIDC_REQUIRED_SCOPE BFABRIC_OIDC_LEEWAY
    ]
  end

  around do |example|
    saved = oidc_vars.to_h { |v| [v, ENV[v]] }
    oidc_vars.each { |v| ENV.delete(v) }
    ENV['BFABRIC_OIDC_ENABLED']  = '1'
    ENV['BFABRIC_OIDC_BASE_URL'] = issuer
    ENV['BFABRIC_OIDC_AUDIENCE'] = audience
    BfabricOidc.reset!
    begin
      example.run
    ensure
      saved.each { |v, value| value.nil? ? ENV.delete(v) : ENV[v] = value }
      BfabricOidc.reset!
    end
  end

  before do
    allow(BfabricOidc::JwksCache).to receive(:expected_issuer).and_return(issuer)
    allow(BfabricOidc::JwksCache).to receive(:jwks_loader)
      .and_return(->(_opts = {}) { BfabricOidcTestKeys.jwks_hash })
  end

  def claims(**overrides)
    now = Time.now.to_i
    {
      'iss' => issuer,
      'aud' => audience,
      'sub' => 'masaomi',
      'scope' => 'openid profile email api:read',
      'iat' => now,
      'exp' => now + 3600
    }.merge(overrides.transform_keys(&:to_s))
  end

  def verify(token)
    described_class.verify(token)
  end

  def rejection(token)
    verify(token)
    raise 'expected a rejection but the token was accepted'
  rescue described_class::Rejected => e
    e
  end

  describe 'a well-formed token from the configured issuer' do
    it 'is accepted, and yields the login and the granted scopes' do
      result = verify(BfabricOidcTestKeys.sign(claims))
      expect(result.sub).to eq('masaomi')
      expect(result.scopes).to contain_exactly('openid', 'profile', 'email', 'api:read')
      expect(result.scope_string).to include('api:read')
    end

    it 'accepts `scp` as an array, which is the other common spelling' do
      token = BfabricOidcTestKeys.sign(claims.except('scope').merge('scp' => %w[api:read api:write]))
      expect(verify(token).scopes).to contain_exactly('api:read', 'api:write')
    end

    it 'accepts an audience array containing the expected value' do
      expect(verify(BfabricOidcTestKeys.sign(claims('aud' => [audience, 'other']))).sub).to eq('masaomi')
    end
  end

  describe 'signature and algorithm' do
    # THE LOAD-BEARING SECURITY CASE. `alg` comes from the attacker-controlled header, so a
    # verifier that honours it can be handed an HS256 token signed with the PUBLIC key
    # everyone can read from the JWKS. Pinning RS256 means the signature is never even
    # checked with the wrong primitive.
    it 'rejects an HS256 token forged with the published RSA public key as the HMAC secret' do
      expect(rejection(BfabricOidcTestKeys.forged_hs256(claims)).reason)
        .to be_in(%w[bad_algorithm bad_signature undecodable])
    end

    it 'rejects a correctly-shaped token signed by a key that is not in the JWKS' do
      token = BfabricOidcTestKeys.sign(claims, key: BfabricOidcTestKeys.foreign_rsa)
      expect(rejection(token).reason).to be_in(%w[bad_signature undecodable])
    end

    it 'rejects a token with no kid, since it cannot be tied to a published key' do
      token = BfabricOidcTestKeys.sign(claims, header: {})
      expect(rejection(token).reason).to eq('undecodable')
    end

    it 'rejects anything that is not a three-segment JWS without touching the network' do
      expect(rejection('not-a-token').reason).to eq('malformed')
      expect(rejection('').reason).to eq('malformed')
    end
  end

  describe 'registered claims' do
    it 'rejects an expired token' do
      expect(rejection(BfabricOidcTestKeys.sign(claims('exp' => Time.now.to_i - 120))).reason)
        .to eq('expired')
    end

    it 'tolerates a small clock skew rather than failing a token that just expired' do
      expect(verify(BfabricOidcTestKeys.sign(claims('exp' => Time.now.to_i - 5))).sub).to eq('masaomi')
    end

    it 'rejects a token that is not valid yet' do
      expect(rejection(BfabricOidcTestKeys.sign(claims('nbf' => Time.now.to_i + 600))).reason)
        .to eq('not_yet_valid')
    end

    it 'rejects a token from a different issuer' do
      expect(rejection(BfabricOidcTestKeys.sign(claims('iss' => 'https://evil.example'))).reason)
        .to eq('bad_issuer')
    end

    # The confused-deputy guard: a token minted for a different relying party.
    it 'rejects a token minted for another audience' do
      expect(rejection(BfabricOidcTestKeys.sign(claims('aud' => 'some-other-app'))).reason)
        .to eq('bad_audience')
    end
  end

  describe 'access token vs id_token' do
    it 'rejects a token carrying at_hash, which marks it as an id_token' do
      expect(rejection(BfabricOidcTestKeys.sign(claims('at_hash' => 'abc'))).reason)
        .to eq('at_hash_present')
    end
  end

  describe 'scope' do
    it 'rejects a token that does not carry the required scope' do
      expect(rejection(BfabricOidcTestKeys.sign(claims('scope' => 'openid profile'))).reason)
        .to eq('missing_scope')
    end

    it 'honours a configured required scope' do
      ENV['BFABRIC_OIDC_REQUIRED_SCOPE'] = 'api:write'
      BfabricOidc.reset!
      expect(rejection(BfabricOidcTestKeys.sign(claims)).reason).to eq('missing_scope')
      expect(verify(BfabricOidcTestKeys.sign(claims('scope' => 'api:write'))).sub).to eq('masaomi')
    end
  end

  describe 'the subject' do
    # `sub` flows into User.find_by(login:) and into FGCZ.get_user_projects2. Constraining
    # its shape here is defence in depth, not the fix for the shell interpolation in
    # lib/fgcz.rb (deferred — see the L2 record).
    it 'rejects a subject that is not a usable login string' do
      ["x'; touch /tmp/pwn; '", 'a' * 65, '', 'has space', "new\nline"].each do |bad|
        expect(rejection(BfabricOidcTestKeys.sign(claims('sub' => bad))).reason).to eq('malformed_sub')
      end
    end
  end

  describe 'the client allow-list' do
    it 'performs no client narrowing at all when it is unset' do
      token = BfabricOidcTestKeys.sign(claims('client_id' => 'anything-at-all'))
      expect(verify(token).sub).to eq('masaomi')
    end

    context 'when it is set' do
      before do
        ENV['BFABRIC_OIDC_ALLOWED_CLIENT_IDS'] = 'CLI,new-sushi'
        BfabricOidc.reset!
      end

      it 'accepts a listed client_id, and azp as the alternative spelling' do
        expect(verify(BfabricOidcTestKeys.sign(claims('client_id' => 'CLI'))).sub).to eq('masaomi')
        expect(verify(BfabricOidcTestKeys.sign(claims('azp' => 'new-sushi'))).sub).to eq('masaomi')
      end

      it 'rejects an unlisted client' do
        expect(rejection(BfabricOidcTestKeys.sign(claims('client_id' => 'someone-else'))).reason)
          .to eq('client_not_allowed')
      end

      # Production's claims_supported lists NEITHER client_id NOR azp, so this is the
      # likely real-world case. Rejecting is the point: an allow-list that silently passes
      # every token reads like a control in review while being none.
      it 'rejects a token carrying neither claim rather than waving it through' do
        expect(rejection(BfabricOidcTestKeys.sign(claims)).reason).to eq('client_claim_absent')
      end
    end
  end

  describe 'when no audience is configured' do
    it 'refuses to verify anything rather than checking the signature alone' do
      ENV.delete('BFABRIC_OIDC_AUDIENCE')
      BfabricOidc.reset!
      expect(rejection(BfabricOidcTestKeys.sign(claims)).reason).to eq('not_configured')
    end
  end

  # ------------------------------------------------------------------------------------
  # THE SHAPE B-FABRIC ACTUALLY ISSUES.
  #
  # Everything above tests criteria in the abstract. This block tests the criteria against
  # the claim set MEASURED on 2026-09-03 from two real device-code logins, one on test and
  # one on production — recorded in
  # scripts/bfabric_oauth_check/fixtures/measured_claims_2026-09-03.json.
  #
  # The signature is ours (we do not have B-Fabric's private key), but every claim NAME and
  # VALUE below is the real one. If B-Fabric changes the shape, this is what fails.
  # ------------------------------------------------------------------------------------
  describe 'the real claim set measured on 2026-09-03' do
    def measured_access_token_claims(**overrides)
      now = Time.now.to_i
      {
        'iss' => issuer,
        'aud' => 'API',                       # a STRING, not a list, on both instances
        'sub' => 'masaomi',
        'client_id' => 'CLI',                 # present, though claims_supported omits it
        'scope' => 'profile api:read email openid api:write',
        'exp' => now + 3600,
        'iat' => now,
        'jti' => '4f1c2b90-0000-4000-8000-000000000000'
      }.merge(overrides.transform_keys(&:to_s))
    end

    # The id_token differs from the access token in exactly two ways that matter here.
    def measured_id_token_claims
      now = Time.now.to_i
      {
        'iss' => issuer, 'aud' => 'CLI', 'sub' => 'masaomi', 'at_hash' => 'Ck5nR1p2',
        'acr' => '1', 'auth_time' => now, 'email' => 'masaomi@example.org',
        'email_verified' => true, 'family_name' => 'H', 'given_name' => 'M',
        'name' => 'M H', 'exp' => now + 3600, 'iat' => now
      }
    end

    before do
      ENV['BFABRIC_OIDC_AUDIENCE'] = 'API'
      BfabricOidc.reset!
    end

    it 'accepts it, and reads out the login and the granted scopes' do
      result = verify(BfabricOidcTestKeys.sign(measured_access_token_claims))
      expect(result.sub).to eq('masaomi')
      expect(result.scopes).to include('api:read', 'api:write')
    end

    # `aud` is the literal string "API" on BOTH instances, which every B-Fabric API token
    # carries. It separates an access token from an id_token; it does NOT separate a token
    # minted for us from one minted for another relying party. Recorded so nobody reads
    # the aud check as more protection than it is.
    it 'is the same audience on test and on production' do
      %w[https://fgcz-bfabric-test.uzh.ch/bfabric https://fgcz-bfabric.uzh.ch/bfabric].each do |iss|
        allow(BfabricOidc::JwksCache).to receive(:expected_issuer).and_return(iss)
        token = BfabricOidcTestKeys.sign(measured_access_token_claims('iss' => iss))
        expect(verify(token).sub).to eq('masaomi')
      end
    end

    it 'rejects the real ID TOKEN presented in an access token\'s place' do
      # Two independent guards catch it: aud is CLI rather than API, and at_hash is present.
      expect(rejection(BfabricOidcTestKeys.sign(measured_id_token_claims)).reason)
        .to be_in(%w[bad_audience at_hash_present])
    end

    # The correction this measurement forced: the design assumed no per-client narrowing
    # was possible because production's `claims_supported` lists neither client_id nor azp.
    # The access token carries client_id anyway — claims_supported under-promises as well
    # as over-promising. So the allow-list is real, and this proves it against the real shape.
    describe 'with the client allow-list turned on' do
      before do
        ENV['BFABRIC_OIDC_ALLOWED_CLIENT_IDS'] = 'CLI'
        BfabricOidc.reset!
      end

      it 'accepts the real token, because client_id is genuinely present' do
        expect(verify(BfabricOidcTestKeys.sign(measured_access_token_claims)).sub).to eq('masaomi')
      end

      it 'rejects a token minted for a different B-Fabric client' do
        token = BfabricOidcTestKeys.sign(measured_access_token_claims('client_id' => 'SomeOtherApp'))
        expect(rejection(token).reason).to eq('client_not_allowed')
      end
    end
  end
end
