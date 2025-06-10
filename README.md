# SUSHI Bioinformatics System v2025

Rails v8 API + Next.js frontend implementation of the SUSHI bioinformatics system.

## Prerequisites

- Ruby 3.3.7
- Node.js 22.16.0
- Git

## Environment Setup

### 1. Load Required Modules
```bash
module load Dev/Ruby/3.3.7
module load Dev/node/22.16.0
```

### 2. Clone Repository
```bash
git clone <repository-url>
cd new_sushi_2025
```

### 3. Backend Setup
```bash
cd backend

# Configure Bundler for local gem installation
bundle config set --local path 'vendor/bundle'

# Install dependencies
bundle install

# Database setup
rails db:create
rails db:migrate

# Run tests
bundle exec rspec
```

### 4. Frontend Setup
```bash
cd ../frontend

# Install dependencies
npm install

# Run tests
npm test

# Start development server
npm run dev
```

## Production Deployment Setup

### Standard Installation Process
This is the recommended approach for production environments and CI/CD pipelines.

#### Prerequisites
- Full development environment with compilation tools
- All system libraries required for native gem compilation
- Proper SSL certificates and security configurations

#### Backend Production Setup
```bash
cd backend

# Configure Bundler for production
bundle config set --local deployment true
bundle config set --local without development test
bundle config set --local path 'vendor/bundle'

# Install production dependencies
bundle install

# Database setup
RAILS_ENV=production rails db:create
RAILS_ENV=production rails db:migrate

# Precompile assets (if needed)
RAILS_ENV=production rails assets:precompile

# Run production server
RAILS_ENV=production rails server -p 4000
```

#### Frontend Production Setup
```bash
cd frontend

# Install production dependencies
npm ci --only=production

# Build application
npm run build

# Start production server
npm start
```

#### Docker Deployment
```bash
# Build images
docker-compose build

# Deploy
docker-compose up -d

# Health check
docker-compose ps
```

## Development Environment Setup (Limited Compilation Environment)

### For Development Nodes with Limited System Libraries

This approach is suitable for development environments where system compilation libraries are not available or restricted.

#### Initial Setup (One-time on Machine with Full Development Tools)

1. **Prepare Libraries on Compilation-Capable Machine**:
```bash
# Clone repository
git clone <repository-url>
cd new_sushi_2025

# Load required modules
module load Dev/Ruby/3.3.7
module load Dev/node/22.16.0

# Install backend dependencies
cd backend
bundle config set --local path 'vendor/bundle'
bundle install

# Install frontend dependencies
cd ../frontend
npm install

# Return to project root
cd ..

# Create backup directory
mkdir -p ~/sushi_backup/libraries

# Backup compiled libraries
cp -r backend/vendor/bundle ~/sushi_backup/libraries/
cp -r frontend/node_modules ~/sushi_backup/libraries/

# Optional: Create versioned backup
DATE=$(date +%Y%m%d_%H%M%S)
mkdir -p ~/sushi_backup/libraries_$DATE
cp -r backend/vendor/bundle ~/sushi_backup/libraries_$DATE/
cp -r frontend/node_modules ~/sushi_backup/libraries_$DATE/
```

2. **Transfer Library Backup to Development Node**:
```bash
# Transfer backup directory to development node
scp -r ~/sushi_backup/libraries username@dev-node:~/sushi_backup/

# Or use rsync for large directories
rsync -av ~/sushi_backup/libraries/ username@dev-node:~/sushi_backup/libraries/
```

#### Development Environment Setup (Subsequent Clones)

1. **Clone and Setup Project**:
```bash
# Load required modules
module load Dev/Ruby/3.3.7
module load Dev/node/22.16.0

# Clone repository
git clone <repository-url>
cd new_sushi_2025
```

2. **Restore Compiled Libraries**:
```bash
# Restore backend libraries
cp -r ~/sushi_backup/libraries/bundle backend/vendor/

# Restore frontend libraries
cp -r ~/sushi_backup/libraries/node_modules frontend/

# Verify restoration
ls -la backend/vendor/bundle
ls -la frontend/node_modules
```

3. **Configure Bundler**:
```bash
cd backend
bundle config set --local path 'vendor/bundle'
```

4. **Database Setup**:
```bash
# Setup database
rails db:create
rails db:migrate

# Run tests to verify setup
bundle exec rspec
```

5. **Frontend Verification**:
```bash
cd ../frontend

# Run tests to verify setup
npm test

# Start development server
npm run dev
```

#### Updating Libraries (Development Environment)

When new dependencies are added:

1. **Add dependencies on compilation-capable machine**:
```bash
# Update Gemfile or package.json
# Run bundle install or npm install
# Update backup
cp -r backend/vendor/bundle ~/sushi_backup/libraries/
cp -r frontend/node_modules ~/sushi_backup/libraries/
```

2. **Update development environment**:
```bash
# Pull latest code
git pull

# Restore updated libraries
cp -r ~/sushi_backup/libraries/bundle backend/vendor/
cp -r ~/sushi_backup/libraries/node_modules frontend/
```

#### Troubleshooting Development Environment

**Common Issues and Solutions**:

1. **Permission Issues**:
```bash
# Fix permissions
chmod -R 755 backend/vendor/bundle
chmod -R 755 frontend/node_modules
```

2. **Missing Binary Symlinks**:
```bash
# Recreate npm bin links
cd frontend
npm rebuild
```

3. **Bundle Configuration Issues**:
```bash
cd backend
bundle config set --local path 'vendor/bundle'
bundle check
```

## Development Servers

### Backend (Rails API)
```bash
cd backend
rails server -p 4000
```
Access: `http://localhost:4000/api/v1/hello`

### Frontend (Next.js)
```bash
cd frontend
npm run dev
```
Access: `http://localhost:4001`

## Testing

### Backend Tests
```bash
cd backend
bundle exec rspec                    # Run all tests
bundle exec rspec --format doc       # Verbose output
```

### Frontend Tests
```bash
cd frontend
npm test                            # Interactive mode
npm run test:watch                  # Watch mode
npm run test:coverage              # With coverage
npm run test:ci                    # CI mode
```

## Project Structure

```
new_sushi_2025/
├── backend/          # Rails v8 API
│   ├── app/
│   ├── config/
│   ├── spec/         # RSpec tests
│   └── vendor/bundle/ (ignored)
├── frontend/         # Next.js app
│   ├── app/
│   ├── __tests__/
│   └── node_modules/ (ignored)
└── README.md
```

## Environment Variables

Create these files if needed (not committed to repository):

### Backend
```bash
# backend/.env
DATABASE_URL=sqlite3:db/development.sqlite3
RAILS_ENV=development
```

### Frontend
```bash
# frontend/.env.local
NEXT_PUBLIC_API_URL=http://localhost:4000
```

## Deployment

(To be documented when deployment infrastructure is set up)

## Contributing

1. Create feature branch from `main`
2. Make changes with appropriate tests
3. Ensure all tests pass
4. Submit pull request

## Architecture

- **Backend**: Rails v8 API-only mode
- **Frontend**: Next.js 15 with TypeScript
- **Database**: SQLite (development), PostgreSQL (production)
- **Testing**: RSpec (backend), Jest + React Testing Library (frontend)
- **Styling**: Tailwind CSS
