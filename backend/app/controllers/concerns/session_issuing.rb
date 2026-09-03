# frozen_string_literal: true

# The single place a SUSHI session is minted.
#
# Extracted from Api::V1::AuthController unchanged, so that the B-Fabric OIDC login has
# somewhere to converge rather than growing a second, parallel issuance path. Below
# #establish_session the two logins are byte-identical: same JWT, same claims, same user
# payload, same downstream JwtAuthenticatable. The only difference above it is carriage —
# a password login gets the token in a JSON body it asked for, a B-Fabric login gets it
# after presenting a B-Fabric token instead of a password.
#
# WHY THIS MATTERS BEYOND TIDINESS: every authorization rule in this application reads
# `current_user` and resolves projects from LDAP. If OAuth sessions were issued by their
# own code path, "is an OAuth session authorized the same way as an LDAP one?" would be a
# question answered by inspection instead of by construction.
module SessionIssuing
  extend ActiveSupport::Concern

  # Lifetime of the opaque refresh token / its cookie (matches Ronald's FastAPI: 7 days).
  REFRESH_TTL = (ENV['JWT_REFRESH_TOKEN_EXPIRE_DAYS'] || 7).to_i.days

  included do
    # serialize_user resolves the caller's projects through the shared resolver.
    include ProjectAuthorizable
  end

  private

  # THE CONVERGENCE POINT. Returns the response body for a successful login.
  #
  # `extra_claims` records provenance for non-password logins (`src: 'bfabric'` plus the
  # scopes B-Fabric granted). It lands in the JWT only — never in the response body, and
  # never in the database.
  def establish_session(user, extra_claims = {})
    token_response(user, extra_claims)
  end

  # Issuing a refresh token is the ONLY database write a login performs, and it
  # is skipped where the table does not exist (082 — see RefreshToken.available?).
  # Skipping rather than failing is deliberate: the caller still receives a usable
  # access token, and the only thing lost is session continuity — /auth/refresh has
  # nothing to rotate and /auth/logout-all nothing to revoke. That trade makes the
  # whole login path write-free, which is what lets it run under a read_only policy
  # against a database shared with the live legacy production system.
  #
  # NOTE the B-Fabric path does NOT call this at all. It never issues a refresh token, so
  # the absent `refresh_tokens` table on 082 is irrelevant there rather than merely
  # tolerated, and there is no server-side token store for that path to breach.
  def issue_tokens_for(user)
    unless RefreshToken.available?
      Rails.logger.info('AuthController: refresh_tokens table absent; issuing an access token only')
      return
    end

    _record, raw = RefreshToken.issue(user: user, ttl: REFRESH_TTL)
    set_refresh_cookie(raw)
  end

  # Contract: TokenResponse { access_token, token_type, user }. The shape is frozen; the
  # optional second argument adds claims to the TOKEN, not fields to this hash.
  def token_response(user, extra_claims = {})
    {
      access_token: generate_jwt_token(user, extra_claims),
      token_type: 'bearer',
      user: serialize_user(user)
    }
  end

  # Contract: User { user_id, login, projects }.
  def serialize_user(user)
    {
      user_id: user.id,
      login: user.login,
      projects: current_user_project_numbers_for(user).map(&:to_i)
    }
  end

  # ----- refresh cookie -------------------------------------------------

  def set_refresh_cookie(raw)
    cookies[:refresh_token] = {
      value: raw,
      httponly: true,
      secure: !Rails.env.local?, # HTTPS only outside dev/test (matches FastAPI)
      same_site: :strict,        # contract-frozen
      expires: REFRESH_TTL.from_now,
      path: '/'
    }
  end

  def clear_refresh_cookie
    cookies.delete(:refresh_token, path: '/')
  end
end
