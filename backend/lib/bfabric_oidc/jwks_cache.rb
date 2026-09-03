# frozen_string_literal: true

module BfabricOidc
  # Caches B-Fabric's OIDC discovery document and its public signing keys (JWKS).
  #
  # Process-wide and mutex-guarded, because it sits on the login path and every cache miss
  # is a network call to an external service. It survives the development reloader only
  # because the whole module is `require`d rather than autoloaded — see lib/bfabric_oidc.rb.
  #
  # KEY ROTATION. A `kid` that is not in the cached set forces ONE refetch, rate-limited to
  # one per FORCED_REFETCH_MIN_INTERVAL seconds. Without the forced refetch, a rotation
  # locks every login out for up to TTL seconds (one hour) — a documented bfabricPy gotcha.
  # Without the rate limit, a stream of tokens carrying an unknown `kid` becomes a request
  # amplifier pointed at B-Fabric.
  class JwksCache
    TTL = 3600
    FORCED_REFETCH_MIN_INTERVAL = 60

    class << self
      # Returns the raw JWKS hash ({"keys" => [...]}), which is what JWT::JWK::Set accepts.
      #
      # `force: true` arrives from the jwt gem's key finder when a token's `kid` is not in
      # the set we handed it.
      def key_set(force: false)
        mutex.synchronize { jwks_locked(force: force) }
      end

      # The `iss` value a token must carry. An explicit BFABRIC_OIDC_ISSUER wins; otherwise
      # the discovery document's own `issuer`, which OIDC requires tokens to match.
      def expected_issuer
        explicit = BfabricOidc.config.expected_issuer
        return explicit if explicit

        mutex.synchronize { discovery_locked['issuer'] }
      end

      def discovery
        mutex.synchronize { discovery_locked }
      end

      # A lambda in the shape the jwt gem's JWK::KeyFinder calls: it passes a hash and
      # sets :kid_not_found (older versions: :invalidate) when it wants a fresh set.
      def jwks_loader
        lambda do |options = {}|
          opts = options.respond_to?(:[]) ? options : {}
          key_set(force: !!(opts[:kid_not_found] || opts[:invalidate]))
        end
      end

      def reset!
        mutex.synchronize do
          @discovery = nil
          @discovery_at = nil
          @jwks = nil
          @jwks_at = nil
          @last_forced_at = nil
        end
      end

      private

      def mutex
        @mutex ||= Mutex.new
      end

      def now
        Time.now.to_i
      end

      def jwks_locked(force: false)
        if force
          # Rate-limit the forced path. When it is suppressed we return the set we have
          # rather than raising: the token will simply fail to verify, which is the
          # correct outcome for an unknown `kid` we cannot currently explain.
          if @last_forced_at && (now - @last_forced_at) < FORCED_REFETCH_MIN_INTERVAL
            return @jwks if @jwks

            raise Unreachable, 'JWKS refetch is rate-limited and no cached key set exists'
          end

          @last_forced_at = now
          @jwks = nil
        end

        return @jwks if @jwks && @jwks_at && (now - @jwks_at) < TTL

        uri = BfabricOidc.config.jwks_uri || discovery_locked['jwks_uri']
        raise Unreachable, 'no jwks_uri in configuration or discovery document' if uri.to_s.strip.empty?

        body = fetch_json(uri)
        unless body.is_a?(Hash) && body['keys'].is_a?(Array)
          raise Unreachable, "JWKS at #{uri} did not contain a `keys` array"
        end

        @jwks = body
        @jwks_at = now
        @jwks
      end

      def discovery_locked
        return @discovery if @discovery && @discovery_at && (now - @discovery_at) < TTL

        url = BfabricOidc.config.discovery_url
        raise Unreachable, 'BFABRIC_OIDC_BASE_URL is not configured' if url.nil?

        body = fetch_json(url)
        raise Unreachable, "discovery document at #{url} was not a JSON object" unless body.is_a?(Hash)

        @discovery = body
        @discovery_at = now
        @discovery
      end

      def fetch_json(url)
        uri = URI.parse(url)
        raise Unreachable, "refusing to fetch a non-http(s) URL: #{url}" unless uri.is_a?(URI::HTTP)

        timeout = BfabricOidc.config.http_timeout
        response = Net::HTTP.start(uri.host, uri.port,
                                   use_ssl: uri.scheme == 'https',
                                   open_timeout: timeout,
                                   read_timeout: timeout) do |http|
          http.request(Net::HTTP::Get.new(uri.request_uri, 'Accept' => 'application/json'))
        end

        unless response.is_a?(Net::HTTPSuccess)
          raise Unreachable, "GET #{uri} answered #{response.code}"
        end

        JSON.parse(response.body)
      rescue Unreachable
        raise
      rescue JSON::ParserError => e
        raise Unreachable, "GET #{url} did not return JSON: #{e.message}"
      rescue StandardError => e
        # Deliberately broad: Net::HTTP raises a wide and version-dependent family
        # (Errno::*, SocketError, OpenSSL::SSL::SSLError, Net::OpenTimeout). Every one of
        # them means the same thing to the caller — B-Fabric is not answering — and none
        # of them should surface as a 500 on a login endpoint.
        raise Unreachable, "GET #{url} failed: #{e.class}: #{e.message}"
      end
    end
  end
end
