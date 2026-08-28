# Be sure to restart your server when you modify this file.

# Avoid CORS issues when API is called from the frontend app.
# Handle Cross-Origin Resource Sharing (CORS) in order to accept cross-origin AJAX requests.

# Read more: https://github.com/cyu/rack-cors

Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    # Allow all origins for development stage
    # origins 'http://fgcz-h-037.fgcz-net.unizh.ch:4001', 'http://localhost:4001', 'http://127.0.0.1:4001'
    origins '*'

    resource '*',
      headers: :any,
      methods: [:get, :post, :put, :patch, :delete, :options, :head],
      # Content-Disposition is not a CORS-safelisted response header, so without
      # this the TSV downloads reach the browser with the client's fallback name
      # instead of the one the server chose.
      expose: ['Content-Disposition'],
      credentials: false  # Set credentials to false
  end
end
