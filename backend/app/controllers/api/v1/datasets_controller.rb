module Api
  module V1
    class DatasetsController < BaseController
          # JWT authentication required (automatically checked by BaseController)
    
    def index
      # When authentication is skipped, return all datasets; otherwise, only user's datasets
        datasets = if AuthenticationHelper.authentication_skipped?
                     DataSet.all
                   else
                     current_user.data_sets
                   end
        
        render json: {
          datasets: datasets.map do |dataset|
            {
              id: dataset.id,
              name: dataset.name,
              created_at: dataset.created_at,
              user: (current_user&.login || 'anonymous')
            }
          end,
          total_count: datasets.count,
          current_user: (current_user&.login || 'anonymous')
        }
      end
      
      def show
        dataset = if AuthenticationHelper.authentication_skipped?
                    DataSet.find(params[:id])
                  else
                    current_user.data_sets.find(params[:id])
                  end

        # Build detailed payload similar to legacy SUSHI data_set/show
        render json: {
          dataset: {
            id: dataset.id,
            name: dataset.name,
            created_at: dataset.created_at,
            user: (current_user&.login || 'anonymous'),
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
        }
      rescue ActiveRecord::RecordNotFound
        render json: { error: 'Dataset not found' }, status: :not_found
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
        dataset = find_authorized_dataset
        tree_nodes = build_dataset_tree(dataset)
        render json: tree_nodes
      rescue ActiveRecord::RecordNotFound
        render json: { error: 'Dataset not found' }, status: :not_found
      end
      
      # GET /api/v1/datasets/:id/runnable_apps
      # Returns runnable applications grouped by category
      def runnable_apps
        dataset = find_authorized_dataset
        apps = runnable_applications_by_category(dataset)
        render json: apps
      rescue ActiveRecord::RecordNotFound
        render json: { error: 'Dataset not found' }, status: :not_found
      end
      
      # GET /api/v1/datasets/:id/samples
      # Returns all samples in the dataset
      def samples
        dataset = find_authorized_dataset
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
      def runnable_applications(dataset)
        headers = dataset.headers

        applications_by_category = SushiApplication.all
          .select { |app| app.required_columns_satisfied_by?(headers) }
          .group_by(&:analysis_category)

        applications_by_category.map do |category, apps|
          {
            category: category || 'Misc',
            apps: apps.map do |app|
              {
                class_name: app.class_name,
                description: app.description
              }
            end
          }
        end
      end
      
      # Find dataset with authorization check
      def find_authorized_dataset
        if AuthenticationHelper.authentication_skipped?
          DataSet.find(params[:id])
        else
          current_user.data_sets.find(params[:id])
        end
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
      def runnable_applications_by_category(dataset)
        headers = dataset.headers
        
        applications_by_category = SushiApplication.all
          .select { |app| app.required_columns_satisfied_by?(headers) }
          .group_by(&:analysis_category)
        
        applications_by_category.map do |category, apps|
          {
            category: category || 'Misc',
            applications: apps.map(&:class_name)
          }
        end
      end
    end
  end
end 