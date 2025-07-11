# GitHub Actions CI/CD Setup Guide

## Overview

This project consists of a Rails 8 API server and Next.js frontend, with automated CI/CD pipeline using GitHub Actions.

## Workflow Configuration

### Jobs to be executed

1. **Backend Tests (Rails)**
   - RSpec test execution
   - Test coverage generation
   - Testing with SQLite database

2. **Frontend Tests (Next.js)**
   - Jest test execution
   - Next.js application build
   - Test coverage generation

3. **Docker Build Test**
   - Backend and frontend Docker image builds
   - docker-compose.yml configuration validation

4. **Integration Tests**
   - Backend server startup
   - API connectivity testing
   - Frontend and backend integration testing

5. **Security Scan**
   - Security scanning using Brakeman
   - Vulnerability report generation

6. **Code Quality & Linting**
   - Ruby code quality checks with RuboCop
   - JavaScript/TypeScript code quality checks with ESLint

7. **Deploy to Staging** (develop branch)
   - Deployment to staging environment

8. **Deploy to Production** (main branch)
   - Deployment to production environment

## Setup Instructions

### 1. GitHub Secrets Configuration

Set up the following secrets in your repository's Settings > Secrets and variables > Actions:

#### Required secrets
```
DATABASE_URL=your_database_url
RAILS_MASTER_KEY=your_rails_master_key
```

#### Optional secrets (for deployment)
```
DEPLOY_HOST=your_deployment_host
DEPLOY_USER=your_deployment_user
DEPLOY_KEY=your_private_ssh_key
DOCKER_REGISTRY=your_docker_registry
DOCKER_USERNAME=your_docker_username
DOCKER_PASSWORD=your_docker_password
```

### 2. Environment Configuration

Configure the following in your GitHub repository's Settings > Environments:

#### Staging environment
- Environment name: `staging`
- Protection rules: Configure as needed

#### Production environment
- Environment name: `production`
- Protection rules: Recommended (Required reviewers, etc.)

### 3. Branch Protection Rules

It is recommended to set the following protection rules for the main branch:

- Require a pull request before merging
- Require status checks to pass before merging
- Require branches to be up to date before merging
- Include administrators

## Workflow Execution

### Automatic execution
- Push to `main` branch → Production deployment
- Push to `develop` branch → Staging deployment
- Pull request → Tests and linting only

### Manual execution
You can manually run workflows from the GitHub Actions page.

## Troubleshooting

### Common issues

1. **Tests failing**
   - Check database configuration
   - Verify dependency installation
   - Check logs for detailed error information

2. **Docker build failing**
   - Verify Dockerfile syntax
   - Check dependency versions
   - Verify build context

3. **Deployment failing**
   - Check GitHub Secrets configuration
   - Verify deployment server settings
   - Check SSH key configuration

### How to check logs

1. Select the workflow on the GitHub Actions page
2. Click on the failed job
3. Check the logs of the failed step

## Customization

### Adding new tests

1. Backend tests: Add test files to `backend/spec/`
2. Frontend tests: Add test files to `frontend/__tests__/`

### Adding deployment scripts

Add actual deployment scripts to the deploy step in `.github/workflows/ci-cd.yml`.

Example:
```yaml
- name: Deploy to Production
  run: |
    # SSH to server and deploy
    ssh ${{ secrets.DEPLOY_USER }}@${{ secrets.DEPLOY_HOST }} << 'EOF'
      cd /path/to/your/app
      git pull origin main
      docker-compose -f docker-compose.prod.yml up -d
    EOF
```

## Performance Optimization

### Cache utilization
- Ruby gems cache
- Node.js modules cache
- Docker layer cache

### Parallel execution
- Test jobs can run in parallel
- Deployment runs after dependent jobs complete

## Security

### Security scanning
- Vulnerability scanning of Rails applications with Brakeman
- Regular dependency updates
- Automatic security report generation

### Access control
- Protection of sensitive information with GitHub Secrets
- Environment-specific access control
- Enforcement of review process

## Monitoring and Alerts

### Notification settings
- Notifications on workflow failures
- Notifications on successful deployments
- Notifications on security scan results

### Metrics
- Test execution time
- Deployment success rate
- Code coverage rate 