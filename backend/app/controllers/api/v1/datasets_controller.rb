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
              user: current_user.login
            }
          end,
          total_count: datasets.count,
          current_user: current_user.login
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
            user: current_user.login,
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
    end
  end
end 