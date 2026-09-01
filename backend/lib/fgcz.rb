module FGCZ
  LDAP_HOST = 'fgcz-bfabric-ldap'
  LDAP_BASE = 'dc=bfabric,dc=org'
  EMPLOYEE_GROUP = 'SG_Employees'

  # Is this login an FGCZ employee?
  #
  # Mirrors the legacy `fgcz` gem (/usr/local/ngseq/gems/fgcz/lib/fgcz.rb:47):
  # read `memberUid` off the LDAP group `SG_Employees`. Verified against the live
  # directory — 77 members.
  #
  # WHAT LEGACY USES IT FOR, so nobody assumes parity: legacy lets an employee jump
  # to a project they are not a member of. It does NOT gate job submission on this
  # — any signed-in user may submit into their own projects. Our use is stricter
  # and INTERIM, a safety valve while New SUSHI's submit path earns confidence on
  # production. To remove it, delete the employee check in
  # Api::V1::JobsController#create and its specs; nothing else depends on this.
  #
  # Uses net-ldap rather than shelling out the way get_user_projects2 does: this
  # answer gates a WRITE, and a PATH lookup for a binary that lives in a conda
  # environment is a weaker thing to stake that on than a declared gem.
  #
  # FAILS CLOSED. Library missing, directory unreachable, malformed answer — all
  # return false, which means "not an employee", which means no write.
  def self.employee?(login)
    login = login.to_s
    return false if login.strip.empty?

    require 'net/ldap'

    ldap = Net::LDAP.new(
      host: LDAP_HOST,
      port: 636,
      encryption: :simple_tls,
      verify_mode: OpenSSL::SSL::VERIFY_PEER
    )

    member = false
    ldap.search(
      base: LDAP_BASE,
      filter: Net::LDAP::Filter.eq('cn', EMPLOYEE_GROUP),
      attributes: ['memberUid']
    ) { |entry| member ||= Array(entry['memberuid']).include?(login) }

    # A failed search returns no entries and would look exactly like "not a
    # member", so check the operation result rather than trusting the silence.
    code = ldap.get_operation_result.code
    unless code.zero?
      Rails.logger.error("FGCZ.employee? LDAP search failed for #{login}: #{ldap.get_operation_result.message}")
      return false
    end

    member
  rescue LoadError, StandardError => e
    Rails.logger.error("FGCZ.employee? error for #{login}: #{e.message}")
    false
  end

  # Returns array like ["p1001", "p1234", ...]
  def self.get_user_projects2(login)
    projects = []
    command = "ldapsearch -x -H 'ldaps://fgcz-bfabric-ldap' -b 'dc=bfabric,dc=org' '(cn=#{login})' memberof"
    IO.popen(command) do |io|
      io.each_line do |line|
        if line !~ /^#/ && line =~ /^memberOf/ && line =~ /cn=P_(\d+)/
          project_number = Regexp.last_match(1)
          projects << "p#{project_number}"
        end
      end
    end
    projects
  rescue => e
    Rails.logger.error "FGCZ.get_user_projects2 error for #{login}: #{e.message}"
    []
  end
end



