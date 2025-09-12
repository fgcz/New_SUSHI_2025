module FGCZ
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



