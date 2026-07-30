require 'json'

# Machine-callable, bearer-only registration API surface. Ported from legacy
# production SUSHI (uzh/sushi) so btools reaches New SUSHI by base-URL swap.
#
# Deliberately inherits from ActionController::Base (NOT our api/v1 base): no
# Devise, no session, no CSRF, no JWT filter. Authentication is fail-closed via a
# per-caller bearer token (ApiToken); authorization is least-privilege by the
# token's project scope. The manifest is received as content, never a path.
#
# Implemented: validate, register (idempotent), set_bfabric_id (set-once),
# destroy (deregister).
module V1
  class DatasetsController < ActionController::Base
    # Bearer-only, no cookies/session → CSRF protection is inapplicable. Use
    # skip_forgery_protection, NOT `with: :null_session`: the latter still runs
    # the unverified-request handler, which (with Devise loaded app-wide) calls
    # request.flash= and 500s on this session-less controller when forgery
    # protection is enabled (dev/prod). Tests default to it OFF, so this only
    # surfaced on a live server.
    skip_forgery_protection

    # Single composable authorization gate (design v0.7). Ordered before_actions;
    # no action runs unless every step passes. Endpoint authority is checked
    # before the (network-bound) membership resolution, so a forbidden action
    # fails deterministically (403) rather than with a resolver-dependent 503.
    before_action :enforce_tls
    before_action :require_bearer_token
    before_action :reject_machine_principal!
    before_action :reject_blank_user_login!
    before_action :authorize_endpoint!
    before_action :authorize_token_write!

    # A user token whose live membership resolver is unreachable fails closed with
    # 503 (a retryable availability failure, distinct from a 403 authz denial).
    rescue_from ApiToken::ResolverUnavailable do
      render json: { error: "authorization backend unavailable" }, status: :service_unavailable
    end

    # A malformed JSON body is a client error (400), not a silently-empty request.
    rescue_from JSON::ParserError do
      render json: { error: "malformed JSON body" }, status: :bad_request
    end

    # POST /v1/datasets/validate
    def validate
      return unless authorize_project!(body_param(:project_number))

      result = DatasetRegistrationService.validate(**manifest_args)
      render json: result, status: :ok
    end

    # POST /v1/datasets/register
    def register
      return unless authorize_project!(body_param(:project_number))

      result = DatasetRegistrationService.register(**manifest_args, owner_login: acting_login)
      render json: result[:body], status: result[:http]
    end

    # PUT /v1/datasets/:id/bfabric-id
    def set_bfabric_id
      data_set = find_scoped_data_set(params[:id])
      return unless data_set

      bfabric_id = body_param(:bfabric_id)
      if bfabric_id.to_s.empty?
        render json: { error: "bfabric_id is required" }, status: :unprocessable_entity
        return
      end
      # Must be a positive integer; a non-numeric value would silently coerce to 0.
      unless bfabric_id.to_s.match?(/\A\d+\z/) && bfabric_id.to_i.positive?
        render json: { error: "bfabric_id must be a positive integer" }, status: :unprocessable_entity
        return
      end

      result = DatasetRegistrationService.set_bfabric_id(data_set, bfabric_id)
      render json: result[:body], status: result[:http]
    end

    # DELETE /v1/datasets/:id
    def destroy
      data_set = DataSet.find_by(id: params[:id])
      # Idempotent: already-gone is a success.
      unless data_set
        render json: { ok: true, state: "COMPENSATED" }, status: :ok
        return
      end
      return unless scope_ok?(data_set)

      result = DatasetRegistrationService.deregister(data_set)
      render json: result[:body], status: result[:http]
    end

    private

    # --- filters ---------------------------------------------------------

    # Confidential transport. Opt-in: enforced only when SUSHI_API_ENFORCE_TLS=1
    # (set where a TLS-terminating proxy fronts the API). Off by default because
    # the intended deployment may reach this surface over an internal cleartext
    # port, which a blanket production-https rule would wrongly reject.
    def enforce_tls
      return unless ENV["SUSHI_API_ENFORCE_TLS"] == "1"
      return if request.ssl? || request.headers["X-Forwarded-Proto"].to_s.downcase == "https"
      render json: { error: "TLS required" }, status: :forbidden
    end

    # Fail-closed bearer-only authentication.
    def require_bearer_token
      @api_token = ApiToken.authenticate(bearer_token)
      return if @api_token
      render json: { error: "unauthorized" }, status: :unauthorized
    end

    # The registration API is for static (project-scoped) and user principals.
    # A machine principal belongs to the /internal bridge only; reject it here so
    # an infra credential cannot be repurposed to register/mutate datasets.
    def reject_machine_principal!
      return unless @api_token&.machine?
      render json: { error: "action not permitted for this token" }, status: :forbidden
    end

    # A user token must carry a non-blank login; reject before any resolver call.
    # Static tokens are unaffected.
    def reject_blank_user_login!
      return unless @api_token&.user?
      return unless @api_token.login.to_s.strip.empty?
      render json: { error: "unauthorized" }, status: :unauthorized
    end

    # Deny-unless-listed endpoint authority for user tokens. A user principal may
    # only reach the non-destructive whitelist; anything else (today destroy; any
    # future route) is 403. Static principals pass unconditionally — which is why
    # authorize_token_write! runs next: on its own this gate leaves a static
    # service credential MORE authority than a person's token, since a static
    # principal is unscoped by action and is attributed only as "apitoken:<name>".
    USER_ALLOWED_ACTIONS = %w[validate register set_bfabric_id].freeze
    def authorize_endpoint!
      return unless @api_token&.user?
      return if USER_ALLOWED_ACTIONS.include?(action_name)
      render json: { error: "action not permitted for this token" }, status: :forbidden
    end

    # Principal-independent write authority. Applies to static tokens too, closing
    # the asymmetry above. Fail-closed for tokens issued before the capabilities
    # column existed. See ApiToken::CAPABILITIES.
    def authorize_token_write!
      return if ApiTokenAuthenticatable::SAFE_HTTP_METHODS.include?(request.request_method)
      return if @api_token.nil? || @api_token.can_write?

      render json: {
        error: "action not permitted for this token",
        message: "This token is read-only. Grant write authority explicitly " \
                 "(rake api_token:grant_write ID=<id>) or use a token that has it."
      }, status: :forbidden
    end

    def bearer_token
      header = request.headers["Authorization"].to_s
      header[/\ABearer\s+(.+)\z/i, 1]
    end

    # The acting person's login for a user-principal token (used to own created
    # datasets so the UI "Who" shows the person). Static tokens have no person.
    def acting_login
      @api_token.user? ? @api_token.login : nil
    end

    # --- authz helpers ---------------------------------------------------

    # Principal-aware membership test. Static → the token's stored scope. User →
    # membership in the live-resolved set (W=0); resolved once per request and may
    # raise ResolverUnavailable (→ 503, handled by rescue_from).
    def token_allows_project?(project_number)
      return false if project_number.nil?
      if @api_token.user?
        (@user_allowed_projects ||= @api_token.allowed_projects).include?(project_number.to_i)
      else
        @api_token.in_scope?(project_number)
      end
    end

    # Request project_number must be authorized for the token.
    def authorize_project!(project_number)
      if project_number.to_s.empty?
        render json: { error: "project_number is required" }, status: :unprocessable_entity
        return false
      end
      unless token_allows_project?(project_number)
        render json: { error: "project #{project_number} out of scope" }, status: :forbidden
        return false
      end
      true
    end

    # IDOR guard: the target data_set's project must be authorized. Returns the
    # data_set, or nil after rendering. For a user token, a not-found dataset and
    # an out-of-scope existing dataset are BOTH 404 (indistinguishable) so dataset
    # IDs cannot be enumerated; static keeps 404/403.
    def find_scoped_data_set(id)
      data_set = DataSet.find_by(id: id)
      unless data_set
        render json: { error: "data_set #{id} not found" }, status: :not_found
        return nil
      end
      return nil unless scope_ok?(data_set)
      data_set
    end

    def scope_ok?(data_set)
      number = data_set.project&.number
      return true if token_allows_project?(number)

      if @api_token.user?
        render json: { error: "data_set #{data_set.id} not found" }, status: :not_found
      else
        render json: { error: "data_set out of scope" }, status: :forbidden
      end
      false
    end

    # --- request body ----------------------------------------------------

    def manifest_args
      {
        dataset_tsv:    body_param(:dataset_tsv),
        project_number: body_param(:project_number),
        name:           body_param(:name),
        parent_id:      body_param(:parent_id),
        order_id:       body_param(:order_id)
      }
    end

    def body_param(key)
      json_body[key.to_s]
    end

    # A malformed body raises JSON::ParserError → 400 via rescue_from, instead of
    # being silently treated as an empty request.
    def json_body
      @json_body ||= begin
        raw = request.body.read
        raw.to_s.empty? ? {} : JSON.parse(raw)
      end
    end
  end
end
