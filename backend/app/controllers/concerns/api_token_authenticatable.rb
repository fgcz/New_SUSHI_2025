# Lets the JWT-based /api/v1 surface ALSO be driven by a bearer ApiToken
# (SUSHI_API_TOKEN) — the same credential custom_dataset_registration / the /v1
# and /internal surfaces use — so sushi-chain / claude-code can do basic
# operations (dataset list, job list/check, job submission) with no interactive
# login and no UI.
#
# Semantics:
#   - A presented, VALID ApiToken authenticates as that token even when global
#     auth is otherwise skipped (dev). Project scope is then enforced from the
#     token, not from anonymous "all projects".
#   - user / static principals are accepted; machine is rejected (403) — machine
#     is the /internal infra credential, not a basic-ops caller.
#   - No token → callers fall through to the existing JWT (or skipped) path.
#
# Authorization is project-based: what a token may see/act on is
# ApiToken#allowed_projects (user → live FGCZ membership; static → stored scope).
module ApiTokenAuthenticatable
  extend ActiveSupport::Concern

  SAFE_HTTP_METHODS = %w[GET HEAD OPTIONS TRACE].freeze

  included do
    # prepend so it runs BEFORE the inherited JWT before_action; a valid ApiToken
    # then satisfies authentication and the JWT layer stands down (see
    # JwtAuthenticatable#authenticate_jwt_token / BaseController).
    prepend_before_action :authenticate_api_token
    rescue_from ApiToken::ResolverUnavailable do
      render json: { error: 'authorization backend unavailable' }, status: :service_unavailable
    end
  end

  private

  def authenticate_api_token
    raw = bearer_api_token
    return if raw.blank?

    token = ApiToken.authenticate(raw)
    return if token.nil? # not our token → leave JWT/anonymous path untouched

    if token.machine?
      render json: { error: 'action not permitted for this token' }, status: :forbidden
      return
    end

    @api_token = token
    authorize_token_write!
  end

  # Project scope answers "which projects"; it never answered "may it change
  # anything". Without this, moving a production instance from read_only to
  # `additive` would silently turn every in-scope token — including a credential
  # issued purely for read-only inspection — into a job submitter. Fail-closed:
  # a token with no recorded capabilities is read-only (see ApiToken::CAPABILITIES).
  def authorize_token_write!
    return if SAFE_HTTP_METHODS.include?(request.request_method)
    return if @api_token.can_write?

    render json: {
      error: 'action not permitted for this token',
      message: 'This token is read-only. Grant write authority explicitly ' \
               '(rake api_token:grant_write ID=<id>) or use a token that has it.'
    }, status: :forbidden
  end

  def token_authenticated?
    @api_token.present?
  end

  # Identity used for display and ownership. For a user principal, the LDAP login
  # (a non-persisted User is fine — we only read .login); for a static principal,
  # a synthetic service login.
  def api_token_identity
    return nil unless token_authenticated?

    @api_token_identity ||=
      if @api_token.user?
        User.find_by(login: @api_token.login) || User.new(login: @api_token.login)
      else
        User.new(login: "apitoken:#{@api_token.name}")
      end
  end

  # Project numbers (integers) this token may act on. user → live FGCZ (may raise
  # ResolverUnavailable → 503); static → stored scope.
  def api_token_project_numbers
    return [] unless token_authenticated?

    @api_token_project_numbers ||= @api_token.allowed_projects.map(&:to_i)
  end

  def bearer_api_token
    header = request.headers['Authorization'].to_s
    header[/\ABearer\s+(.+)\z/i, 1]
  end
end
