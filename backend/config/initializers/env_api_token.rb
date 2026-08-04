# frozen_string_literal: true

# Freeze and report the ENV-provisioned API-token credential during boot.
#
# Two reasons this runs at startup rather than lazily on the first request:
#   - it fixes the credential (and therefore the node's authority) before any
#     request is served, so mutating ENV mid-process cannot change it;
#   - a misconfiguration is announced once, at startup, instead of presenting as
#     an inexplicable 401 on every subsequent request.
#
# Touches no database. Logs the name and scope but NEVER the digest.
Rails.application.config.after_initialize do
  if (config = EnvApiToken.config)
    Rails.logger.info(
      "EnvApiToken: ENV-provisioned API token ENABLED " \
      "(name=#{config.name} scope=#{config.scope.inspect} " \
      "principal=static capabilities=read-only)"
    )
  elsif EnvApiToken.errors.any?
    EnvApiToken.errors.each do |message|
      Rails.logger.warn("EnvApiToken: ENV-provisioned API token DISABLED — #{message}")
    end
  end
end
