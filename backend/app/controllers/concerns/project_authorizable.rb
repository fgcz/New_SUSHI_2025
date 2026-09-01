module ProjectAuthorizable
  extend ActiveSupport::Concern

  private

  def authorize_project!(project_number)
    # Token requests are always scope-enforced, even when global auth is skipped.
    token = respond_to?(:token_authenticated?, true) && token_authenticated?
    return if AuthenticationHelper.authentication_skipped? && !token

    unless current_user_project_numbers.include?(project_number.to_s)
      render json: { error: 'Forbidden' }, status: :forbidden
    end
  end

  def authorize_dataset!(dataset)
    authorize_project!(dataset.project.number.to_s)
  end

  def authorize_job!(job)
    dataset = DataSet.find_by(id: job.next_dataset_id) ||
              DataSet.find_by(id: job.input_dataset_id)

    unless dataset
      render json: { error: 'Forbidden' }, status: :forbidden
      return
    end

    authorize_project!(dataset.project.number.to_s)
  end

  def current_user_project_numbers
    # A bearer ApiToken authorizes exactly its own projects (user → live FGCZ;
    # static → stored scope), enforced regardless of authentication_skipped?.
    if respond_to?(:token_authenticated?, true) && token_authenticated?
      return @current_user_project_numbers ||= api_token_project_numbers.map(&:to_s)
    end
    @current_user_project_numbers ||= resolve_projects_for(current_user)
  end

  # Project numbers (as strings) the given user may access. Used by AuthController
  # to build the contract User payload, sharing one resolver with authorize_project!.
  def current_user_project_numbers_for(user)
    resolve_projects_for(user)
  end

  def resolve_projects_for(user)
    if defined?(FGCZ) && FGCZ.respond_to?(:get_user_projects2) && user
      begin
        FGCZ.get_user_projects2(user.login).map { |p| p.gsub(/p/, '').to_s }
      rescue => e
        Rails.logger.error("ProjectAuthorizable LDAP lookup failed: #{e.message}")
        projects_when_resolution_unavailable
      end
    else
      projects_when_resolution_unavailable
    end
  end

  # Fail-closed in production: when FGCZ project resolution is unavailable we deny
  # everything rather than granting all projects. The permissive fallback is kept
  # only for non-production dev convenience and when authentication is skipped.
  def projects_when_resolution_unavailable
    if Rails.env.production? && !AuthenticationHelper.authentication_skipped?
      Rails.logger.error("ProjectAuthorizable: project resolution unavailable in production — denying all projects (fail-closed)")
      []
    else
      fallback_all_projects
    end
  end

  def fallback_all_projects
    Project.pluck(:number).map(&:to_s)
  end

  # The project numbers this caller may see, as Integers. Lived privately in
  # ProjectsController until the gStore browser needed the same rule; moved here
  # unchanged so there is one answer rather than two.
  def authorized_project_numbers
    @authorized_project_numbers ||= resolve_user_projects
  end

  def resolve_user_projects
    # A bearer ApiToken authorizes exactly its own projects (user → live FGCZ;
    # static → stored scope), taking precedence over the anonymous default.
    if respond_to?(:token_authenticated?, true) && token_authenticated?
      return api_token_project_numbers.uniq.sort
    end

    # Anonymous mode → allow access to all existing projects
    if AuthenticationHelper.authentication_skipped?
      return Project.pluck(:number).uniq.sort
    end

    # Course mode
    if AuthenticationHelper.respond_to?(:course_mode?) && AuthenticationHelper.course_mode?
      users = SushiFabric::Application.config.course_users rescue nil
      return users ? users.flatten.uniq.sort : [1001]
    end

    # FGCZ/LDAP mode
    if AuthenticationHelper.ldap_auth_enabled? && current_user
      begin
        if defined?(FGCZ) && FGCZ.respond_to?(:get_user_projects2)
          return FGCZ.get_user_projects2(current_user.login).map { |p| p.gsub(/p/, '').to_i }.sort
        end
      rescue => e
        Rails.logger.error "FGCZ project lookup failed: #{e.message}"
      end
    end

    # Fallback - allow access to all existing projects
    Project.pluck(:number).uniq.sort
  end
end
