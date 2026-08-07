require 'json'

# Machine-to-machine "internal bridge" for the legacy SUSHI schema. Ported from
# Ronald's FastAPI /internal/legacy/* surface (backend_python) so background
# services reach New SUSHI by base-URL swap instead of a direct DB connection:
#
#   job_manager  → poll jobs by status, resolve SLURM dependencies, patch job rows
#   GeoUploader  → list a project's datasets, resolve bfabric-id/parent/project,
#                  read parsed sample rows
#
# Security posture (differs from Ronald, deliberately):
#   Ronald mounts /internal behind get_machine_caller, which is a NO-OP stub
#   ("service=anonymous") — i.e. unauthenticated. Per the priority-1b directive
#   (no unauthenticated DB access), this surface is bearer-only and fail-closed
#   via a MACHINE-principal ApiToken. static (project-scoped registration) and
#   user tokens are rejected (403): a project-scoped /v1 token must NOT gain
#   system-wide internal-bridge authority, and these callers are infrastructure
#   daemons, not people.
#
#   No per-project scoping is applied here: job_manager polls jobs system-wide
#   and GeoUploader reads across projects, so any valid machine token authorizes
#   the whole surface (one trusted infra credential, principal 'machine'). This
#   is the validation-oracle re-implementation of the contract Ronald leads on;
#   it does not couple to the legacy MariaDB (works against the app DB).
module Internal
  class LegacyController < ActionController::Base
    # Bearer-only, session-less → skip CSRF entirely. `with: :null_session` would
    # still invoke the unverified-request handler (Devise → request.flash=) and
    # 500 when forgery protection is enabled (dev/prod); tests default it OFF.
    skip_forgery_protection

    class InvalidField < StandardError; end

    rescue_from JSON::ParserError do
      render json: { error: 'malformed JSON body' }, status: :bad_request
    end
    rescue_from InvalidField do |e|
      render json: { error: e.message }, status: :unprocessable_entity
    end

    before_action :require_machine_token

    # Fields job_manager may write on a state transition. Mirrors Ronald's
    # PatchJobRequest exactly; anything else in the body is ignored.
    PATCHABLE_JOB_FIELDS = %w[
      status submit_job_id submit_command stdout_path stderr_path start_time end_time
    ].freeze

    # GET /internal/legacy/jobs?status=CREATED,WAITING_FOR_DEPENDENCY
    # Parity port of the deployed daemon's own poll query
    # (masa_job_manager/src/db_manager.py:69-71, scheduler.py:81-85).
    # NOT called by the deployed job_manager: it reaches the same rows over
    # direct MySQL, because New SUSHI and the daemon share one `sushi` DB.
    # Kept so an HTTP-based daemon can be pointed here by base-URL swap.
    def jobs
      statuses = params[:status].to_s.split(',').map(&:strip).reject(&:empty?)
      if statuses.empty?
        render json: { error: 'status query parameter is required' }, status: :unprocessable_entity
        return
      end
      rows = Job.where(status: statuses).order(:id)
      render json: rows.map { |j| job_json(j) }, status: :ok
    end

    # GET /internal/legacy/datasets/:dataset_id/jobs
    # Jobs that produce a given dataset (next_dataset_id = dataset_id). Empty
    # list if none.
    #
    # Parity port of the query the deployed job_manager uses to build the SLURM
    # --dependency chain (masa_job_manager/src/db_manager.py:76, called from
    # scheduler.py:50) — but the daemon runs that SQL directly and has NO HTTP
    # caller for this route (verified 2026-08-07: `grep -rn internal/legacy` over
    # the daemon source returns nothing, and a live chained submit produced zero
    # requests here). What actually orders New SUSHI jobs is that the daemon
    # reads OUR jobs.input_dataset_id / next_dataset_id out of the shared DB;
    # see spec/services/job_submission_service_spec.rb for the guard on those
    # two columns. Do not describe this endpoint as the live mechanism.
    def dataset_jobs
      rows = Job.where(next_dataset_id: params[:dataset_id]).order(:id)
      render json: rows.map { |j| parent_job_json(j) }, status: :ok
    end

    # PATCH /internal/legacy/jobs/:id
    # Partial update. Only keys PRESENT in the JSON body are written; a present
    # key with an explicit null clears the column; an absent key is left as-is
    # (mirrors Ronald's model_dump(exclude_unset=True)).
    def patch_job
      job = Job.find_by(id: params[:id])
      unless job
        render json: { error: "job #{params[:id]} not found" }, status: :not_found
        return
      end

      attrs = {}
      PATCHABLE_JOB_FIELDS.each do |field|
        next unless json_body.key?(field)
        attrs[field] = coerce_job_field(field, json_body[field])
      end

      job.update!(attrs) unless attrs.empty?
      render json: job_json(job.reload), status: :ok
    end

    # GET /internal/legacy/projects/:project_number/datasets
    # All datasets for a project (GeoUploader jsTree selector). Empty list if the
    # project does not exist.
    def project_datasets
      project = Project.find_by(number: params[:project_number])
      rows = project ? DataSet.where(project_id: project.id).order(:id) : DataSet.none
      render json: rows.map { |d| { id: d.id, name: d.name, parent_id: d.parent_id } }, status: :ok
    end

    # GET /internal/legacy/datasets/by-bfabric/:bfabric_id
    # SUSHI dataset id for a B-Fabric dataset id (GeoUploader login redirect).
    def dataset_by_bfabric
      data_set = DataSet.find_by(bfabric_id: params[:bfabric_id])
      unless data_set
        render json: { error: "dataset for bfabric_id #{params[:bfabric_id]} not found" }, status: :not_found
        return
      end
      render json: { dataset_id: data_set.id }, status: :ok
    end

    # GET /internal/legacy/datasets/:dataset_id/parent
    # parent_id is null for a root dataset; 404 only if the dataset is absent.
    def dataset_parent
      data_set = DataSet.find_by(id: params[:dataset_id])
      unless data_set
        render json: { error: "dataset #{params[:dataset_id]} not found" }, status: :not_found
        return
      end
      render json: { parent_id: data_set.parent_id }, status: :ok
    end

    # GET /internal/legacy/datasets/:dataset_id/project
    # Owning project number. 404 if the dataset is absent or has no project
    # (matches Ronald's inner join semantics).
    def dataset_project
      data_set = DataSet.find_by(id: params[:dataset_id])
      project = data_set&.project
      unless project
        render json: { error: "dataset #{params[:dataset_id]} not found" }, status: :not_found
        return
      end
      render json: { project_number: project.number }, status: :ok
    end

    # POST /internal/legacy/datasets/:dataset_id/update-completed-samples
    # job_manager calls this on a job's COMPLETED transition to refresh how many
    # samples have all their gStore files present (drives the UI progress count).
    # Legacy exposed it as GET /data_set/:id/update_completed_samples (GET with a
    # side effect); re-homed here as POST since it mutates. 404 if dataset absent.
    def update_completed_samples
      data_set = DataSet.find_by(id: params[:dataset_id])
      unless data_set
        render json: { error: "dataset #{params[:dataset_id]} not found" }, status: :not_found
        return
      end
      completed = data_set.recount_completed_samples
      render json: { completed_samples: completed, num_samples: data_set.samples_length }, status: :ok
    end

    # GET /internal/legacy/datasets/:dataset_id/samples
    # Parsed sample rows (Ruby Hash#inspect key_value → plain hashes). Empty list
    # if the dataset has no samples (matches Ronald: queries samples, not dataset).
    def dataset_samples
      rows = Sample.where(data_set_id: params[:dataset_id]).order(:id)
      render json: rows.map(&:to_hash), status: :ok
    end

    private

    def require_machine_token
      @api_token = ApiToken.authenticate(bearer_token)
      unless @api_token
        render json: { error: 'unauthorized' }, status: :unauthorized
        return
      end
      return if @api_token.machine?

      render json: { error: 'internal bridge requires a machine token' }, status: :forbidden
    end

    def bearer_token
      header = request.headers['Authorization'].to_s
      header[/\ABearer\s+(.+)\z/i, 1]
    end

    def coerce_job_field(field, value)
      case field
      when 'submit_job_id'
        value.nil? ? nil : value.to_i
      when 'start_time', 'end_time'
        return nil if value.nil?
        parsed = begin
          Time.zone.parse(value.to_s)
        rescue ArgumentError
          nil
        end
        raise InvalidField, "#{field} is not a valid timestamp" if parsed.nil?
        parsed
      else
        value
      end
    end

    def job_json(job)
      {
        id: job.id,
        submit_job_id: job.submit_job_id,
        input_dataset_id: job.input_dataset_id,
        next_dataset_id: job.next_dataset_id,
        script_path: job.script_path,
        stdout_path: job.stdout_path,
        stderr_path: job.stderr_path,
        submit_command: job.submit_command,
        status: job.status,
        user: job.user,
        start_time: job.start_time&.iso8601,
        end_time: job.end_time&.iso8601
      }
    end

    def parent_job_json(job)
      { id: job.id, submit_job_id: job.submit_job_id, status: job.status }
    end

    # Parse the JSON body. A malformed body raises JSON::ParserError, mapped to a
    # 400 by rescue_from (rather than being silently treated as {}), so a client
    # bug surfaces instead of a no-op success.
    def json_body
      @json_body ||= begin
        raw = request.body.read
        raw.to_s.empty? ? {} : JSON.parse(raw)
      end
    end
  end
end
