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
        number = resolve_project_number
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
        number = resolve_project_number
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

      # Returns jobs for a project with pagination and filtering
      def jobs
        project_number = resolve_project_number
        
        unless authorized_project_numbers.include?(project_number)
          return render json: { error: 'Project not accessible' }, status: :forbidden
        end
        
        project = Project.find_by(number: project_number)
        unless project
          return render json: { error: 'Project not found' }, status: :not_found
        end
        
        # Get all dataset IDs for this project
        dataset_ids = project.data_sets.pluck(:id)
        
        # Pagination (computed early so we can include in early returns)
        page = (params[:page] || 1).to_i
        per = [[(params[:per] || 50).to_i, 200].min, 1].max

        if dataset_ids.empty?
          return render json: { 
            jobs: [], 
            total_count: 0, 
            page: page, 
            per: per,
            project_number: project_number 
          }
        end
        
        # Build query with filters
        rel = Job.where(next_dataset_id: dataset_ids)
                 .or(Job.where(input_dataset_id: dataset_ids))
                 .distinct
        
        # Apply filters
        rel = apply_job_filters(rel)
        
        total_count = rel.count
        
        # Optimize query: preload dataset, order by most recent first
        jobs = rel.includes(:data_set)
                  .order(created_at: :desc)
                  .offset((page - 1) * per)
                  .limit(per)
        
        render json: {
          jobs: jobs.map { |job| serialize_job(job) },
          total_count: total_count,
          page: page,
          per: per,
          project_number: project_number,
          filters: active_filters
        }
      end

      private
      
      def resolve_project_number
        (params[:project_number] || params[:project_id] || params[:project_project_number] || params[:id]).to_i
      end

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

      def apply_job_filters(relation)
        # Status filter
        if params[:status].present?
          relation = relation.where(status: params[:status])
        end
        
        # User filter
        if params[:user].present?
          relation = relation.where(user: params[:user])
        end
        
        # Dataset filter
        if params[:dataset_id].present?
          dataset_id = params[:dataset_id].to_i
          relation = relation.where(next_dataset_id: dataset_id)
                             .or(relation.where(input_dataset_id: dataset_id))
        end
        
        # Date range filter (start_time)
        if params[:from_date].present?
          begin
            from_date = Date.parse(params[:from_date])
            relation = relation.where('start_time >= ?', from_date.beginning_of_day)
          rescue ArgumentError
            # Invalid date format, ignore filter
          end
        end
        
        if params[:to_date].present?
          begin
            to_date = Date.parse(params[:to_date])
            relation = relation.where('start_time <= ?', to_date.end_of_day)
          rescue ArgumentError
            # Invalid date format, ignore filter
          end
        end
        
        relation
      end

      def serialize_job(job)
        dataset = job.data_set
        
        {
          id: job.id,
          submit_job_id: job.submit_job_id,
          status: job.status || 'unknown',
          user: job.user || 'unknown',
          dataset: dataset ? {
            id: dataset.id,
            name: dataset.name
          } : nil,
          time: {
            start_time: job.start_time&.iso8601,
            end_time: job.end_time&.iso8601
          },
          created_at: job.created_at.iso8601
          # Note: Intentionally exclude large fields like submit_command, 
          # script_path to reduce response size
        }
      end

      def active_filters
        filters = {}
        filters[:status] = params[:status] if params[:status].present?
        filters[:user] = params[:user] if params[:user].present?
        filters[:dataset_id] = params[:dataset_id].to_i if params[:dataset_id].present?
        filters[:from_date] = params[:from_date] if params[:from_date].present?
        filters[:to_date] = params[:to_date] if params[:to_date].present?
        filters
      end
    end
  end
end



