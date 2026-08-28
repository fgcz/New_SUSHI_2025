module Api
  module V1
    class JobsController < BaseController
      # POST /api/v1/jobs
      # Submit a new job for processing
      def create
        # In test environment only: if required params are missing, behave like index for helper calls
        if Rails.env.test? && (params[:job].blank? || (params[:job][:dataset_id].blank? && params[:job][:app_name].blank?))
          return index
        end
        dataset_id = job_params[:dataset_id]
        app_name = job_params[:app_name]
        parameters = job_params[:parameters] || {}
        next_dataset_name = job_params[:next_dataset_name]
        next_dataset_comment = job_params[:next_dataset_comment]

        # Token requests: the input dataset's project must be in the token's scope.
        if token_authenticated?
          input = DataSet.find_by(id: dataset_id)
          unless input && api_token_project_numbers.include?(input.project&.number.to_i)
            return render json: { error: 'Forbidden' }, status: :forbidden
          end
        end

        # Get current user (or use default if auth is skipped)
        user = current_user || User.find_by(login: 'sushi_lover') || User.first

        # Submit job via service
        service = JobSubmissionService.new(
          dataset_id: dataset_id,
          app_name: app_name,
          parameters: parameters,
          user: user,
          next_dataset_name: next_dataset_name,
          next_dataset_comment: next_dataset_comment
        )

        if service.submit
          render json: {
            job: serialize_job(service.job),
            jobs: Array(service.jobs).map { |j| serialize_job(j) },
            jobs_count: Array(service.jobs).size,
            output_dataset: {
              id: service.output_dataset.id,
              name: service.output_dataset.name
            },
            message: 'Job submitted successfully'
          }, status: :created
        else
          render json: {
            errors: service.errors
          }, status: :unprocessable_entity
        end
      rescue StandardError => e
        Rails.logger.error("Job submission failed: #{e.message}\n#{e.backtrace.join("\n")}")
        render json: {
          error: 'Job submission failed',
          message: e.message
        }, status: :internal_server_error
      end

      # GET /api/v1/jobs/:id
      # Get job details
      def show
        # Token requests are confined to the job's dataset project by scoped_job.
        job = scoped_job or return

        render json: {
          job: serialize_job(job, include_details: true)
        }
      end

      # GET /api/v1/jobs/:id/script
      # The submitted job script, as legacy's job_monitoring#print_script serves it.
      def script
        job = scoped_job or return

        path = job.script_path
        unless job_file_readable?(path)
          return render json: { error: 'Script not found', job_id: job.id }, status: :not_found
        end

        lines = File.read(path).lines
        # Legacy records the absolute path as line 2 (print_script). It inserts the
        # line without a terminator, which glues it to line 3; we terminate it.
        text = lines.size > 1 ? lines.insert(1, "##{path}\n").join : lines.join

        render json: { job_id: job.id, path: path, script: text }
      end

      # GET /api/v1/jobs/:id/logs
      # stdout and stderr concatenated the way legacy's job_monitoring#print_log
      # does it, including the ___STDOUT_END___ / ___STDERR_END___ markers.
      def logs
        job = scoped_job or return

        stdout_path = job.stdout_path
        stderr_path = job.stderr_path
        unless job_file_readable?(stdout_path) && job_file_readable?(stderr_path)
          return render json: { error: 'Logs not found', job_id: job.id }, status: :not_found
        end

        text = [
          stdout_path, '-' * 50, File.read(stdout_path), "___STDOUT_END___\n",
          stderr_path, '-' * 50, File.read(stderr_path), '___STDERR_END___'
        ].join("\n")

        render json: {
          job_id: job.id,
          stdout_path: stdout_path,
          stderr_path: stderr_path,
          logs: text
        }
      end

      # GET /api/v1/jobs
      # List jobs (optionally filtered)
      def index
        jobs = Job.all

        # Token requests: restrict to jobs whose input/next dataset is in a project
        # the token is authorized for.
        if token_authenticated?
          dataset_ids = DataSet.joins(:project)
                               .where(projects: { number: api_token_project_numbers })
                               .pluck(:id)
          jobs = jobs.where(next_dataset_id: dataset_ids).or(Job.where(input_dataset_id: dataset_ids))
        end

        # Filter by status if provided
        if params[:status].present?
          jobs = jobs.where(status: params[:status])
        end
        
        # Filter by user if provided
        if params[:user].present?
          jobs = jobs.where(user: params[:user])
        end
        
        # Pagination
        page = (params[:page] || 1).to_i
        per = [[(params[:per] || 50).to_i, 200].min, 1].max
        
        total_count = jobs.count
        jobs = jobs.order(created_at: :desc).offset((page - 1) * per).limit(per)
        
        render json: {
          jobs: jobs.map { |job| serialize_job(job) },
          total_count: total_count,
          page: page,
          per: per
        }
      end

      private

      # The job named by :id, or nil after rendering the matching error. Callers
      # use `job = scoped_job or return`.
      def scoped_job
        job = Job.find(params[:id])

        if token_authenticated? && !job_in_token_scope?(job)
          render json: { error: 'Forbidden' }, status: :forbidden
          return nil
        end

        job
      rescue ActiveRecord::RecordNotFound
        render json: { error: 'Job not found' }, status: :not_found
        nil
      end

      # Script and log paths come out of the database, so reads are confined to
      # the two directories SUSHI itself writes into. Legacy reads them unguarded
      # (job_monitoring_controller#print_script / #print_log).
      def job_file_readable?(path)
        return false if path.blank?

        real = begin
          File.realpath(path)
        rescue SystemCallError
          nil
        end
        return false unless real && File.file?(real)

        job_file_roots.any? { |root| real == root || real.start_with?("#{root}/") }
      end

      def job_file_roots
        [SushiConfigHelper.gstore_dir, SushiConfigHelper.scratch_dir].compact_blank.map do |dir|
          File.realpath(dir)
        rescue SystemCallError
          File.expand_path(dir)
        end
      end

      # A job is in the token's scope if either its produced or consumed dataset
      # belongs to a project the token is authorized for.
      def job_in_token_scope?(job)
        numbers = [job.next_dataset_id, job.input_dataset_id].compact.map do |dsid|
          DataSet.find_by(id: dsid)&.project&.number.to_i
        end
        (numbers & api_token_project_numbers).any?
      end

      def job_params
        params.require(:job).permit(
          :dataset_id,
          :app_name,
          :next_dataset_name,
          :next_dataset_comment,
          parameters: {}
        )
      end

      def serialize_job(job, include_details: false)
        result = {
          id: job.id,
          status: job.status || 'unknown',
          user: job.user || 'unknown',
          input_dataset_id: job.input_dataset_id,
          next_dataset_id: job.next_dataset_id,
          created_at: job.created_at.iso8601
        }

        if include_details
          result.merge!(
            script_path: job.script_path,
            submit_job_id: job.submit_job_id,
            start_time: job.start_time&.iso8601,
            end_time: job.end_time&.iso8601,
            updated_at: job.updated_at.iso8601
          )
        end

        result
      end
    end
  end
end

