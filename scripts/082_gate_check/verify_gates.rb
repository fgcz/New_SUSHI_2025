# Assert what the three write gates are actually doing on the node this runs on.
#
# Runs on the REAL boot path (`rails runner` executes after_initialize), so it sees the
# same credentials and policy the server does. Needs no HTTP — which matters, because the
# agent harness denies mutating HTTP verbs against production — and leaves no orphan
# process. Read-only: nothing here saves, writes or migrates.
#
# It adapts to the node's configuration and asserts the expectations for that state:
#
#   * NO write credential configured  -> the read-only posture (Phase 3 step 12)
#   * a write credential configured   -> the cutover posture (Phase 4 step 15: "re-prove
#                                        the negative space FIRST, before submitting")
#
# Either way it first proves the write-credential code is LOADED, because without that
# every "cannot write" assertion below would pass vacuously on a node that simply does not
# have the feature.
#
# Usage:  bash scripts/082_gate_check/run.sh <launch script>

results = []

def check(results, label, actual, expected)
  ok = (actual == expected)
  results << ok
  puts format("  [%s] %-58s got %s", ok ? "PASS" : "FAIL", label, actual.inspect)
end

policy = Middleware::SushiReadOnlyGuard.new(nil).send(:policy)

# Probed defensively and BEFORE anything else touches the write API: on a node that does
# not carry this code, calling it would raise and the run would die with a backtrace
# instead of reporting a clean failure. A check that crashes tells you less than one that
# fails.
code_loaded = ApiToken.new.respond_to?(:grant_env_write!) &&
              EnvApiToken.respond_to?(:write_enabled?) &&
              EnvApiToken.const_defined?(:WRITE_VARS)
write_configured = code_loaded && EnvApiToken.write_enabled?

puts "posture: write-credential code #{code_loaded ? 'LOADED' : 'NOT PRESENT'}, " \
     "write credential #{write_configured ? 'CONFIGURED' : 'ABSENT'}, " \
     "rack policy #{policy.inspect}"
puts

puts "=== 0. the write-credential code is loaded (else everything below is vacuous) ==="
check(results, "ApiToken responds to grant_env_write!",
      ApiToken.new.respond_to?(:grant_env_write!), true)
check(results, "ApiToken responds to env_write_granted?",
      ApiToken.new.respond_to?(:env_write_granted?), true)
check(results, "EnvApiToken knows the three WRITE variables",
      code_loaded ? EnvApiToken::WRITE_VARS : "(EnvApiToken has no WRITE_VARS)",
      %w[SUSHI_ENV_TOKEN_WRITE_SHA256 SUSHI_ENV_TOKEN_WRITE_SCOPE SUSHI_ENV_TOKEN_WRITE_NAME])

unless code_loaded
  puts "\nThis node does not carry the write-credential code, so the remaining assertions"
  puts "would be vacuous and are not run. Deploy feat/082-env-write-credential (or a"
  puts "revision that contains it) and re-run."
  puts "\n" + "-" * 78
  puts "#{results.count(false)} of #{results.size} CHECKS FAILED"
  exit 1
end

puts "\n=== 1. the READ credential is configured and healthy ==="
check(results, "EnvApiToken.enabled?", EnvApiToken.enabled?, true)
check(results, "EnvApiToken.errors", EnvApiToken.errors, [])
puts "        (scope #{EnvApiToken.config&.scope.inspect}, name #{EnvApiToken.config&.name.inspect})"

puts "\n=== 2. the READ credential can never write, in either posture ==="
read_token = EnvApiToken.send(:build, EnvApiToken.config, write: false)
check(results, "read token can_write?", read_token.can_write?, false)
check(results, "read token env_write_granted?", read_token.env_write_granted?, false)
check(results, "read token effective_capabilities", read_token.effective_capabilities, ["read"])
check(results, "read token is unsaved", read_token.persisted?, false)

puts "\n=== 3. gate 3 — the capabilities column must stay ABSENT on 082 ==="
check(results, "api_tokens has a capabilities column",
      ApiToken.column_names.include?("capabilities"), false)
puts "        (#{ApiToken.column_names.size} columns, #{ApiToken.count} rows — expect the row " \
     "count to grow: legacy owns this table)"

if write_configured
  puts "\n=== 4. CUTOVER posture — a write credential IS configured ==="
  write_cfg = EnvApiToken.write_config
  write_token = EnvApiToken.send(:build, write_cfg, write: true)
  check(results, "write token can_write?", write_token.can_write?, true)
  check(results, "write token env_write_granted?", write_token.env_write_granted?, true)
  check(results, "write token effective_capabilities is STILL [read] (the documented inversion)",
        write_token.effective_capabilities, ["read"])
  check(results, "write token is unsaved", write_token.persisted?, false)
  check(results, "the two credentials have DIFFERENT names",
        write_cfg.name != EnvApiToken.config.name, true)
  check(results, "the rack policy is additive, not full", policy, "additive")
  puts "        write credential scope #{write_cfg.scope.inspect}, name #{write_cfg.name.inspect}"
  puts "        -> production rows created in this window are attributable to " \
       "apitoken:#{write_cfg.name}"
else
  puts "\n=== 4. READ-ONLY posture — no write credential configured ==="
  check(results, "EnvApiToken.write_config", EnvApiToken.write_config, nil)
  EnvApiToken::WRITE_VARS.each do |v|
    check(results, "ENV[#{v}] is empty", ENV[v].to_s, "")
  end
  check(results, "rack policy is read_only", policy, "read_only")
  check(results, "ENV[SUSHI_WRITE_POLICY] is unset", ENV["SUSHI_WRITE_POLICY"].to_s, "")

  puts "\n=== 5. the grant mechanism still WORKS when asked — the above is not vacuous ==="
  # An in-memory throwaway, never saved, discarded when this process exits. Without this,
  # a broken or no-op grant_env_write! would make every assertion above pass for the wrong
  # reason.
  probe = ApiToken.new(name: "gate-check-probe", principal: "static", scope: [0])
  probe.grant_env_write!
  check(results, "a granted token reports can_write?", probe.can_write?, true)
  check(results, "...while its effective_capabilities stay [read]",
        probe.effective_capabilities, ["read"])
end

puts "\n=== 6. authority cannot be promoted onto a database row ==="
check(results, "grant_env_write! refuses a PERSISTED record",
      begin
        ApiToken.first&.grant_env_write!
        "no error raised"
      rescue StandardError => e
        e.class.name
      end,
      "ArgumentError")

failed = results.count(false)
puts "\n" + "-" * 78
puts(failed.zero? ? "ALL #{results.size} CHECKS PASS" : "#{failed} of #{results.size} CHECKS FAILED")
exit(failed.zero? ? 0 : 1)
