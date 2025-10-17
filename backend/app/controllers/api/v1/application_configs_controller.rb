module Api
  module V1
    class ApplicationConfigsController < ApplicationController
      # JWT authentication is handled by ApplicationController via JwtAuthenticatable concern

      # GET /api/v1/application-configs
      # List all available applications
      def index
        apps = ApplicationConfigParser.list_apps
        
        render json: {
          applications: apps.map { |app_name| { name: app_name } },
          total_count: apps.size
        }
      end

      # GET /api/v1/application-configs/:app_name
      # Get configuration for a specific application
      def show
        app_name = params[:app_name] || params[:id]
        
        config = ApplicationConfigParser.parse(app_name)
        
        if config
          render json: {
            application: format_config(config)
          }
        else
          render json: { 
            error: 'Application not found',
            app_name: app_name
          }, status: :not_found
        end
      rescue StandardError => e
        Rails.logger.error("Error in ApplicationConfigsController#show: #{e.message}")
        Rails.logger.error(e.backtrace.join("\n"))
        
        render json: { 
          error: 'Internal server error',
          message: e.message
        }, status: :internal_server_error
      end

      private

      def format_config(config)
        {
          name: config[:name],
          class_name: config[:class_name],
          category: config[:analysis_category],
          description: config[:description],
          required_columns: config[:required_columns],
          required_params: config[:required_params],
          form_fields: config[:form_fields],
          modules: config[:modules],
          inherit_tags: config[:inherit_tags],
          inherit_columns: config[:inherit_columns]
        }
      end
    end
  end
end

