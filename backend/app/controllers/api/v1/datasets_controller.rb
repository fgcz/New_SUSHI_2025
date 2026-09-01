module Api
  module V1
    class DatasetsController < BaseController
          # JWT authentication required (automatically checked by BaseController)
    
    def index
      # Token requests are scoped to the token's projects; otherwise the existing
      # behavior (all when auth skipped, else the user's owned datasets).
        datasets = if token_authenticated?
                     DataSet.joins(:project).where(projects: { number: api_token_project_numbers })
                   elsif AuthenticationHelper.authentication_skipped?
                     DataSet.all
                   else
                     # Project membership, not ownership — same correction as
                     # authorized_dataset below. 4,056 rows for a 77-project account
                     # against 1,348 owned, measured on production; this action has no
                     # caller in the UI, which lists per project and paginates.
                     DataSet.joins(:project)
                            .where(projects: { number: authorized_project_numbers })
                   end
        
        render json: {
          datasets: datasets.map do |dataset|
            {
              id: dataset.id,
              name: dataset.name,
              created_at: dataset.created_at,
              user_login: (current_user&.login || 'anonymous')
            }
          end,
          total_count: datasets.count,
          current_user: (current_user&.login || 'anonymous')
        }
      end
      
      def show
        dataset = authorized_dataset(params[:id]) or return

        # Build detailed payload similar to legacy SUSHI data_set/show
        render json: {
          id: dataset.id,
          name: dataset.name,
          created_at: dataset.created_at,
          user_login: (current_user&.login || 'anonymous'),
          project_number: dataset.project&.number,
          samples_count: dataset.samples_length,
          completed_samples: dataset.completed_samples,
          parent_id: dataset.parent_id,
          children_ids: dataset.data_sets.pluck(:id),
          bfabric_id: dataset.bfabric_id,
          order_id: dataset.order_id,
          comment: dataset.comment,
          sushi_app_name: dataset.sushi_app_name,
          headers: dataset.factor_first_headers,
          samples: serialize_samples(dataset),
          applications: runnable_applications(dataset)
        }
      rescue ActiveRecord::RecordNotFound
        render json: { error: 'Dataset not found' }, status: :not_found
      end
      
      # PATCH /api/v1/datasets/:id
      # Legacy writes exactly these two from its show page (data_set_controller
      # #add_comment and #edit_name); nothing else about a dataset is editable.
      def update
        dataset = scoped_dataset or return

        if dataset.update(dataset_update_params)
          render json: { id: dataset.id, name: dataset.name, comment: dataset.comment }
        else
          render json: { errors: dataset.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # GET /api/v1/datasets/:id/paths
      # The project-relative gStore directories this dataset's files live in,
      # which is what the UI turns into a browse link (DataSet#paths).
      def paths
        dataset = scoped_dataset or return

        render json: { dataset_id: dataset.id, paths: dataset.paths }
      end

      # GET /api/v1/datasets/:id/parameters
      # The fully-resolved parameters of the job that produced this dataset.
      def parameters
        dataset = scoped_dataset or return

        render json: { dataset_id: dataset.id, parameters: dataset.job_parameters || {} }
      end

      # GET /api/v1/datasets/:id/resubmit
      # What the run-application form needs to re-run the app that produced this
      # dataset. 'sushi_app' is dropped: it records which app ran, and is not one
      # of the app's own parameters.
      def resubmit
        dataset = scoped_dataset or return

        stored = dataset.job_parameters || {}
        render json: {
          dataset_id: dataset.id,
          app_name: dataset.sushi_app_name,
          parameters: stored.except('sushi_app')
        }
      end

      # GET /api/v1/datasets/:id/tsv
      # The dataset itself as TSV — legacy's DataSet#save_as_tsv content.
      def tsv
        dataset = scoped_dataset or return

        send_data dataset.tsv_string,
                  type: 'text/tab-separated-values',
                  filename: "#{dataset.name}_dataset.tsv",
                  disposition: 'attachment'
      end

      def create
        dataset = current_user.data_sets.build(dataset_params)
        
        if dataset.save
          render json: {
            dataset: {
              id: dataset.id,
              name: dataset.name,
              created_at: dataset.created_at,
              user: current_user.login
            },
            message: 'Dataset created successfully'
          }, status: :created
        else
          render json: { errors: dataset.errors.full_messages }, status: :unprocessable_entity
        end
      end
      
      # POST /api/v1/datasets/from_tsv
      # Register a dataset from TSV file content
      def from_tsv
        tsv_content = params[:tsv_content]
        dataset_name = params[:dataset_name] || params[:name]
        project_number = params[:project_number] || params[:project]
        parent_id = params[:parent_id]
        comment = params[:comment]
        
        unless tsv_content.present?
          return render json: { errors: ['TSV content is required'] }, status: :unprocessable_entity
        end
        
        unless dataset_name.present?
          return render json: { errors: ['Dataset name is required'] }, status: :unprocessable_entity
        end
        
        unless project_number.present?
          return render json: { errors: ['Project number is required'] }, status: :unprocessable_entity
        end
        
        begin
          # Parse TSV content
          require 'csv'
          csv_data = CSV.parse(tsv_content, col_sep: "\t", headers: true)
          
          headers = csv_data.headers
          rows = csv_data.map(&:fields)
          
          # Prepare data_set_arr for save_dataset_to_database
          data_set_arr = [
            'DataSetName', dataset_name,
            'ProjectNumber', project_number.to_s
          ]
          
          data_set_arr << 'ParentID' << parent_id.to_s if parent_id.present?
          data_set_arr << 'Comment' << comment if comment.present?
          
          # Get current user
          user = if AuthenticationHelper.authentication_skipped?
                   User.find_by(login: 'sushi_lover') || User.first
                 else
                   current_user
                 end
          
          # Save dataset to database
          dataset_id = DataSet.save_dataset_to_database(
            data_set_arr: data_set_arr,
            headers: headers,
            rows: rows,
            user: user,
            child: false
          )
          
          dataset = DataSet.find(dataset_id)
          
          render json: {
            dataset: {
              id: dataset.id,
              name: dataset.name,
              created_at: dataset.created_at,
              user: user.login || 'anonymous',
              project_number: dataset.project&.number
            },
            message: 'Dataset created successfully from TSV'
          }, status: :created
        rescue CSV::MalformedCSVError => e
          render json: { errors: ["Invalid TSV format: #{e.message}"] }, status: :unprocessable_entity
        rescue StandardError => e
          Rails.logger.error("Error creating dataset from TSV: #{e.message}\n#{e.backtrace.join("\n")}")
          render json: { errors: ["Failed to create dataset: #{e.message}"] }, status: :internal_server_error
        end
      end
      
      # GET /api/v1/datasets/:id/tree
      # Returns the parent tree to root and all children recursively
      def tree
        # `or return` because the lookup now RENDERS the 404/403 and answers nil,
        # the same contract scoped_dataset has used all along. It used to raise and
        # let the rescue below answer, so without this the action would carry on
        # with nil and turn a refusal into a 500. The rescue stays as a backstop
        # for anything further down that still raises.
        dataset = find_authorized_dataset or return
        tree_nodes = build_dataset_tree(dataset)
        render json: tree_nodes
      rescue ActiveRecord::RecordNotFound
        render json: { error: 'Dataset not found' }, status: :not_found
      end
      
      # GET /api/v1/datasets/:id/runnable_apps
      # Returns runnable applications grouped by category
      def runnable_apps
        # `or return` because the lookup now RENDERS the 404/403 and answers nil,
        # the same contract scoped_dataset has used all along. It used to raise and
        # let the rescue below answer, so without this the action would carry on
        # with nil and turn a refusal into a 500. The rescue stays as a backstop
        # for anything further down that still raises.
        dataset = find_authorized_dataset or return
        apps = runnable_applications_by_category(dataset)
        render json: apps
      rescue ActiveRecord::RecordNotFound
        render json: { error: 'Dataset not found' }, status: :not_found
      end
      
      # GET /api/v1/datasets/:id/samples
      # Returns all samples in the dataset
      def samples
        # `or return` because the lookup now RENDERS the 404/403 and answers nil,
        # the same contract scoped_dataset has used all along. It used to raise and
        # let the rescue below answer, so without this the action would carry on
        # with nil and turn a refusal into a 500. The rescue stays as a backstop
        # for anything further down that still raises.
        dataset = find_authorized_dataset or return
        samples_data = serialize_samples(dataset)
        render json: samples_data
      rescue ActiveRecord::RecordNotFound
        render json: { error: 'Dataset not found' }, status: :not_found
      end
      
      private
      
      def dataset_params
        params.require(:dataset).permit(:name)
      end

      # Convert Sample.key_value (stored as serialized String) into Hash safely
      def serialize_samples(dataset)
        dataset.samples.map do |sample|
          sample.to_hash
        rescue => e
          Rails.logger.warn "Failed to parse sample #{sample.id}: #{e}"
          {}
        end
      end

      # Determine runnable applications grouped by category, based on headers
      # Categories and applications are sorted alphabetically, with 'Misc' at the end
      def runnable_applications(dataset)
        headers = dataset.headers

        applications_by_category = SushiApplication.all
          .select { |app| app.required_columns_satisfied_by?(headers) }
          .group_by(&:analysis_category)

        # Sort by category name alphabetically, with 'Misc' (nil category) at the end
        sorted_categories = applications_by_category.keys.compact.sort
        sorted_categories << nil if applications_by_category.key?(nil)

        sorted_categories.map do |category|
          apps = applications_by_category[category]
          {
            category: category || 'Misc',
            # Sort applications alphabetically by class_name
            apps: apps.sort_by(&:class_name).map do |app|
              {
                class_name: app.class_name,
                description: app.description
              }
            end
          }
        end
      end
      
      def dataset_update_params
        params.require(:dataset).permit(:name, :comment)
      end

      # The dataset named by :id, or nil after rendering the matching error.
      # Same rule as #show: project scope for token callers, ownership otherwise.
      # THE one rule for "may this caller read this dataset". There were three
      # near-copies of it and all three said OWNERSHIP — `current_user.data_sets` —
      # which is not what authorizes anything here. Measured on the production
      # database: dataset 113260 in project 35611 has a NULL `user_id`, masaomi owns
      # 1348 of 83,071 datasets, and 9 of the 19 datasets in his own project 35611
      # are owned by someone else. So a logged-in user got "Dataset not found" for
      # 98% of production, including datasets in projects he is a member of.
      #
      # It stayed hidden because this branch only runs when a login is REQUIRED: with
      # authentication skipped — every node until 082 today — the unscoped
      # `DataSet.find` above it was taken instead.
      #
      # Project membership is the rule, and ProjectAuthorizable already computes it
      # for the project and gStore surfaces; this makes datasets use the same answer.
      def authorized_dataset(id)
        dataset = DataSet.find(id)

        if token_authenticated?
          unless api_token_project_numbers.include?(dataset.project&.number.to_i)
            render json: { error: 'Forbidden' }, status: :forbidden
            return nil
          end
          return dataset
        end

        return dataset if AuthenticationHelper.authentication_skipped?

        # `authorized_project_numbers`, deliberately — it is the resolver the project
        # and gStore surfaces already use, so all three now give one answer. (The
        # other resolver in ProjectAuthorizable, current_user_project_numbers, asks
        # LDAP unconditionally and would refuse everything on a node where LDAP is
        # off but a login is still required.)
        unless authorized_project_numbers.include?(dataset.project&.number.to_i)
          render json: { error: 'Forbidden' }, status: :forbidden
          return nil
        end

        dataset
      rescue ActiveRecord::RecordNotFound
        render json: { error: 'Dataset not found' }, status: :not_found
        nil
      end

      def scoped_dataset
        authorized_dataset(params[:id])
      end

      # Find dataset with authorization check
      def find_authorized_dataset
        authorized_dataset(params[:id])
      end
      
      # Build tree structure containing ancestors, current dataset, and descendants
      def build_dataset_tree(dataset)
        nodes = []
        
        # Collect ancestors (parent to root)
        ancestors = collect_ancestors(dataset)
        ancestors.each do |ancestor|
          nodes << dataset_to_tree_node(ancestor, ancestor.parent_id || "#")
        end
        
        # Add current dataset
        nodes << dataset_to_tree_node(dataset, dataset.parent_id || "#")
        
        # Collect descendants (children recursively)
        collect_descendants(dataset, nodes)
        
        nodes
      end
      
      # Collect all ancestor datasets
      def collect_ancestors(dataset)
        ancestors = []
        current = dataset.data_set # parent
        while current
          ancestors.unshift(current)
          current = current.data_set
        end
        ancestors
      end
      
      # Recursively collect all descendant datasets
      def collect_descendants(dataset, nodes)
        dataset.data_sets.each do |child|
          nodes << dataset_to_tree_node(child, dataset.id)
          collect_descendants(child, nodes)
        end
      end
      
      # Convert dataset to tree node format
      def dataset_to_tree_node(dataset, parent_id)
        node = {
          id: dataset.id,
          name: dataset.name,
          parent: parent_id
        }
        node[:comment] = dataset.comment if dataset.comment.present?
        node
      end
      
      # Get runnable applications by category (simplified format with app names only)
      # Categories and applications are sorted alphabetically
      def runnable_applications_by_category(dataset)
        headers = dataset.headers
        
        applications_by_category = SushiApplication.all
          .select { |app| app.required_columns_satisfied_by?(headers) }
          .group_by(&:analysis_category)
        
        # Sort by category name alphabetically, with 'Misc' at the end
        sorted_categories = applications_by_category.keys.compact.sort
        sorted_categories << nil if applications_by_category.key?(nil) # nil category becomes 'Misc'
        
        sorted_categories.map do |category|
          apps = applications_by_category[category]
          {
            category: category || 'Misc',
            # Sort application names alphabetically
            applications: apps.map { |app| app.class_name.sub(/App$/, '') }.sort
          }
        end
      end
    end
  end
end 
