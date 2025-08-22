#!/bin/bash

# Development environment startup script
# Usage:
#   ./start-dev.sh [backend-port] [frontend-port]
#   BACKEND_PORT=4000 FRONTEND_PORT=4001 ./start-dev.sh
#   ./start-dev.sh ENABLE_LDAP [backend-port] [frontend-port]  # enable LDAP (sets ENABLE_LDAP=1)

set -e

# Default ports
DEFAULT_BACKEND_PORT=4050
DEFAULT_FRONTEND_PORT=4051

# Read from env with defaults
FRONTEND_PORT="${FRONTEND_PORT:-$DEFAULT_FRONTEND_PORT}"
BACKEND_PORT="${BACKEND_PORT:-$DEFAULT_BACKEND_PORT}"

# Optional flag to enable LDAP: allow `./start-dev.sh ENABLE_LDAP`
if [ "${1:-}" = "ENABLE_LDAP" ]; then
  export ENABLE_LDAP=1
  echo "🔐 ENABLE_LDAP=1 (via flag)"
else
  if [ -z "${ENABLE_LDAP+x}" ]; then
    echo "🔐 ENABLE_LDAP is unset (default)"
  else
    echo "🔐 ENABLE_LDAP=${ENABLE_LDAP} (pre-set)"
  fi
fi

# Positional args override env
if [ "${1:-}" = "ENABLE_LDAP" ]; then
  [ -n "$2" ] && BACKEND_PORT="$2"
  [ -n "$3" ] && FRONTEND_PORT="$3"
else
  [ -n "$1" ] && BACKEND_PORT="$1"
  [ -n "$2" ] && FRONTEND_PORT="$2"
fi

# Function to cleanup processes
cleanup() {
    echo ""
    echo "🛑 Stopping processes..."
    if [ ! -z "$BACKEND_PID" ]; then
        kill $BACKEND_PID 2>/dev/null
    fi
    if [ ! -z "$FRONTEND_PID" ]; then
        kill $FRONTEND_PID 2>/dev/null
    fi
    echo "✅ Processes stopped"
    exit 0
}

# Set trap to cleanup on script exit
trap cleanup SIGINT SIGTERM

echo "🚀 Starting development environment..."
echo "(Hint) Override API host by setting DEV_HOST if accessed remotely"
echo ""

# Start backend
echo "🔧 Starting backend..."
cd backend
# If LDAP is requested and available, ensure the LDAP group is installed
if [ "${ENABLE_LDAP:-0}" = "1" ]; then
  echo "🔎 LDAP requested (ENABLE_LDAP=1)"
  LDAP_PATH="/usr/local/ngseq/gems/devise_ldap_authenticatable_forked_20190712"
  if [ -d "$LDAP_PATH" ]; then
    if ! bundle show devise_ldap_authenticatable >/dev/null 2>&1; then
      echo "⬇️  Installing gems for group :ldap ..."
      bundle config set --local path 'vendor/bundle'
      bundle install --with ldap
    fi
  else
    echo "⚠️  LDAP gem path not found at $LDAP_PATH. Continuing without LDAP."
  fi
fi
# Bind to 0.0.0.0 so it is reachable from remote browsers
if [ "${ENABLE_LDAP:-0}" = "1" ]; then
  BUNDLE_WITH=ldap RAILS_ENV=development bundle exec rails s -p $BACKEND_PORT -b 0.0.0.0 &
else
  RAILS_ENV=development bundle exec rails s -p $BACKEND_PORT -b 0.0.0.0 &
fi
BACKEND_PID=$!
cd ..

# Wait a bit before starting frontend
sleep 3

# Start frontend
echo "📱 Starting frontend..."
cd frontend
# Determine API host visible to the browser. Allow override via DEV_HOST
API_HOST="${DEV_HOST:-$(hostname -f)}"
API_URL="http://$API_HOST:$BACKEND_PORT"
# Bind Next dev server to 0.0.0.0 for remote access
NEXT_PUBLIC_API_URL="$API_URL" NEXT_PUBLIC_API_PORT="$BACKEND_PORT" npm run dev -- --port "$FRONTEND_PORT" --hostname 0.0.0.0 &
FRONTEND_PID=$!
cd ..

echo ""
echo "✅ Development environment started!"
echo "🔧 Backend:  http://$API_HOST:$BACKEND_PORT (bound 0.0.0.0)"
echo "📱 Frontend: http://$API_HOST:$FRONTEND_PORT (bound 0.0.0.0)"
echo "ℹ️  Frontend will call API at $API_URL"
echo ""
echo "Press Ctrl+C to stop"

# Wait for processes
wait $BACKEND_PID $FRONTEND_PID 
