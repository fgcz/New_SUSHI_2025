#!/bin/bash

# Docker development helper script

set -e

# Default ports
DEFAULT_BACKEND_PORT=4050
DEFAULT_FRONTEND_PORT=4051

# Resolve DEV_HOST if not provided (used by frontend to reach backend from browser)
DEV_HOST="${DEV_HOST:-$(hostname -f)}"
export DEV_HOST
# Default ENABLE_LDAP to 0 unless explicitly set by env or args
ENABLE_LDAP="${ENABLE_LDAP:-0}"

case "$1" in
  "up")
    echo "Starting development environment..."
    # Flexible argument parsing: ENABLE_LDAP flag, optional ports, optional --build in any order
    shift  # drop 'up'
    BUILD_FLAG=""
    REQ_BACKEND_PORT=""
    REQ_FRONTEND_PORT=""
    while [ $# -gt 0 ]; do
      case "$1" in
        ENABLE_LDAP)
          ENABLE_LDAP=1
          ;;
        --build)
          BUILD_FLAG="--build"
          ;;
        ''|*[!0-9]*)
          echo "Ignoring unknown argument: $1" 1>&2
          ;;
        *)
          if [ -z "$REQ_BACKEND_PORT" ]; then
            REQ_BACKEND_PORT="$1"
          elif [ -z "$REQ_FRONTEND_PORT" ]; then
            REQ_FRONTEND_PORT="$1"
          else
            echo "Ignoring extra port argument: $1" 1>&2
          fi
          ;;
      esac
      shift
    done

    EFFECTIVE_BACKEND_PORT="${REQ_BACKEND_PORT:-$DEFAULT_BACKEND_PORT}"
    EFFECTIVE_FRONTEND_PORT="${REQ_FRONTEND_PORT:-$DEFAULT_FRONTEND_PORT}"

    if [ -n "$REQ_BACKEND_PORT" ] || [ -n "$REQ_FRONTEND_PORT" ]; then
      echo "Using custom ports: Backend=$EFFECTIVE_BACKEND_PORT, Frontend=$EFFECTIVE_FRONTEND_PORT (DEV_HOST=$DEV_HOST)"
    else
      echo "Using default ports: Backend=$EFFECTIVE_BACKEND_PORT, Frontend=$EFFECTIVE_FRONTEND_PORT (DEV_HOST=$DEV_HOST)"
    fi

    if [ "${ENABLE_LDAP:-0}" = "1" ]; then
      DEV_HOST=$DEV_HOST BACKEND_PORT=$EFFECTIVE_BACKEND_PORT FRONTEND_PORT=$EFFECTIVE_FRONTEND_PORT sudo --preserve-env=DEV_HOST,BACKEND_PORT,FRONTEND_PORT,ENABLE_LDAP docker compose -f compose.dev.yml -f compose.dev.ldap.yml up $BUILD_FLAG
    else
      DEV_HOST=$DEV_HOST BACKEND_PORT=$EFFECTIVE_BACKEND_PORT FRONTEND_PORT=$EFFECTIVE_FRONTEND_PORT sudo --preserve-env=DEV_HOST,BACKEND_PORT,FRONTEND_PORT,ENABLE_LDAP docker compose -f compose.dev.yml up $BUILD_FLAG
    fi
    ;;

  "down")
    echo "Stopping development environment..."
    if [ "${ENABLE_LDAP:-0}" = "1" ]; then
      sudo --preserve-env=DEV_HOST,BACKEND_PORT,FRONTEND_PORT,ENABLE_LDAP docker compose -f compose.dev.yml -f compose.dev.ldap.yml down
    else
      sudo --preserve-env=DEV_HOST,BACKEND_PORT,FRONTEND_PORT,ENABLE_LDAP docker compose -f compose.dev.yml down
    fi
    ;;

  "restart")
    echo "Restarting development environment..."
    if [ "${ENABLE_LDAP:-0}" = "1" ]; then
      sudo --preserve-env=DEV_HOST,BACKEND_PORT,FRONTEND_PORT,ENABLE_LDAP docker compose -f compose.dev.yml -f compose.dev.ldap.yml down
    else
      sudo --preserve-env=DEV_HOST,BACKEND_PORT,FRONTEND_PORT,ENABLE_LDAP docker compose -f compose.dev.yml down
    fi
    # Reuse 'up' with remaining arguments
    exec "$0" up "$@"
    ;;

  "logs")
    echo "Showing logs..."
    if [ "${ENABLE_LDAP:-0}" = "1" ]; then
      sudo --preserve-env=DEV_HOST,BACKEND_PORT,FRONTEND_PORT,ENABLE_LDAP docker compose -f compose.dev.yml -f compose.dev.ldap.yml logs -f
    else
      sudo --preserve-env=DEV_HOST,BACKEND_PORT,FRONTEND_PORT,ENABLE_LDAP docker compose -f compose.dev.yml logs -f
    fi
    ;;

  "backend-logs")
    echo "Showing backend logs..."
    if [ "${ENABLE_LDAP:-0}" = "1" ]; then
      sudo --preserve-env=DEV_HOST,BACKEND_PORT,FRONTEND_PORT,ENABLE_LDAP docker compose -f compose.dev.yml -f compose.dev.ldap.yml logs -f backend
    else
      sudo --preserve-env=DEV_HOST,BACKEND_PORT,FRONTEND_PORT,ENABLE_LDAP docker compose -f compose.dev.yml logs -f backend
    fi
    ;;

  "frontend-logs")
    echo "Showing frontend logs..."
    if [ "${ENABLE_LDAP:-0}" = "1" ]; then
      sudo --preserve-env=DEV_HOST,BACKEND_PORT,FRONTEND_PORT,ENABLE_LDAP docker compose -f compose.dev.yml -f compose.dev.ldap.yml logs -f frontend
    else
      sudo --preserve-env=DEV_HOST,BACKEND_PORT,FRONTEND_PORT,ENABLE_LDAP docker compose -f compose.dev.yml logs -f frontend
    fi
    ;;

  "console")
    echo "Opening Rails console..."
    if [ "${ENABLE_LDAP:-0}" = "1" ]; then
      sudo --preserve-env=DEV_HOST,BACKEND_PORT,FRONTEND_PORT,ENABLE_LDAP docker compose -f compose.dev.yml -f compose.dev.ldap.yml exec backend rails console
    else
      sudo --preserve-env=DEV_HOST,BACKEND_PORT,FRONTEND_PORT,ENABLE_LDAP docker compose -f compose.dev.yml exec backend rails console
    fi
    ;;

  "migrate")
    echo "Running database migrations..."
    if [ "${ENABLE_LDAP:-0}" = "1" ]; then
      sudo --preserve-env=DEV_HOST,BACKEND_PORT,FRONTEND_PORT,ENABLE_LDAP docker compose -f compose.dev.yml -f compose.dev.ldap.yml exec backend rails db:migrate
    else
      sudo --preserve-env=DEV_HOST,BACKEND_PORT,FRONTEND_PORT,ENABLE_LDAP docker compose -f compose.dev.yml exec backend rails db:migrate
    fi
    ;;

  "reset")
    echo "Resetting database..."
    if [ "${ENABLE_LDAP:-0}" = "1" ]; then
      sudo --preserve-env=DEV_HOST,BACKEND_PORT,FRONTEND_PORT,ENABLE_LDAP docker compose -f compose.dev.yml -f compose.dev.ldap.yml exec backend rails db:reset
    else
      sudo --preserve-env=DEV_HOST,BACKEND_PORT,FRONTEND_PORT,ENABLE_LDAP docker compose -f compose.dev.yml exec backend rails db:reset
    fi
    ;;

  "sqlite")
    echo "Opening SQLite console..."
    if [ "${ENABLE_LDAP:-0}" = "1" ]; then
      sudo --preserve-env=DEV_HOST,BACKEND_PORT,FRONTEND_PORT,ENABLE_LDAP docker compose -f compose.dev.yml -f compose.dev.ldap.yml exec backend sqlite3 storage/development.sqlite3
    else
      sudo --preserve-env=DEV_HOST,BACKEND_PORT,FRONTEND_PORT,ENABLE_LDAP docker compose -f compose.dev.yml exec backend sqlite3 storage/development.sqlite3
    fi
    ;;

  "clean")
    echo "Cleaning up Docker resources..."
    if [ "${ENABLE_LDAP:-0}" = "1" ]; then
      sudo --preserve-env=DEV_HOST,BACKEND_PORT,FRONTEND_PORT,ENABLE_LDAP docker compose -f compose.dev.yml -f compose.dev.ldap.yml down -v
    else
      sudo --preserve-env=DEV_HOST,BACKEND_PORT,FRONTEND_PORT,ENABLE_LDAP docker compose -f compose.dev.yml down -v
    fi
    docker system prune -a -f
    ;;

  "rebuild")
    echo "Rebuilding all containers..."
    if [ "${ENABLE_LDAP:-0}" = "1" ]; then
      sudo --preserve-env=DEV_HOST,BACKEND_PORT,FRONTEND_PORT,ENABLE_LDAP docker compose -f compose.dev.yml -f compose.dev.ldap.yml down
      sudo --preserve-env=DEV_HOST,BACKEND_PORT,FRONTEND_PORT,ENABLE_LDAP docker compose -f compose.dev.yml -f compose.dev.ldap.yml build --no-cache
    else
      sudo --preserve-env=DEV_HOST,BACKEND_PORT,FRONTEND_PORT,ENABLE_LDAP docker compose -f compose.dev.yml down
      sudo --preserve-env=DEV_HOST,BACKEND_PORT,FRONTEND_PORT,ENABLE_LDAP docker compose -f compose.dev.yml build --no-cache
    fi
    # After rebuild, reuse 'up' with remaining arguments
    shift
    exec "$0" up "$@"
    ;;

  *)
    echo "Usage: $0 {up|down|restart|logs|backend-logs|frontend-logs|console|migrate|reset|sqlite|clean|rebuild} [ENABLE_LDAP] [backend_port] [frontend_port] [--build]"
    echo ""
    echo "Commands:"
    echo "  up [ENABLE_LDAP] [backend_port] [frontend_port] [--build] - Start development environment"
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
    echo "Env vars:"
    echo "  DEV_HOST                               - Hostname/IP used by the browser to reach backend (default: $(hostname -f))"
    echo ""
    echo "Default ports:"
    echo "  Backend:  $DEFAULT_BACKEND_PORT"
    echo "  Frontend: $DEFAULT_FRONTEND_PORT"
    echo ""
    echo "Examples:"
    echo "  $0 up                               # Default ports, LDAP off, no build"
    echo "  $0 up ENABLE_LDAP                   # Default ports, LDAP on, no build"
    echo "  $0 up --build                       # Default ports, LDAP off, with build"
    echo "  $0 up ENABLE_LDAP --build           # Default ports, LDAP on, with build"
    echo "  $0 up 3000 3001                     # Custom ports, LDAP off, no build"
    echo "  $0 up ENABLE_LDAP 3000 3001 --build # Custom ports, LDAP on, with build"
    exit 1
    ;;
esac

#!/bin/bash

# Docker development helper script

set -e

# Default ports
DEFAULT_BACKEND_PORT=4050
DEFAULT_FRONTEND_PORT=4051

# Resolve DEV_HOST if not provided (used by frontend to reach backend from browser)
DEV_HOST="${DEV_HOST:-$(hostname -f)}"
# Default ENABLE_LDAP to 0 unless explicitly set by user
ENABLE_LDAP="${ENABLE_LDAP:-0}"

case "$1" in
  "up")
    echo "Starting development environment..."
    if [ -n "$2" ] && [ -n "$3" ]; then
      echo "Using custom ports: Backend=$2, Frontend=$3 (DEV_HOST=$DEV_HOST)"
      if [ "$ENABLE_LDAP" = "1" ]; then
        DEV_HOST=$DEV_HOST BACKEND_PORT=$2 FRONTEND_PORT=$3 sudo --preserve-env=DEV_HOST,BACKEND_PORT,FRONTEND_PORT,ENABLE_LDAP docker compose -f compose.dev.yml -f compose.dev.ldap.yml up --build
      else
        DEV_HOST=$DEV_HOST BACKEND_PORT=$2 FRONTEND_PORT=$3 sudo --preserve-env=DEV_HOST,BACKEND_PORT,FRONTEND_PORT,ENABLE_LDAP docker compose -f compose.dev.yml up --build
      fi
    else
      echo "Using default ports: Backend=$DEFAULT_BACKEND_PORT, Frontend=$DEFAULT_FRONTEND_PORT (DEV_HOST=$DEV_HOST)"
      if [ "$ENABLE_LDAP" = "1" ]; then
        sudo --preserve-env=DEV_HOST,BACKEND_PORT,FRONTEND_PORT,ENABLE_LDAP docker compose -f compose.dev.yml -f compose.dev.ldap.yml up --build
      else
        sudo --preserve-env=DEV_HOST,BACKEND_PORT,FRONTEND_PORT,ENABLE_LDAP docker compose -f compose.dev.yml up --build
      fi
    fi
    ;;
  "down")
    echo "Stopping development environment..."
    if [ "$ENABLE_LDAP" = "1" ]; then
      sudo --preserve-env=DEV_HOST,BACKEND_PORT,FRONTEND_PORT,ENABLE_LDAP docker compose -f compose.dev.yml -f compose.dev.ldap.yml down
    else
      sudo --preserve-env=DEV_HOST,BACKEND_PORT,FRONTEND_PORT,ENABLE_LDAP docker compose -f compose.dev.yml down
    fi
    ;;
  "restart")
    echo "Restarting development environment..."
    if [ "$ENABLE_LDAP" = "1" ]; then
      sudo --preserve-env=DEV_HOST,BACKEND_PORT,FRONTEND_PORT,ENABLE_LDAP docker compose -f compose.dev.yml -f compose.dev.ldap.yml down
    else
      sudo --preserve-env=DEV_HOST,BACKEND_PORT,FRONTEND_PORT,ENABLE_LDAP docker compose -f compose.dev.yml down
    fi
    if [ -n "$2" ] && [ -n "$3" ]; then
      echo "Using custom ports: Backend=$2, Frontend=$3 (DEV_HOST=$DEV_HOST)"
      if [ "$ENABLE_LDAP" = "1" ]; then
        DEV_HOST=$DEV_HOST BACKEND_PORT=$2 FRONTEND_PORT=$3 sudo --preserve-env=DEV_HOST,BACKEND_PORT,FRONTEND_PORT,ENABLE_LDAP docker compose -f compose.dev.yml -f compose.dev.ldap.yml up --build
      else
        DEV_HOST=$DEV_HOST BACKEND_PORT=$2 FRONTEND_PORT=$3 sudo --preserve-env=DEV_HOST,BACKEND_PORT,FRONTEND_PORT,ENABLE_LDAP docker compose -f compose.dev.yml up --build
      fi
    else
      echo "Using default ports: Backend=$DEFAULT_BACKEND_PORT, Frontend=$DEFAULT_FRONTEND_PORT (DEV_HOST=$DEV_HOST)"
      if [ "$ENABLE_LDAP" = "1" ]; then
        sudo --preserve-env=DEV_HOST,BACKEND_PORT,FRONTEND_PORT,ENABLE_LDAP docker compose -f compose.dev.yml -f compose.dev.ldap.yml up --build
      else
        sudo --preserve-env=DEV_HOST,BACKEND_PORT,FRONTEND_PORT,ENABLE_LDAP docker compose -f compose.dev.yml up --build
      fi
    fi
    ;;
  "logs")
    echo "Showing logs..."
    if [ "$ENABLE_LDAP" = "1" ]; then
      sudo --preserve-env=DEV_HOST,BACKEND_PORT,FRONTEND_PORT,ENABLE_LDAP docker compose -f compose.dev.yml -f compose.dev.ldap.yml logs -f
    else
      sudo --preserve-env=DEV_HOST,BACKEND_PORT,FRONTEND_PORT,ENABLE_LDAP docker compose -f compose.dev.yml logs -f
    fi
    ;;
  "backend-logs")
    echo "Showing backend logs..."
    if [ "$ENABLE_LDAP" = "1" ]; then
      sudo --preserve-env=DEV_HOST,BACKEND_PORT,FRONTEND_PORT,ENABLE_LDAP docker compose -f compose.dev.yml -f compose.dev.ldap.yml logs -f backend
    else
      sudo --preserve-env=DEV_HOST,BACKEND_PORT,FRONTEND_PORT,ENABLE_LDAP docker compose -f compose.dev.yml logs -f backend
    fi
    ;;
  "frontend-logs")
    echo "Showing frontend logs..."
    if [ "$ENABLE_LDAP" = "1" ]; then
      sudo --preserve-env=DEV_HOST,BACKEND_PORT,FRONTEND_PORT,ENABLE_LDAP docker compose -f compose.dev.yml -f compose.dev.ldap.yml logs -f frontend
    else
      sudo --preserve-env=DEV_HOST,BACKEND_PORT,FRONTEND_PORT,ENABLE_LDAP docker compose -f compose.dev.yml logs -f frontend
    fi
    ;;
  "console")
    echo "Opening Rails console..."
    if [ "$ENABLE_LDAP" = "1" ]; then
      sudo --preserve-env=DEV_HOST,BACKEND_PORT,FRONTEND_PORT,ENABLE_LDAP docker compose -f compose.dev.yml -f compose.dev.ldap.yml exec backend rails console
    else
      sudo --preserve-env=DEV_HOST,BACKEND_PORT,FRONTEND_PORT,ENABLE_LDAP docker compose -f compose.dev.yml exec backend rails console
    fi
    ;;
  "migrate")
    echo "Running database migrations..."
    if [ "$ENABLE_LDAP" = "1" ]; then
      sudo --preserve-env=DEV_HOST,BACKEND_PORT,FRONTEND_PORT,ENABLE_LDAP docker compose -f compose.dev.yml -f compose.dev.ldap.yml exec backend rails db:migrate
    else
      sudo --preserve-env=DEV_HOST,BACKEND_PORT,FRONTEND_PORT,ENABLE_LDAP docker compose -f compose.dev.yml exec backend rails db:migrate
    fi
    ;;
  "reset")
    echo "Resetting database..."
    if [ "$ENABLE_LDAP" = "1" ]; then
      sudo --preserve-env=DEV_HOST,BACKEND_PORT,FRONTEND_PORT,ENABLE_LDAP docker compose -f compose.dev.yml -f compose.dev.ldap.yml exec backend rails db:reset
    else
      sudo --preserve-env=DEV_HOST,BACKEND_PORT,FRONTEND_PORT,ENABLE_LDAP docker compose -f compose.dev.yml exec backend rails db:reset
    fi
    ;;
  "sqlite")
    echo "Opening SQLite console..."
    if [ "$ENABLE_LDAP" = "1" ]; then
      sudo --preserve-env=DEV_HOST,BACKEND_PORT,FRONTEND_PORT,ENABLE_LDAP docker compose -f compose.dev.yml -f compose.dev.ldap.yml exec backend sqlite3 storage/development.sqlite3
    else
      sudo --preserve-env=DEV_HOST,BACKEND_PORT,FRONTEND_PORT,ENABLE_LDAP docker compose -f compose.dev.yml exec backend sqlite3 storage/development.sqlite3
    fi
    ;;
  "clean")
    echo "Cleaning up Docker resources..."
    if [ "$ENABLE_LDAP" = "1" ]; then
      sudo --preserve-env=DEV_HOST,BACKEND_PORT,FRONTEND_PORT,ENABLE_LDAP docker compose -f compose.dev.yml -f compose.dev.ldap.yml down -v
    else
      sudo --preserve-env=DEV_HOST,BACKEND_PORT,FRONTEND_PORT,ENABLE_LDAP docker compose -f compose.dev.yml down -v
    fi
    docker system prune -a -f
    ;;
  "rebuild")
    echo "Rebuilding all containers..."
    if [ "$ENABLE_LDAP" = "1" ]; then
      sudo --preserve-env=DEV_HOST,BACKEND_PORT,FRONTEND_PORT,ENABLE_LDAP docker compose -f compose.dev.yml -f compose.dev.ldap.yml down
      sudo --preserve-env=DEV_HOST,BACKEND_PORT,FRONTEND_PORT,ENABLE_LDAP docker compose -f compose.dev.yml -f compose.dev.ldap.yml build --no-cache
    else
      sudo --preserve-env=DEV_HOST,BACKEND_PORT,FRONTEND_PORT,ENABLE_LDAP docker compose -f compose.dev.yml down
      sudo --preserve-env=DEV_HOST,BACKEND_PORT,FRONTEND_PORT,ENABLE_LDAP docker compose -f compose.dev.yml build --no-cache
    fi
    if [ -n "$2" ] && [ -n "$3" ]; then
      echo "Using custom ports: Backend=$2, Frontend=$3 (DEV_HOST=$DEV_HOST)"
      if [ "$ENABLE_LDAP" = "1" ]; then
        DEV_HOST=$DEV_HOST BACKEND_PORT=$2 FRONTEND_PORT=$3 sudo --preserve-env=DEV_HOST,BACKEND_PORT,FRONTEND_PORT,ENABLE_LDAP docker compose -f compose.dev.yml -f compose.dev.ldap.yml up
      else
        DEV_HOST=$DEV_HOST BACKEND_PORT=$2 FRONTEND_PORT=$3 sudo --preserve-env=DEV_HOST,BACKEND_PORT,FRONTEND_PORT,ENABLE_LDAP docker compose -f compose.dev.yml up
      fi
    else
      echo "Using default ports: Backend=$DEFAULT_BACKEND_PORT, Frontend=$DEFAULT_FRONTEND_PORT (DEV_HOST=$DEV_HOST)"
      if [ "$ENABLE_LDAP" = "1" ]; then
        sudo --preserve-env=DEV_HOST,BACKEND_PORT,FRONTEND_PORT,ENABLE_LDAP docker compose -f compose.dev.yml -f compose.dev.ldap.yml up
      else
        sudo --preserve-env=DEV_HOST,BACKEND_PORT,FRONTEND_PORT,ENABLE_LDAP docker compose -f compose.dev.yml up
      fi
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
    echo "Env vars:"
    echo "  DEV_HOST                               - Hostname/IP used by the browser to reach backend (default: $(hostname -f))"
    echo ""
    echo "Default ports:"
    echo "  Backend:  $DEFAULT_BACKEND_PORT"
    echo "  Frontend: $DEFAULT_FRONTEND_PORT"
    echo ""
    echo "Examples:"
    echo "  sudo DEV_HOST=$(hostname -f) ENABLE_LDAP=1 $0 up 3000 3001  # Enable LDAP with custom ports and explicit host"
    echo "  $0 restart 8080 8081     # Restart with custom ports"
    exit 1
    ;;
esac 