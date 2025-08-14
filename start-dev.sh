#!/bin/bash

# Development environment startup script
# Usage:
#   ./start-dev.sh [backend-port] [frontend-port]
#   BACKEND_PORT=4000 FRONTEND_PORT=4001 ./start-dev.sh

set -e

# Default ports
DEFAULT_BACKEND_PORT=4050
DEFAULT_FRONTEND_PORT=4051

# Read from env with defaults
FRONTEND_PORT="${FRONTEND_PORT:-$DEFAULT_FRONTEND_PORT}"
BACKEND_PORT="${BACKEND_PORT:-$DEFAULT_BACKEND_PORT}"

# Positional args override env
[ -n "$1" ] && BACKEND_PORT="$1"
[ -n "$2" ] && FRONTEND_PORT="$2"

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
# Bind to 0.0.0.0 so it is reachable from remote browsers
RAILS_ENV=development bundle exec rails s -p $BACKEND_PORT -b 0.0.0.0 &
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
