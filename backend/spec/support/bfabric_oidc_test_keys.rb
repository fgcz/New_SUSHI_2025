# frozen_string_literal: true

require 'jwt'

# Signing material for the B-Fabric OIDC specs.
#
# The RSA key is generated ONCE per process and memoized: 2048-bit generation is not free,
# and every example that needs a token needs the same key that produced the JWKS.
module BfabricOidcTestKeys
  module_function

  def rsa
    @rsa ||= OpenSSL::PKey::RSA.generate(2048)
  end

  # A second key that is NEVER published in the JWKS — used to prove that a
  # correctly-shaped token signed by the wrong party is rejected.
  def foreign_rsa
    @foreign_rsa ||= OpenSSL::PKey::RSA.generate(2048)
  end

  def jwk
    @jwk ||= JWT::JWK.new(rsa)
  end

  def kid
    jwk.export[:kid] || jwk.export['kid']
  end

  # Shaped like a real JWKS document: string keys, a `keys` array.
  def jwks_hash
    { 'keys' => [jwk.export.transform_keys(&:to_s)] }
  end

  def sign(claims, key: rsa, alg: 'RS256', header: { kid: kid })
    JWT.encode(claims, key, alg, header)
  end

  # The algorithm-confusion attempt: take the PUBLIC modulus anyone can read from the
  # JWKS and use it as an HMAC secret. A verifier that trusts the token's own `alg`
  # header accepts this; one that pins RS256 never looks at the signature.
  def forged_hs256(claims)
    secret = rsa.public_key.to_pem
    JWT.encode(claims, secret, 'HS256', { kid: kid })
  end
end
