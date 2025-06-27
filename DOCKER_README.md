# Docker Setup for Sushi Application

This document explains how to run the Sushi application using Docker Compose.

## Prerequisites

- Docker
- Docker Compose

## Quick Start

### Development Environment

1. Clone the repository and navigate to the project root:
   ```bash
   cd new_sushi_2025
   ```

2. Start the development environment:
   ```bash
   # Using default ports (4050, 4051)
   docker-compose up --build
   
   # Or using custom ports
   BACKEND_PORT=3000 FRONTEND_PORT=3001 docker-compose up --build
   
   # Or using the helper script
   ./docker-dev.sh up
   ./docker-dev.sh up 3000 3001  # Custom ports
   ```

3. Access the applications:
   - Frontend: http://localhost:4051 (default) or http://localhost:3001 (custom)
   - Backend API: http://localhost:4050 (default) or http://localhost:3000 (custom)
   - Database: SQLite3 (file-based, no external service needed)

### Production Environment

1. Set up environment variables:
   ```bash
   cp env.example .env
   # Edit .env with your production values
   ```

2. Start the production environment:
   ```bash
   # Using default ports
   docker-compose -f docker-compose.prod.yml up --build
   
   # Or using custom ports
   BACKEND_PORT=3000 FRONTEND_PORT=3001 docker-compose -f docker-compose.prod.yml up --build
   ```

## Services

### Backend (Rails API)
- **Default Port**: 4050 (dev) / 4050 (prod)
- **Database**: SQLite3 (dev) / MySQL (prod)
- **Environment**: Development/Production

### Frontend (Next.js)
- **Default Port**: 4051
- **Environment**: Development/Production
- **API Proxy**: Routes `/api/*` to backend

### Database (Production Only)
- **Type**: MySQL 8.0
- **Port**: 3306 (internal)
- **Database**: sushi_app_production

## Port Configuration

### Default Ports
- **Backend**: 4050
- **Frontend**: 4051

### Custom Ports
You can override the default ports using environment variables:

```bash
# Set custom ports
export BACKEND_PORT=3000
export FRONTEND_PORT=3001

# Or inline
BACKEND_PORT=3000 FRONTEND_PORT=3001 docker-compose up
```

### Helper Script Usage
```bash
# Default ports
./docker-dev.sh up

# Custom ports
./docker-dev.sh up 3000 3001
./docker-dev.sh restart 8080 8081
```

## Development Workflow

### Running in Development Mode

```bash
# Start all services (default ports)
docker-compose up

# Start with custom ports
BACKEND_PORT=3000 FRONTEND_PORT=3001 docker-compose up

# Start in background
docker-compose up -d

# View logs
docker-compose logs -f

# Stop services
docker-compose down
```

### Database Operations

```bash
# Run migrations
docker-compose exec backend rails db:migrate

# Create database
docker-compose exec backend rails db:create

# Reset database
docker-compose exec backend rails db:reset

# Access SQLite database (development)
docker-compose exec backend sqlite3 storage/development.sqlite3
```

### Rails Console

```bash
# Access Rails console
docker-compose exec backend rails console
```

### Frontend Development

The frontend code is mounted as a volume, so changes are reflected immediately.

### Backend Development

The backend code is mounted as a volume, so changes are reflected immediately. You may need to restart the Rails server for some changes.

## Environment Variables

### Development
- `RAILS_ENV`: Rails environment (default: development)
- `BACKEND_PORT`: Backend port (default: 4050)
- `FRONTEND_PORT`: Frontend port (default: 4051)
- Database: SQLite3 (file-based, no environment variables needed)

### Production
- `RAILS_MASTER_KEY`: Rails master key for production
- `MYSQL_USER`: Database username (default: sushi_user)
- `MYSQL_PASSWORD`: Database password
- `MYSQL_DATABASE`: Database name (default: sushi_app_production)
- `MYSQL_HOST`: Database host (default: db)
- `MYSQL_PORT`: Database port (default: 3306)
- `BACKEND_PORT`: Backend port (default: 4050)
- `FRONTEND_PORT`: Frontend port (default: 4051)

## Database Configuration

### Development
- **Type**: SQLite3
- **Location**: `backend/storage/development.sqlite3`
- **Advantages**: No setup required, fast, file-based

### Production
- **Type**: MySQL 8.0
- **Location**: Docker volume (`mysql_data`)
- **Advantages**: ACID compliance, better for concurrent access

## Troubleshooting

### Common Issues

1. **Port already in use**:
   ```bash
   # Check what's using the port
   lsof -i :4050
   lsof -i :4051
   
   # Use different ports
   BACKEND_PORT=3000 FRONTEND_PORT=3001 docker-compose up
   ```

2. **Database connection issues (production)**:
   ```bash
   # Check if database is running
   docker-compose -f docker-compose.prod.yml ps
   
   # Restart database
   docker-compose -f docker-compose.prod.yml restart db
   ```

3. **Permission issues**:
   ```bash
   # Fix file permissions
   sudo chown -R $USER:$USER .
   ```

4. **Clean rebuild**:
   ```bash
   # Remove all containers and volumes
   docker-compose down -v
   docker system prune -a
   
   # Rebuild from scratch
   docker-compose up --build
   ```

### Logs

```bash
# View all logs
docker-compose logs

# View specific service logs
docker-compose logs backend
docker-compose logs frontend

# Follow logs in real-time
docker-compose logs -f
```

## File Structure

```
.
├── docker-compose.yml          # Development environment (SQLite3)
├── docker-compose.prod.yml     # Production environment (MySQL)
├── env.example                 # Environment variables template
├── docker-dev.sh               # Development helper script
├── backend/
│   ├── Dockerfile              # Production backend image
│   ├── Dockerfile.dev          # Development backend image
│   └── entrypoint.sh           # Backend entrypoint script
└── frontend/
    ├── Dockerfile              # Production frontend image
    └── Dockerfile.dev          # Development frontend image
```

## Notes

- **Development**: Uses SQLite3 for simplicity and speed
- **Production**: Uses MySQL for reliability and scalability
- **Default Ports**: Backend 4050, Frontend 4051
- **Custom Ports**: Can be set via environment variables
- The development environment uses volume mounts for hot reloading
- The production environment uses multi-stage builds for optimized images
- Database data is persisted using Docker volumes (production only)
- The frontend proxies API requests to the backend automatically 
