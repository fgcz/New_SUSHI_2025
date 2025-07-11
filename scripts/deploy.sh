#!/bin/bash

# Deployment script for GitHub Actions
# This script handles deployment to staging and production environments

set -e

# Configuration
ENVIRONMENT=${1:-staging}
DEPLOY_HOST=${DEPLOY_HOST}
DEPLOY_USER=${DEPLOY_USER}
APP_DIR="/opt/sushi-app"
DOCKER_COMPOSE_FILE="docker-compose.prod.yml"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check required environment variables
check_environment() {
    if [ -z "$DEPLOY_HOST" ] || [ -z "$DEPLOY_USER" ]; then
        log_error "DEPLOY_HOST and DEPLOY_USER must be set"
        exit 1
    fi
}

# Create SSH key file
setup_ssh() {
    if [ -n "$DEPLOY_KEY" ]; then
        log_info "Setting up SSH key..."
        mkdir -p ~/.ssh
        echo "$DEPLOY_KEY" > ~/.ssh/id_rsa
        chmod 600 ~/.ssh/id_rsa
        ssh-keyscan -H "$DEPLOY_HOST" >> ~/.ssh/known_hosts
    fi
}

# Deploy to server
deploy() {
    log_info "Deploying to $ENVIRONMENT environment..."
    
    # Create deployment script
    cat > deploy_remote.sh << 'EOF'
#!/bin/bash
set -e

cd /opt/sushi-app

# Pull latest changes
git pull origin main

# Backup current deployment
if [ -f docker-compose.prod.yml ]; then
    docker-compose -f docker-compose.prod.yml down || true
fi

# Build and start new containers
docker-compose -f docker-compose.prod.yml up -d --build

# Wait for services to be healthy
sleep 30

# Check if services are running
if docker-compose -f docker-compose.prod.yml ps | grep -q "Up"; then
    echo "✅ Deployment successful"
else
    echo "❌ Deployment failed"
    exit 1
fi

# Clean up old images
docker image prune -f
EOF

    # Copy deployment script to server
    scp deploy_remote.sh "$DEPLOY_USER@$DEPLOY_HOST:/tmp/"
    
    # Execute deployment on server
    ssh "$DEPLOY_USER@$DEPLOY_HOST" "chmod +x /tmp/deploy_remote.sh && /tmp/deploy_remote.sh"
    
    # Clean up local script
    rm deploy_remote.sh
}

# Health check
health_check() {
    log_info "Performing health check..."
    
    # Wait for services to be ready
    sleep 10
    
    # Check if backend is responding
    if curl -f "http://$DEPLOY_HOST:4050/api/v1/hello" > /dev/null 2>&1; then
        log_info "✅ Backend health check passed"
    else
        log_error "❌ Backend health check failed"
        return 1
    fi
    
    # Check if frontend is responding
    if curl -f "http://$DEPLOY_HOST:4051" > /dev/null 2>&1; then
        log_info "✅ Frontend health check passed"
    else
        log_error "❌ Frontend health check failed"
        return 1
    fi
}

# Rollback function
rollback() {
    log_warn "Rolling back deployment..."
    
    ssh "$DEPLOY_USER@$DEPLOY_HOST" << 'EOF'
        cd /opt/sushi-app
        
        # Stop current containers
        docker-compose -f docker-compose.prod.yml down
        
        # Restart previous version (if available)
        if [ -f docker-compose.prod.yml.backup ]; then
            cp docker-compose.prod.yml.backup docker-compose.prod.yml
            docker-compose -f docker-compose.prod.yml up -d
        fi
EOF
}

# Main execution
main() {
    log_info "Starting deployment process..."
    
    check_environment
    setup_ssh
    
    # Deploy with error handling
    if deploy; then
        log_info "Deployment completed successfully"
        
        if health_check; then
            log_info "✅ All health checks passed"
        else
            log_error "❌ Health checks failed"
            rollback
            exit 1
        fi
    else
        log_error "❌ Deployment failed"
        rollback
        exit 1
    fi
}

# Execute main function
main "$@" 