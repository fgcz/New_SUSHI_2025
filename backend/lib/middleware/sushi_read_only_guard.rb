# frozen_string_literal: true

require "json"

module Middleware
  # Rack-level server-side write-policy guard. Enforced BEFORE any controller, so it
  # covers ALL surfaces uniformly (/api/v1, /v1, /internal, auth) regardless of base
  # class. The sushi-chain MCP proxy allow_writes flag is a second, client-side layer
  # (defense in depth).
  #
  # Policy is chosen by SUSHI_WRITE_POLICY (read_only | additive | full); for backward
  # compatibility SUSHI_READ_ONLY=1 still means read_only, and the default is full.
  #
  #   read_only  — reject every non-safe method (POST/PUT/PATCH/DELETE). Only safe
  #                methods and the dry-run allowlist (validation) pass.
  #   additive   — allow CREATE-only user operations (job submit, dataset import) and
  #                the internal machine bridge, but reject DELETE and mutating PUT/PATCH
  #                on user surfaces. This lets New SUSHI ADD to a (production) DB without
  #                being able to delete or rewrite existing data — matching the
  #                additive-only data discipline. NOTE: B-Fabric registration is NOT part
  #                of this policy; it is a separate, caller-controlled gate.
  #   full       — no restriction (default when neither env is set).
  #
  # The internal bridge (/internal/*, machine principal) is exempt under `additive` so
  # the job_manager can advance job state (CREATED→RUNNING→COMPLETED); its principal
  # auth is still enforced downstream. Under `read_only` the bridge is blocked too
  # (a read-only mirror has no writing daemon).
  class SushiReadOnlyGuard
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
      end

      deny(pol, method, env["PATH_INFO"].to_s)
    end

    private

    def policy
      explicit = ENV["SUSHI_WRITE_POLICY"].to_s.strip.downcase
      return explicit if %w[read_only additive full].include?(explicit)
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

    def deny(pol, method, path)
      body = JSON.generate(
        error: pol, # "read_only" | "additive"
        message: "This SUSHI backend write policy is '#{pol}'; " \
                 "#{method} #{path} is not permitted."
      )
      # Rack 3 (Rails 8) requires lowercase response header field names.
      [403, { "content-type" => "application/json" }, [body]]
    end
  end
end
