#!/bin/bash

# Development environment startup script
# Usage: ./start-dev.sh [frontend-port] [backend-port]

# Default port settings
FRONTEND_PORT=${1:-4051}
BACKEND_PORT=${2:-4050}

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
echo "📱 Frontend: http://localhost:$FRONTEND_PORT"
echo "🔧 Backend: http://localhost:$BACKEND_PORT"
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
NEXT_PUBLIC_API_PORT=$BACKEND_PORT npm run dev -- --port $FRONTEND_PORT &
FRONTEND_PID=$!
cd ..

echo ""
echo "✅ Development environment started!"
echo "📱 Frontend: http://localhost:$FRONTEND_PORT"
echo "🔧 Backend: http://localhost:$BACKEND_PORT"
echo ""
echo "Press Ctrl+C to stop"

# Wait for processes
wait $BACKEND_PID $FRONTEND_PID 
