# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc
]

# OAuth2 / OIDC parameters that arrive in a QUERY STRING and would otherwise be written to
# the request log verbatim. This matters because railties' rack logger builds its
# `Started GET "..."` line from `request.filtered_path`, so these entries genuinely scrub
# the log rather than only the params hash (verified against railties 8.0.5,
# lib/rails/rack/logger.rb).
#
# An authorization `code` is a single-use credential: anyone who reads it out of a
# retained log before the legitimate exchange can trade it for a token. `state` and the
# PKCE verifier are session secrets in the same window.
#
# ANCHORED REGEXPS, not bare symbols, on purpose: a symbol is a PARTIAL match, so `:code`
# would also blank out any future `barcode`/`zipcode`/`app_code` parameter and quietly
# make unrelated logs less useful. These match the exact parameter names only.
Rails.application.config.filter_parameters += [
  /\Acode\z/, /\Astate\z/, /\Adevice_code\z/, /\Acode_verifier\z/, /\Auser_code\z/
]
