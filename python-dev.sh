#!/bin/bash
# Usage: ./python-dev.sh [start|stop|restart|status]
#   BACKEND_PORT=4071 FRONTEND_PORT=4070 ./python-dev.sh start
#   DEV_HOST=fgcz-h-083.fgcz-net.unizh.ch ./python-dev.sh start

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

BACKEND_PID_FILE="$ROOT_DIR/.backend-python.pid"
FRONTEND_PID_FILE="$ROOT_DIR/.frontend.pid"
BACKEND_LOG="$ROOT_DIR/backend_python/backend.log"
FRONTEND_LOG="$ROOT_DIR/frontend/frontend.log"

BACKEND_PORT="${BACKEND_PORT:-4071}"
FRONTEND_PORT="${FRONTEND_PORT:-4070}"
API_HOST="${DEV_HOST:-$(hostname -f)}"

start() {
    if [ -f "$BACKEND_PID_FILE" ] && kill -0 "$(cat "$BACKEND_PID_FILE")" 2>/dev/null; then
        echo "Backend already running (PID $(cat "$BACKEND_PID_FILE"))"
    else
        echo "Starting Python backend on port $BACKEND_PORT..."
        cd "$ROOT_DIR/backend_python"
        nohup uv run uvicorn app.main:app --reload --port "$BACKEND_PORT" --host 0.0.0.0 \
            >> "$BACKEND_LOG" 2>&1 &
        echo $! > "$BACKEND_PID_FILE"
        echo "Backend started (PID $!), log: $BACKEND_LOG"
        cd "$ROOT_DIR"
    fi

    if [ -f "$FRONTEND_PID_FILE" ] && kill -0 "$(cat "$FRONTEND_PID_FILE")" 2>/dev/null; then
        echo "Frontend already running (PID $(cat "$FRONTEND_PID_FILE"))"
    else
        echo "Starting Next.js frontend on port $FRONTEND_PORT..."
        cd "$ROOT_DIR/frontend"
        NEXT_PUBLIC_API_URL="http://$API_HOST:$BACKEND_PORT" \
            nohup npm run dev -- --port "$FRONTEND_PORT" --hostname 0.0.0.0 \
            >> "$FRONTEND_LOG" 2>&1 &
        echo $! > "$FRONTEND_PID_FILE"
        echo "Frontend started (PID $!), log: $FRONTEND_LOG"
        cd "$ROOT_DIR"
    fi

    echo ""
    echo "Backend:  http://$API_HOST:$BACKEND_PORT"
    echo "Frontend: http://$API_HOST:$FRONTEND_PORT"
}

kill_group() {
    local pid="$1"
    local pgid
    pgid=$(ps -o pgid= -p "$pid" 2>/dev/null | tr -d ' ')
    if [ -n "$pgid" ] && [ "$pgid" != "0" ]; then
        kill -- -"$pgid" 2>/dev/null
    else
        kill "$pid" 2>/dev/null
    fi
}

stop() {
    if [ -f "$BACKEND_PID_FILE" ]; then
        PID=$(cat "$BACKEND_PID_FILE")
        if kill -0 "$PID" 2>/dev/null; then
            echo "Stopping backend (PID $PID)..."
            kill_group "$PID"
        else
            echo "Backend not running (stale PID file)"
        fi
        rm -f "$BACKEND_PID_FILE"
    else
        echo "No backend PID file found"
    fi

    if [ -f "$FRONTEND_PID_FILE" ]; then
        PID=$(cat "$FRONTEND_PID_FILE")
        if kill -0 "$PID" 2>/dev/null; then
            echo "Stopping frontend (PID $PID)..."
            kill_group "$PID"
        else
            echo "Frontend not running (stale PID file)"
        fi
        rm -f "$FRONTEND_PID_FILE"
    else
        echo "No frontend PID file found"
    fi
}

status() {
    if [ -f "$BACKEND_PID_FILE" ] && kill -0 "$(cat "$BACKEND_PID_FILE")" 2>/dev/null; then
        echo "Backend:  running (PID $(cat "$BACKEND_PID_FILE")) on port $BACKEND_PORT"
    else
        echo "Backend:  stopped"
    fi

    if [ -f "$FRONTEND_PID_FILE" ] && kill -0 "$(cat "$FRONTEND_PID_FILE")" 2>/dev/null; then
        echo "Frontend: running (PID $(cat "$FRONTEND_PID_FILE")) on port $FRONTEND_PORT"
    else
        echo "Frontend: stopped"
    fi
}

case "${1:-start}" in
    start)   start ;;
    stop)    stop ;;
    restart) stop; sleep 2; start ;;
    status)  status ;;
    *)
        echo "Usage: $0 [start|stop|restart|status]"
        exit 1
        ;;
esac
