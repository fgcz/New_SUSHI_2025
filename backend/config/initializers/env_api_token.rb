# frozen_string_literal: true

# Freeze and report the ENV-provisioned API-token credentials during boot.
#
# Two reasons this runs at startup rather than lazily on the first request:
#   - it fixes the credentials (and therefore the node's authority) before any
#     request is served, so mutating ENV mid-process cannot change them;
#   - a misconfiguration is announced once, at startup, instead of presenting as
#     an inexplicable 401 on every subsequent request.
#
# Touches no database. Logs names and scopes but NEVER a digest.
Rails.application.config.after_initialize do
  if (config = EnvApiToken.config)
    Rails.logger.info(
      "EnvApiToken: ENV-provisioned API token ENABLED " \
      "(name=#{config.name} scope=#{config.scope.inspect} " \
      "principal=static capabilities=read-only)"
    )
  end

  # Deliberately WARN, not INFO. On the production node an enabled write
  # credential is a standing risk that should be visible in the log without
  # anyone going looking for it — and its absence on an ordinary node should be
  # equally unremarkable, hence no message at all in that case.
  if (write = EnvApiToken.write_config)
    Rails.logger.warn(
      "EnvApiToken: WRITE credential ENABLED " \
      "(name=#{write.name} scope=#{write.scope.inspect} principal=static) — " \
      "this bearer value may CREATE rows. The Rack write policy " \
      "(SUSHI_WRITE_POLICY=#{ENV.fetch('SUSHI_WRITE_POLICY', '(unset)')}) is a " \
      "separate gate and must also permit the route."
    )
  end

  EnvApiToken.errors.each do |message|
    Rails.logger.warn("EnvApiToken: ENV-provisioned API token DISABLED — #{message}")
  end
end
