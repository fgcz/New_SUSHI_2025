# frozen_string_literal: true

require "json"

module Middleware
  # Rack-level server-side write-policy guard. Enforced BEFORE any controller, so it
  # covers ALL surfaces uniformly (/api/v1, /v1, /internal, auth) regardless of base
  # class. The sushi-chain MCP proxy allow_writes flag is a second, client-side layer
  # (defense in depth).
  #
  # Policy is chosen by SUSHI_WRITE_POLICY (read_only | submit_only | additive | full); for
  # backward compatibility SUSHI_READ_ONLY=1 still means read_only, and the default is full.
  # Ordered strictest first:
  #
  #   read_only   — reject every non-safe method (POST/PUT/PATCH/DELETE). Only safe
  #                 methods and the dry-run allowlist (validation) pass.
  #   submit_only — allow exactly one WRITING REQUEST: job submission. Dataset import, the
  #                 set-once B-Fabric link and every MUTATING request to the internal
  #                 bridge are refused. (Safe methods are never gated by any policy, so a
  #                 GET under /internal/ still passes — see the caveat below.) Its purpose is
  #                 that a backend sharing a database with the live legacy production system
  #                 exposes a single writing route, so a new app or an AI agent calling an
  #                 individual endpoint cannot reach the database through any other one.
  #                 The routes it closes have no live producer today: nothing here registers
  #                 anything in B-Fabric, and the job_manager daemon reads MySQL directly
  #                 rather than calling the bridge (checked 2026-08-07).
  #   additive    — allow CREATE-only user operations (job submit, dataset import) and
  #                 the internal machine bridge, but reject DELETE and mutating PUT/PATCH
  #                 on user surfaces. This lets New SUSHI ADD to a (production) DB without
  #                 being able to delete or rewrite existing data — matching the
  #                 additive-only data discipline. NOTE: B-Fabric registration is NOT part
  #                 of this policy; it is a separate, caller-controlled gate.
  #   full        — no restriction (default when neither env is set).
  #
  # The internal bridge (/internal/*, machine principal) is exempt under `additive` so
  # the job_manager can advance job state (CREATED→RUNNING→COMPLETED); its principal
  # auth is still enforced downstream. Under `read_only` the bridge is blocked too
  # (a read-only mirror has no writing daemon), and under `submit_only` its mutating verbs
  # are blocked by design — that exemption is the one surface this policy narrows which
  # `additive` did not restrict at all.
  #
  # CAVEAT — no policy here makes the PROCESS read-only, and `read_only` is not a promise
  # that nothing is written. This guard gates HTTP methods and paths; it cannot see what a
  # handler does. At least one READ path writes: `DataSet#samples_length` backfills
  # `num_samples` with `save` when the column is NULL, and it is called from
  # `GET /api/v1/datasets/:id` and `GET /api/v1/projects/:number/datasets`. Legacy's
  # `data_set.rb` has the identical method, so this is PARITY, not a defect introduced here,
  # and it is deliberately not changed. Two consequences worth knowing:
  #   * a GET can UPDATE a row, which row COUNTS and max(id) cannot detect — do not treat
  #     "counts unchanged" as proof that nothing was written;
  #   * measured on the production database 2026-08-27: 55 of 82,967 `data_sets` rows have a
  #     NULL `num_samples`, and 0 of the 18 rows reachable under the project-scoped
  #     credential — so the backfill could fire there in principle but not through that
  #     credential's scope.
  # Found by an independent cross-model review of the `submit_only` commit, not by these
  # specs, which stop at the middleware boundary with a dummy downstream app.
  class SushiReadOnlyGuard
    # Every recognized policy value. A non-empty value absent from this list is a
    # misconfiguration and fails CLOSED — see #policy.
    POLICIES = %w[read_only submit_only additive full].freeze

    SAFE_METHODS = %w[GET HEAD OPTIONS TRACE].freeze

    # POST endpoints that perform NO write (validation/dry-run) — allowed in every
    # non-full policy. Matched after normalizing trailing slash / .format suffix.
    DRY_RUN_PATHS = %w[
      /v1/datasets/validate
    ].freeze

    # Additive (create-only) routes allowed under the `additive` policy. Each entry is
    # [METHOD, normalized-path]. These CREATE new rows/jobs; they never delete or rewrite
    # existing data. Deliberately excludes DELETE /v1/datasets/:id (deregister).
    ADDITIVE_ROUTES = [
      ["POST", "/api/v1/jobs"],           # job submission
      ["POST", "/v1/datasets/register"],  # content-based dataset import (idempotent)
      ["POST", "/api/v1/datasets/from_tsv"] # TSV-body dataset import
    ].freeze

    # Same rule, for routes carrying an id segment.
    #
    # PUT /v1/datasets/:id/bfabric-id is here despite being a PUT because
    # DatasetRegistrationService.set_bfabric_id is strictly SET-ONCE: it fills the field
    # when NULL, returns 200 idempotently for the same value, and refuses a different
    # value with 409. It therefore satisfies this policy's own criterion — never delete
    # or rewrite existing data — and only the HTTP verb made it look like a mutation.
    # Denying it meant a dataset New SUSHI created on a production DB could never be
    # linked to its B-Fabric record through the API at all, which breaks parity with the
    # legacy system sharing that DB. Registration IN B-Fabric remains a separate,
    # caller-controlled step; this only records the resulting id.
    ADDITIVE_ROUTE_PATTERNS = [
      ["PUT", %r{\A/v1/datasets/\d+/bfabric-id\z}]
    ].freeze

    # The single write allowed under `submit_only`. Matched the same way ADDITIVE_ROUTES is —
    # by EXACT [method, normalized-path] equality, never by prefix, because a prefix match
    # would open everything living under the job path (`/api/v1/jobs/123/cancel`) and every
    # other verb on the path itself. Kept as its own list rather than derived from
    # ADDITIVE_ROUTES so that adding a route to the additive policy later cannot silently
    # widen this one.
    SUBMIT_ONLY_ROUTES = [
      ["POST", "/api/v1/jobs"] # job submission — the only write this policy permits
    ].freeze

    def initialize(app)
      @app = app
    end

    def call(env)
      pol = policy
      return @app.call(env) if pol == "full"

      method = env["REQUEST_METHOD"]
      return @app.call(env) if SAFE_METHODS.include?(method)

      path = normalize(env["PATH_INFO"].to_s)
      return @app.call(env) if dry_run?(path)

      if pol == "additive"
        return @app.call(env) if internal_bridge?(path)
        return @app.call(env) if additive?(method, path)
      elsif pol == "submit_only"
        # No internal_bridge? exemption here, deliberately.
        return @app.call(env) if submit_only?(method, path)
      end

      deny(pol, method, env["PATH_INFO"].to_s)
    end

    private

    def policy
      explicit = ENV["SUSHI_WRITE_POLICY"].to_s.strip.downcase
      return explicit if POLICIES.include?(explicit)

      # A non-empty value that is not a recognized policy is a MISCONFIGURATION, not a
      # request for the default. Falling through would read `submitonly` or `additivee` as
      # `full` and grant every write against a database shared with the live legacy
      # production system, so it fails CLOSED instead. An UNSET variable is not a typo: it
      # keeps the historical default below, so no existing deployment changes behaviour.
      return "read_only" unless explicit.empty?

      return "read_only" if ENV["SUSHI_READ_ONLY"] == "1"
      "full"
    end

    # Normalize a trailing slash and any .format suffix before matching.
    def normalize(path)
      path.sub(%r{/\z}, "").sub(/\.[a-z0-9]+\z/i, "")
    end

    def dry_run?(path)
      DRY_RUN_PATHS.include?(path)
    end

    def internal_bridge?(path)
      path.start_with?("/internal/")
    end

    def additive?(method, path)
      return true if ADDITIVE_ROUTES.include?([method, path])

      ADDITIVE_ROUTE_PATTERNS.any? { |m, re| m == method && re.match?(path) }
    end

    def submit_only?(method, path)
      SUBMIT_ONLY_ROUTES.include?([method, path])
    end

    def deny(pol, method, path)
      body = JSON.generate(
        error: pol, # "read_only" | "submit_only" | "additive"
        message: "This SUSHI backend write policy is '#{pol}'; " \
                 "#{method} #{path} is not permitted."
      )
      # Rack 3 (Rails 8) requires lowercase response header field names.
      [403, { "content-type" => "application/json" }, [body]]
    end
  end
end
