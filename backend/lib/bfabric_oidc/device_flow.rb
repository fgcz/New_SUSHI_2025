# frozen_string_literal: true

module BfabricOidc
  # The browser-side device-code login, mediated by this backend.
  #
  # WHY THE BACKEND SITS IN THE MIDDLE. The browser could in principle drive B-Fabric's
  # device endpoints itself, and must not, for two reasons:
  #
  #   1. B-Fabric is a different origin and does not advertise CORS for these endpoints,
  #      so the browser's request would simply be refused.
  #   2. It would put a B-FABRIC token in the page. That token is LIMS-wide; the SUSHI
  #      session it buys is not. One cross-site scripting bug would then cost the whole
  #      LIMS rather than a 30-minute session. Mediating here means the browser only ever
  #      sees the SUSHI JWT it already handles today.
  #
  # WHY DEVICE CODE AND NOT AUTHORIZATION CODE, for now. Authorization code needs a
  # CONFIDENTIAL client registered with our exact redirect_uri, and `register_client`
  # accepts only one URI — so a TLS decision has to be made before anyone registers
  # anything. Device code uses the PUBLIC client `CLI`, which already exists on both
  # instances and needs no registration, no secret and no redirect_uri. It is the bridge:
  # it stops the user's password reaching this backend TODAY. Both flows converge on the
  # same `establish_session`, so replacing it later changes nothing downstream.
  #
  # THIS SURFACE IS UNAUTHENTICATED, because it is the login. That is why the pending
  # table is bounded and why the poll interval is enforced HERE rather than trusted from
  # the client: without both, an anonymous caller could grow this table without limit and
  # use us to hammer B-Fabric.
  class DeviceFlow
    # A hard ceiling on concurrent logins-in-progress. Real concurrent logins on one node
    # are a handful; this is a backstop against an anonymous caller, not a capacity plan.
    MAX_PENDING = 100

    # Nothing lives longer than a device code can (RFC 8628 expires_in, 900 s in practice).
    MAX_TTL = 900

    Pending = Struct.new(:device_code, :token_url, :client_id, :scope,
                         :expires_at, :interval, :next_poll_at, keyword_init: true)

    class << self
      # Returns the payload the browser needs, and NOTHING that would let it (or anyone who
      # sees the response) redeem the login itself: `device_code` stays here.
      def start(scope:)
        disc = JwksCache.discovery
        device_url = disc["device_authorization_endpoint"]
        token_url = disc["token_endpoint"]
        raise Unreachable, "this B-Fabric instance advertises no device_authorization_endpoint" if device_url.to_s.empty?

        client_id = BfabricOidc.config.device_client_id
        body = post_form(device_url, client_id: client_id, scope: scope)

        %w[device_code user_code verification_uri].each do |k|
          raise Unreachable, "the device authorization response has no #{k}" if body[k].to_s.empty?
        end

        interval = [body["interval"].to_i, 1].max
        ttl = [[body["expires_in"].to_i, 1].max, MAX_TTL].min
        handle = SecureRandom.urlsafe_base64(32)

        store do |table|
          prune(table)
          raise TooBusy if table.size >= MAX_PENDING

          table[handle] = Pending.new(
            device_code: body["device_code"], token_url: token_url, client_id: client_id,
            scope: scope, expires_at: now + ttl, interval: interval, next_poll_at: now
          )
        end

        {
          handle: handle,
          user_code: body["user_code"],
          verification_uri: body["verification_uri"],
          # RFC 8628's `verification_uri_complete` — the one that needs no typing — is NOT
          # sent by B-Fabric (measured on both instances, 2026-09-03), so this is a URL we
          # construct: the same approval page with `?user_code=` appended.
          #
          # IT WORKS. Confirmed by a human sign-in on 2026-09-03: the code arrived already
          # filled in. That could not be checked from outside — the page redirects to the
          # B-Fabric home page for an unauthenticated fetch — so only a person at a browser
          # could establish it, and one did. Keep the fallback anyway: the caller also
          # receives `user_code` and displays it, so a future B-Fabric change that stops
          # honouring the parameter costs a paste rather than a failed sign-in.
          verification_uri_complete: body["verification_uri_complete"],
          verification_uri_guess: with_user_code(body["verification_uri"], body["user_code"]),
          interval: interval,
          expires_in: ttl
        }
      end

      # One poll. Returns [status, payload]:
      #   [:pending, nil]           not approved yet
      #   [:too_soon, seconds]      the caller asked again before its own interval elapsed
      #   [:ok, access_token]       approved — the B-Fabric access token, for the caller
      #                             to exchange immediately and then forget
      #   [:expired, nil]           the device code lapsed, or the handle is unknown
      #   [:error, message]         B-Fabric refused
      def poll(handle)
        pending = store { |table| prune(table); table[handle] }
        return [:expired, nil] if pending.nil?

        wait = pending.next_poll_at - now
        return [:too_soon, wait] if wait.positive?

        body = post_form(pending.token_url,
                         grant_type: "urn:ietf:params:oauth:grant-type:device_code",
                         device_code: pending.device_code,
                         client_id: pending.client_id)

        case body["error"]
        when nil
          token = body["access_token"].to_s
          # Single use: whatever happens next, this handle is spent.
          forget(handle)
          return [:error, "B-Fabric returned no access token"] if token.empty?

          [:ok, token]
        when "authorization_pending"
          store { |t| t[handle]&.next_poll_at = now + pending.interval }
          [:pending, nil]
        when "slow_down"
          # RFC 8628: back off by 5 s and keep the longer interval from now on.
          store do |t|
            entry = t[handle]
            next unless entry

            entry.interval += 5
            entry.next_poll_at = now + entry.interval
          end
          [:pending, nil]
        when "expired_token", "access_denied"
          forget(handle)
          [:expired, nil]
        else
          forget(handle)
          [:error, body["error"].to_s]
        end
      end

      def forget(handle)
        store { |table| table.delete(handle) }
      end

      def pending_count
        store { |table| prune(table); table.size }
      end

      def reset!
        store { |table| table.clear }
      end

      private

      def now
        Time.now.to_i
      end

      def store
        @mutex ||= Mutex.new
        @table ||= {}
        @mutex.synchronize { yield @table }
      end

      def prune(table)
        table.delete_if { |_, p| p.expires_at <= now }
      end

      def with_user_code(uri, user_code)
        return uri if uri.to_s.empty? || user_code.to_s.empty?

        sep = uri.include?("?") ? "&" : "?"
        "#{uri}#{sep}user_code=#{CGI.escape(user_code)}"
      end

      def post_form(url, **params)
        uri = URI.parse(url)
        raise Unreachable, "refusing to post to a non-http(s) URL" unless uri.is_a?(URI::HTTP)

        timeout = BfabricOidc.config.http_timeout
        request = Net::HTTP::Post.new(uri.request_uri, "Accept" => "application/json")
        request.set_form_data(params.transform_keys(&:to_s))

        response = Net::HTTP.start(uri.host, uri.port,
                                   use_ssl: uri.scheme == "https",
                                   open_timeout: timeout, read_timeout: timeout) do |http|
          http.request(request)
        end

        JSON.parse(response.body)
      rescue Unreachable
        raise
      rescue JSON::ParserError
        # A non-JSON body from the token endpoint is a B-Fabric-side fault, not a bad
        # credential; the caller turns Unreachable into 503 rather than 401.
        raise Unreachable, "POST #{url} did not return JSON"
      rescue StandardError => e
        raise Unreachable, "POST #{url} failed: #{e.class}: #{e.message}"
      end
    end

    # Raised when the pending table is full. Surfaces as 503 with a retry hint — the node
    # is busy, the caller's credentials are not the problem.
    class TooBusy < Error; end
  end
end
