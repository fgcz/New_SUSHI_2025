# CI/CD Pipeline Setup

## Overview

This project uses GitHub Actions to build an integrated CI/CD pipeline for the backend (Rails) and frontend (Next.js) applications.

## Pipeline Architecture

### 1. Backend Tests (Rails)
- Test execution in Ruby 3.2.3 environment
- SQLite database for testing
- RSpec test execution
- Code coverage measurement with SimpleCov

### 2. Frontend Tests (Next.js)
- Test execution in Node.js 22.16.0 environment
- Jest + React Testing Library for testing
- Production build verification
- Coverage report generation

### 3. Integration Tests
- API server startup verification
- Backend-frontend connectivity testing
- Endpoint functionality verification

### 4. Code Quality & Linting
- Backend code quality checks with Rubocop
- Frontend code quality checks with ESLint

### 5. Deploy
- Automatic deployment after all tests pass
- Executes only on push to main branch

## Environment Variables Setup

### GitHub Secrets (Configure as needed)

```
# Production environment variables
RAILS_MASTER_KEY=<your-rails-master-key>
DATABASE_URL=<production-database-url>

# Deployment configuration
DEPLOY_HOST=<your-deployment-host>
DEPLOY_USER=<your-deployment-user>
DEPLOY_KEY=<your-ssh-private-key>
```

### Local Development Environment

```bash
# backend/.env.development
RAILS_ENV=development

# backend/.env.test
RAILS_ENV=test

# frontend/.env.local
NEXT_PUBLIC_API_URL=http://localhost:4000
```

## Workflow Triggers

- **Push**: Push to `main`, `develop` branches
- **Pull Request**: PR to `main` branch

## Execution Instructions

### 1. Local Test Execution

```bash
# Backend tests
cd backend
bundle exec rspec

# Frontend tests
cd frontend
npm test
```

### 2. Manual Integration Testing

```bash
# Start backend server (Terminal 1)
cd backend
bundle exec rails server -p 4000

# Start frontend server (Terminal 2)
cd frontend
npm run dev

# Test API connectivity
curl http://localhost:4000/api/v1/hello
```

## Deployment Configuration

### Current Status
- Deployment job is configured but actual deployment scripts are not implemented
- Currently executes basic verification as placeholder

### Future Enhancement Plans
- Dockerization
- AWS/Heroku deployment configuration
- Environment-specific deployments (staging/production)
- Migration from SQLite to MySQL

## Database Migration Plan

### Current Setup
- Using SQLite for development and testing
- Lightweight and suitable for early development stages
- No external database dependencies

### Planned Migration to MySQL
- Will migrate to MySQL in early development stages
- CI/CD pipeline will be updated to include MySQL service
- Database migration scripts will be added
- Environment-specific database configurations

## Troubleshooting

### Common Issues

1. **Bundler cache errors**
   ```
   Solution: Ensure Gemfile.lock is up to date
   ```

2. **Node.js cache errors**
   ```
   Solution: Ensure package-lock.json is up to date
   ```

3. **Integration test failures**
   ```
   Solution: Adjust API server startup time (increase sleep value)
   ```

4. **Database connection issues**
   ```
   Solution: Verify database configuration and permissions
   ```

## Configuration Files

- `.github/workflows/ci-cd.yml`: Main workflow configuration
- `backend/.rspec`: RSpec configuration
- `frontend/jest.config.js`: Jest configuration
- `backend/config/database.yml`: Database configuration (SQLite)

## Next Steps

1. Monitor CI/CD pipeline performance
2. Add more comprehensive test coverage
3. Implement actual deployment scripts
4. Plan MySQL migration timeline
5. Add environment-specific configurations 