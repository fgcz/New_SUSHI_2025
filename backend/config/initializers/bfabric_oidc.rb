# frozen_string_literal: true

# Freeze and report the node's B-Fabric OIDC posture during boot.
#
# Same two reasons as config/initializers/env_api_token.rb: the posture is fixed before
# any request is served, and a misconfiguration is announced once at startup instead of
# presenting as an inexplicable 401 on every login attempt.
#
# Touches no database and makes NO network call — discovery and JWKS are fetched lazily on
# first use, so B-Fabric being down cannot stop this process from booting.
Rails.application.config.after_initialize do
  config = BfabricOidc.config

  if config.enabled?
    Rails.logger.info(
      "BfabricOidc: B-Fabric OIDC ENABLED (base_url=#{config.base_url} " \
      "audience=#{config.access_token_audience} required_scope=#{config.required_scope})"
    )

    if config.device_login_enabled?
      # Worth one line at boot: these two routes are UNAUTHENTICATED by necessity (they
      # are the login) and they make outbound calls to B-Fabric, so an operator reading
      # the log should know they are open and what bounds them.
      Rails.logger.info(
        "BfabricOidc: browser device login ENABLED (public client " \
        "#{config.device_client_id}, at most #{BfabricOidc::DeviceFlow::MAX_PENDING} " \
        'sign-ins in progress, poll interval enforced server-side)'
      )
    else
      Rails.logger.info('BfabricOidc: browser device login is OFF; only the ' \
                        'machine-facing token exchange is available')
    end

    unless config.enforce_client_allow_list?
      # WARN, not INFO. This is the one narrowing the design would like to have and
      # cannot assume: production's `claims_supported` lists neither `client_id` nor
      # `azp`, so a token minted for ANY B-Fabric client can be exchanged here. Saying so
      # at boot is the difference between an accepted risk and an unnoticed one.
      Rails.logger.warn(
        'BfabricOidc: no client allow-list (BFABRIC_OIDC_ALLOWED_CLIENT_IDS is unset) — ' \
        'any B-Fabric token with the configured audience and scope is accepted at ' \
        'GET /api/v1/auth/bfabric/session, whichever client it was minted for.'
      )
    end
  elsif config.requested?
    config.errors.each do |message|
      Rails.logger.warn("BfabricOidc: B-Fabric OIDC DISABLED — #{message}")
    end
  end
end
