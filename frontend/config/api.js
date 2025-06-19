// API configuration
const API_CONFIG = {
  // Development environments
  development: {
    localhost: 'http://localhost:4000',
    fullHostname: 'http://fgcz-h-037.fgcz-net.unizh.ch:4000'
  },
  
  // Production environment (update as needed)
  production: {
    default: 'http://fgcz-h-037.fgcz-net.unizh.ch:4000'
  }
};

// Get current environment
const getEnvironment = () => {
  if (typeof window !== 'undefined') {
    return window.location.hostname === 'localhost' ? 'development' : 'production';
  }
  return 'development';
};

// Get API base URL based on current environment and hostname
export const getApiBaseUrl = () => {
  const env = getEnvironment();
  const config = API_CONFIG[env];
  
  if (env === 'development') {
    // Check if we're accessing via full hostname
    if (typeof window !== 'undefined' && window.location.hostname === 'fgcz-h-037.fgcz-net.unizh.ch') {
      return config.fullHostname;
    }
    return config.localhost;
  }
  
  return config.default;
};

export default API_CONFIG; 