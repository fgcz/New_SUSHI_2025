module Api
  module V1
    class JobsController < BaseController
      # POST /api/v1/jobs
      # Submit a new job for processing
      def create
        dataset_id = job_params[:dataset_id]
        app_name = job_params[:app_name]
        parameters = job_params[:parameters] || {}
        next_dataset_name = job_params[:next_dataset_name]
        next_dataset_comment = job_params[:next_dataset_comment]

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
        job = Job.find(params[:id])
        
        render json: {
          job: serialize_job(job, include_details: true)
        }
      rescue ActiveRecord::RecordNotFound
        render json: { error: 'Job not found' }, status: :not_found
      end

      # GET /api/v1/jobs
      # List jobs (optionally filtered)
      def index
        jobs = Job.all
        
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

