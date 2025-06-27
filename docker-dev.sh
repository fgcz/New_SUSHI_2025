#!/bin/bash

# Docker development helper script

set -e

# Default ports
DEFAULT_BACKEND_PORT=4050
DEFAULT_FRONTEND_PORT=4051

case "$1" in
  "up")
    echo "Starting development environment..."
    if [ -n "$2" ] && [ -n "$3" ]; then
      echo "Using custom ports: Backend=$2, Frontend=$3"
      BACKEND_PORT=$2 FRONTEND_PORT=$3 docker-compose up --build
    else
      echo "Using default ports: Backend=$DEFAULT_BACKEND_PORT, Frontend=$DEFAULT_FRONTEND_PORT"
      docker-compose up --build
    fi
    ;;
  "down")
    echo "Stopping development environment..."
    docker-compose down
    ;;
  "restart")
    echo "Restarting development environment..."
    docker-compose down
    if [ -n "$2" ] && [ -n "$3" ]; then
      echo "Using custom ports: Backend=$2, Frontend=$3"
      BACKEND_PORT=$2 FRONTEND_PORT=$3 docker-compose up --build
    else
      echo "Using default ports: Backend=$DEFAULT_BACKEND_PORT, Frontend=$DEFAULT_FRONTEND_PORT"
      docker-compose up --build
    fi
    ;;
  "logs")
    echo "Showing logs..."
    docker-compose logs -f
    ;;
  "backend-logs")
    echo "Showing backend logs..."
    docker-compose logs -f backend
    ;;
  "frontend-logs")
    echo "Showing frontend logs..."
    docker-compose logs -f frontend
    ;;
  "console")
    echo "Opening Rails console..."
    docker-compose exec backend rails console
    ;;
  "migrate")
    echo "Running database migrations..."
    docker-compose exec backend rails db:migrate
    ;;
  "reset")
    echo "Resetting database..."
    docker-compose exec backend rails db:reset
    ;;
  "sqlite")
    echo "Opening SQLite console..."
    docker-compose exec backend sqlite3 storage/development.sqlite3
    ;;
  "clean")
    echo "Cleaning up Docker resources..."
    docker-compose down -v
    docker system prune -a -f
    ;;
  "rebuild")
    echo "Rebuilding all containers..."
    docker-compose down
    docker-compose build --no-cache
    if [ -n "$2" ] && [ -n "$3" ]; then
      echo "Using custom ports: Backend=$2, Frontend=$3"
      BACKEND_PORT=$2 FRONTEND_PORT=$3 docker-compose up
    else
      echo "Using default ports: Backend=$DEFAULT_BACKEND_PORT, Frontend=$DEFAULT_FRONTEND_PORT"
      docker-compose up
    fi
    ;;
  *)
    echo "Usage: $0 {up|down|restart|logs|backend-logs|frontend-logs|console|migrate|reset|sqlite|clean|rebuild} [backend_port] [frontend_port]"
    echo ""
    echo "Commands:"
    echo "  up [backend_port] [frontend_port]     - Start development environment"
    echo "  down                                  - Stop development environment"
    echo "  restart [backend_port] [frontend_port] - Restart development environment"
    echo "  logs                                  - Show all logs"
    echo "  backend-logs                          - Show backend logs"
    echo "  frontend-logs                         - Show frontend logs"
    echo "  console                               - Open Rails console"
    echo "  migrate                               - Run database migrations"
    echo "  reset                                 - Reset database"
    echo "  sqlite                                - Open SQLite console"
    echo "  clean                                 - Clean up Docker resources"
    echo "  rebuild [backend_port] [frontend_port] - Rebuild all containers"
    echo ""
    echo "Default ports:"
    echo "  Backend:  $DEFAULT_BACKEND_PORT"
    echo "  Frontend: $DEFAULT_FRONTEND_PORT"
    echo ""
    echo "Examples:"
    echo "  $0 up                    # Use default ports"
    echo "  $0 up 3000 3001          # Use custom ports"
    echo "  $0 restart 8080 8081     # Restart with custom ports"
    exit 1
    ;;
esac 