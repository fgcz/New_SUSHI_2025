#!/bin/bash

# Development environment startup script
# Usage:
#   ./start-dev.sh [frontend-port] [backend-port]
#   FRONTEND_PORT=3001 BACKEND_PORT=3000 ./start-dev.sh

set -e

# Default ports
DEFAULT_FRONTEND_PORT=4051
DEFAULT_BACKEND_PORT=4050

# Read from env with defaults
FRONTEND_PORT="${FRONTEND_PORT:-$DEFAULT_FRONTEND_PORT}"
BACKEND_PORT="${BACKEND_PORT:-$DEFAULT_BACKEND_PORT}"

# Positional args override env
[ -n "$1" ] && FRONTEND_PORT="$1"
[ -n "$2" ] && BACKEND_PORT="$2"

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
echo "🔧 Backend:  http://localhost:$BACKEND_PORT"
echo "📱 Frontend: http://localhost:$FRONTEND_PORT"
echo ""

# Start backend
echo "🔧 Starting backend..."
cd backend
RAILS_ENV=development bundle exec rails s -p $BACKEND_PORT &
BACKEND_PID=$!
cd ..

# Wait a bit before starting frontend
sleep 3

# Start frontend
echo "📱 Starting frontend..."
cd frontend
API_URL="http://localhost:$BACKEND_PORT"
NEXT_PUBLIC_API_URL="$API_URL" NEXT_PUBLIC_API_PORT="$BACKEND_PORT" npm run dev -- --port "$FRONTEND_PORT" &
FRONTEND_PID=$!
cd ..

echo ""
echo "✅ Development environment started!"
echo "🔧 Backend:  http://localhost:$BACKEND_PORT"
echo "📱 Frontend: http://localhost:$FRONTEND_PORT"
echo "ℹ️  Frontend will call API at $API_URL"
echo ""
echo "Press Ctrl+C to stop"

# Wait for processes
wait $BACKEND_PID $FRONTEND_PID 
