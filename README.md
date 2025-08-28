# New SUSHI 2025

Rails v8 API and FastAPI (backend) + Next.js (frontend) implementation of the SUSHI bioinformatics system.

## 1. Prerequisites

- Ruby 3.3.7
- Python 3.12.x
- Node.js 22.16.0
- Git

## 2. Environment Setup

(on fgcz-r-029)

### 1. Load Required Modules
```bash
module load Dev/Ruby/3.3.7
module load Dev/node/22.16.0
```

### 2. Clone Repository
```bash
cd /misc/fgcz01/sushi/
git clone git@github.com:fgcz/new_SUSHI_2025
cd new_sushi_2025
```

### 3. Backend Setup
```bash
cd backend

# Configure Bundler for local gem installation
bundle config set --local path 'vendor/bundle'

# Install gems
bundle install
```

### 4. Frontend Setup
```bash
cd ../frontend

# Install dependencies
npm install
```

## 2. Development Environment Setup (Limited Compilation Environment)

1. **Prepare Libraries on Compilation-Capable Machine**:
```bash
# Clone repository
git clone git@github.com:fgcz/new_SUSHI_2025
cd new_sushi_2025

# Load required modules
module load Dev/Ruby/3.3.7
module load Dev/node/22.16.0

# Install backend dependencies
cd backend
bundle config set --local path 'vendor/bundle'
cp -r /misc/fgcz01/sushi/new_SUSHI_2025/backend/vendor .

# Run tests to verify setup
bundle exec rspec

# Install frontend dependencies
cd ../frontend
cp -r /misc/fgcz01/sushi/new_SUSHI_2025/frontend/node_modules .

# Run tests to verify setup
npm test
```

2. **Database Setup (SQLite3, for development)**:
```bash
cd ../backend/
# Setup database
bundle exec rails db:create
bundle exec rails db:migrate

# Run API server
bundle exec rails s -b fgcz-h-037.fgcz-net.unizh.ch -p 4000
```

3. **Frontend Verification**:
```bash
cd frontend

# Start development server
npm run dev -- --port 4001
```

## 4. Production Deployment Setup

TODO: update

### 1. Prerequisites
- Full development environment with compilation tools
- All system libraries required for native gem compilation
- Proper SSL certificates and security configurations

### 2. Backend Production Setup
```bash
cd backend

# Configure Bundler for production
bundle config set --local path 'vendor/bundle'

# Install production dependencies
bundle install

# Database setup
RAILS_ENV=production bundle exec rails db:create
RAILS_ENV=production bundle exec rails db:migrate

# Precompile assets (if needed)
RAILS_ENV=production bundle exec rails assets:precompile

# Run production server
RAILS_ENV=production bundle exec rails server -p 4000
```

### 3. Frontend Production Setup
```bash
cd frontend

# Install production dependencies
npm ci --only=production

# Build application
npm run build

# Start production server
npm start
```

### 4. Docker Deployment
```bash
# Build images
docker-compose build

# Deploy
docker-compose up -d

# Health check
docker-compose ps
```


## 5. Test

### 1. Backend Tests
```bash
cd backend
bundle exec rspec                    # Run all tests
bundle exec rspec --format doc       # Verbose output
```

### 2. Frontend Tests
```bash
cd frontend
npm test                            # Interactive mode
npm run test:watch                  # Watch mode
npm run test:coverage              # With coverage
npm run test:ci                    # CI mode
```

## 6. Project Structure

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

## 7. Environment Variables

Create these files if needed (not committed to repository):

### 1. Backend
```bash
# backend/.env
DATABASE_URL=sqlite3:db/development.sqlite3
RAILS_ENV=development
```

### 2. Frontend
```bash
# frontend/.env.local
NEXT_PUBLIC_API_URL=http://localhost:4000
```

## 8. Architecture

- **Backend**: Rails v8 API-only mode, FastAPI (later)
- **Frontend**: Next.js 15 with TypeScript
- **Database**: SQLite (development), PostgreSQL (production)
- **Testing**: RSpec (backend), Jest + React Testing Library (frontend)
- **Styling**: Tailwind CSS
