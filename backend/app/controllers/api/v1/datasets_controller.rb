module Api
  module V1
    class DatasetsController < BaseController
          # JWT authentication required (automatically checked by BaseController)
    
    def index
      # Get datasets for the current user
        datasets = current_user.data_sets
        
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
        dataset = current_user.data_sets.find(params[:id])
        
        render json: {
          dataset: {
            id: dataset.id,
            name: dataset.name,
            created_at: dataset.created_at,
            user: current_user.login
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
    end
  end
end 