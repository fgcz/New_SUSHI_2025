module Api
  module V1
    class ProjectsController < BaseController
      # Returns accessible projects for current_user or default when auth skipped
      def index
        projects = resolve_user_projects
        render json: {
          projects: projects.map { |n| { number: n } },
          current_user: current_user&.login || 'anonymous'
        }
      end

      # Returns datasets under a project_number with authorization checks
      def datasets
        # Accept various param keys depending on routing/helper
        number_param = params[:project_number] || params[:project_id] || params[:project_project_number] || params[:id]
        number = number_param.to_i
        unless authorized_project_numbers.include?(number)
          return render json: { error: 'Project not accessible' }, status: :forbidden
        end

        # Basic pagination and search
        page = (params[:page] || 1).to_i
        per  = [[(params[:per] || 50).to_i, 200].min, 1].max
        q    = (params[:q] || '').to_s.strip

        rel = DataSet.joins(:project)
          .where(projects: { number: number })
        rel = rel.where('data_sets.name LIKE ?', "%#{q}%") unless q.empty?

        total_count = rel.count
        datasets = rel.order(created_at: :desc).offset((page - 1) * per).limit(per)

        render json: {
          datasets: datasets.map { |ds| serialize_dataset_row(ds) },
          total_count: total_count,
          page: page,
          per: per,
          project_number: number
        }
      end

      # Returns tree structure of datasets for a project
      def datasets_tree
        number_param = params[:project_number] || params[:project_id] || params[:project_project_number] || params[:id]
        number = number_param.to_i
        unless authorized_project_numbers.include?(number)
          return render json: { error: 'Project not accessible' }, status: :forbidden
        end

        project = Project.find_by(number: number)
        unless project
          return render json: { error: 'Project not found' }, status: :not_found
        end

        # Preload associations for efficiency
        datasets = project.data_sets.includes(:data_sets, :user)

        parent_exists_map = datasets.each_with_object({}) { |ds, h| h[ds.id] = true }

        tree_nodes = datasets.map do |dataset|
          {
            id: dataset.id,
            text: "#{dataset.data_sets.length} #{dataset.name} <small><font color='gray'>#{dataset.comment}</font></small>",
            parent: (dataset.parent_id && parent_exists_map[dataset.parent_id]) ? dataset.parent_id : "#",
            a_attr: {
              href: "/projects/#{number}/datasets/#{dataset.id}"
            },
            dataset_data: serialize_dataset_row(dataset)
          }
        end

        render json: {
          tree: tree_nodes.sort_by { |node| -node[:id].to_i },
          project_number: number
        }
      end

      private

      def serialize_dataset_row(dataset)
        {
          id: dataset.id,
          name: dataset.name,
          sushi_app_name: dataset.sushi_app_name,
          completed_samples: dataset.completed_samples,
          samples_length: dataset.samples_length,
          parent_id: dataset.parent_id,
          children_ids: dataset.data_sets.pluck(:id),
          user_login: dataset.user&.login,
          created_at: dataset.created_at,
          bfabric_id: dataset.bfabric_id,
          project_number: dataset.project&.number
        }
      end

      def resolve_user_projects
        # Anonymous mode → default [1001]
        return [1001] if AuthenticationHelper.authentication_skipped?

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

        # Fallback
        [1001]
      end

      def authorized_project_numbers
        @authorized_project_numbers ||= resolve_user_projects
      end
    end
  end
end



