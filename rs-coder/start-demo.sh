#!/bin/bash
################################################################################
# VL Demo Stack Manager
# Unified startup script for Vision-Language demo with TTS and Whisper
# Runs services in a detachable tmux session with tiled panes
################################################################################

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

################################################################################
# Configuration
################################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$SCRIPT_DIR/scripts"
VLDEMO_DIR="$SCRIPT_DIR/vl-demo"

# tmux session name
SESSION_NAME="${SESSION_NAME:-vl-demo}"

# Service ports
VLLM_PORT="${VLLM_PORT:-8000}"
TTS_PORT="${TTS_PORT:-7860}"
WHISPER_PORT="${WHISPER_PORT:-8766}"
WEB_HTTPS_PORT="${WEB_HTTPS_PORT:-8443}"
WEB_HTTP_PORT="${WEB_HTTP_PORT:-8080}"

# Default services to start (all)
START_VLLM=true
START_TTS=true
START_WHISPER=true
START_WEB=true

################################################################################
# Helper Functions
################################################################################

print_header() {
    echo -e "${BLUE}================================================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}================================================================================${NC}"
}

print_status() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_info() {
    echo -e "${YELLOW}[i]${NC} $1"
}

check_dependencies() {
    local missing=()

    if ! command -v tmux &>/dev/null; then
        missing+=("tmux")
    fi

    if ! command -v docker &>/dev/null; then
        missing+=("docker")
    fi

    if [ ${#missing[@]} -gt 0 ]; then
        print_error "Missing dependencies: ${missing[*]}"
        echo "Install with: sudo apt install ${missing[*]}"
        exit 1
    fi
}

is_session_running() {
    tmux has-session -t "$SESSION_NAME" 2>/dev/null
}

kill_session() {
    if is_session_running; then
        print_info "Stopping existing session: $SESSION_NAME"
        tmux kill-session -t "$SESSION_NAME"
        sleep 1
    fi
}

wait_for_service() {
    local name="$1"
    local url="$2"
    local max_wait="${3:-120}"

    echo -n "  Waiting for $name..."
    for i in $(seq 1 $max_wait); do
        if curl -s "$url" &>/dev/null; then
            echo -e " ${GREEN}ready${NC}"
            return 0
        fi
        echo -n "."
        sleep 1
    done
    echo -e " ${RED}timeout${NC}"
    return 1
}

################################################################################
# Service Commands
################################################################################

cmd_vllm() {
    # Remove the read -p prompt for unattended start
    echo "cd '$SCRIPTS_DIR' && exec ./jetson_deploy_vl.sh --port $VLLM_PORT 2>&1 | head -1000"
}

cmd_tts() {
    echo "cd '$SCRIPT_DIR' && exec '$SCRIPT_DIR/tts-venv/bin/python' '$SCRIPTS_DIR/piper_tts_server.py' --port $TTS_PORT 2>&1"
}

cmd_whisper() {
    # Set LD_LIBRARY_PATH for custom ctranslate2 build with CUDA support
    local ct2_lib="$SCRIPT_DIR/ctranslate2-build/install/lib"
    local ld_path=""
    if [ -d "$ct2_lib" ]; then
        ld_path="export LD_LIBRARY_PATH='$ct2_lib:\$LD_LIBRARY_PATH' && "
    fi
    echo "cd '$SCRIPT_DIR' && ${ld_path}exec '$SCRIPT_DIR/whisper-venv/bin/python' '$SCRIPTS_DIR/whisper_ws_server.py' --port $WHISPER_PORT 2>&1"
}

cmd_web() {
    echo "cd '$VLDEMO_DIR' && exec python3 server.py --port $WEB_HTTPS_PORT --http-port $WEB_HTTP_PORT 2>&1"
}

################################################################################
# Start Session
################################################################################

start_session() {
    local pane_count=0
    local panes=()

    # Count services to start
    [ "$START_VLLM" = true ] && { panes+=("vLLM"); ((++pane_count)); }
    [ "$START_TTS" = true ] && { panes+=("TTS"); ((++pane_count)); }
    [ "$START_WHISPER" = true ] && { panes+=("Whisper"); ((++pane_count)); }
    [ "$START_WEB" = true ] && { panes+=("Web"); ((++pane_count)); }

    if [ $pane_count -eq 0 ]; then
        print_error "No services selected to start"
        exit 1
    fi

    print_info "Starting services: ${panes[*]}"
    echo ""

    # Kill existing session if running
    kill_session

    # Create new session with first pane
    local first=true
    local pane_idx=0

    if [ "$START_VLLM" = true ] && [ "$first" = true ]; then
        print_info "Creating tmux session with vLLM pane..."
        tmux new-session -d -s "$SESSION_NAME" -n "demo" "cd '$SCRIPTS_DIR' && exec ./jetson_deploy_vl.sh --port $VLLM_PORT -y 2>&1"
        first=false
        ((++pane_idx)) || true
    fi

    if [ "$START_TTS" = true ]; then
        if [ "$first" = true ]; then
            print_info "Creating tmux session with TTS pane..."
            tmux new-session -d -s "$SESSION_NAME" -n "demo" "$(cmd_tts)"
            first=false
        else
            print_info "Adding TTS pane..."
            tmux split-window -t "$SESSION_NAME:0" -h "$(cmd_tts)"
        fi
        ((++pane_idx)) || true
    fi

    if [ "$START_WHISPER" = true ]; then
        if [ "$first" = true ]; then
            print_info "Creating tmux session with Whisper pane..."
            tmux new-session -d -s "$SESSION_NAME" -n "demo" "$(cmd_whisper)"
            first=false
        else
            print_info "Adding Whisper pane..."
            tmux split-window -t "$SESSION_NAME:0" -v "$(cmd_whisper)"
        fi
        ((++pane_idx)) || true
    fi

    if [ "$START_WEB" = true ]; then
        if [ "$first" = true ]; then
            print_info "Creating tmux session with Web pane..."
            tmux new-session -d -s "$SESSION_NAME" -n "demo" "$(cmd_web)"
            first=false
        else
            print_info "Adding Web server pane..."
            tmux split-window -t "$SESSION_NAME:0" -v "$(cmd_web)"
        fi
        ((++pane_idx)) || true
    fi

    # Apply tiled layout for nice even panes
    tmux select-layout -t "$SESSION_NAME:0" tiled

    # Set pane titles for easier identification
    local idx=0
    [ "$START_VLLM" = true ] && { tmux select-pane -t "$SESSION_NAME:0.$idx" -T "vLLM"; ((++idx)) || true; }
    [ "$START_TTS" = true ] && { tmux select-pane -t "$SESSION_NAME:0.$idx" -T "TTS"; ((++idx)) || true; }
    [ "$START_WHISPER" = true ] && { tmux select-pane -t "$SESSION_NAME:0.$idx" -T "Whisper"; ((++idx)) || true; }
    [ "$START_WEB" = true ] && { tmux select-pane -t "$SESSION_NAME:0.$idx" -T "Web"; ((++idx)) || true; }

    # Enable pane borders with titles
    tmux set-option -t "$SESSION_NAME" pane-border-status top
    tmux set-option -t "$SESSION_NAME" pane-border-format " #{pane_title} "

    print_status "tmux session '$SESSION_NAME' created with $pane_count panes"
    echo ""
}

################################################################################
# Status Check
################################################################################

show_status() {
    print_header "Service Status"
    echo ""

    # Check tmux session
    if is_session_running; then
        print_status "tmux session '$SESSION_NAME' is running"
        local pane_count=$(tmux list-panes -t "$SESSION_NAME" 2>/dev/null | wc -l)
        print_info "  Panes: $pane_count"
    else
        print_error "tmux session '$SESSION_NAME' not running"
    fi
    echo ""

    # Check individual services
    echo "Services:"

    if curl -s "http://localhost:$VLLM_PORT/health" &>/dev/null; then
        echo -e "  ${GREEN}●${NC} vLLM (port $VLLM_PORT) - running"
    else
        echo -e "  ${RED}○${NC} vLLM (port $VLLM_PORT) - not responding"
    fi

    if curl -s "http://localhost:$TTS_PORT/health" &>/dev/null; then
        echo -e "  ${GREEN}●${NC} TTS (port $TTS_PORT) - running"
    else
        echo -e "  ${RED}○${NC} TTS (port $TTS_PORT) - not responding"
    fi

    # Whisper uses WebSocket, check if port is open
    if ss -tlnp 2>/dev/null | grep -q ":$WHISPER_PORT " || netstat -tlnp 2>/dev/null | grep -q ":$WHISPER_PORT "; then
        echo -e "  ${GREEN}●${NC} Whisper (port $WHISPER_PORT) - running"
    else
        echo -e "  ${RED}○${NC} Whisper (port $WHISPER_PORT) - not responding"
    fi

    if curl -sk "https://localhost:$WEB_HTTPS_PORT" &>/dev/null; then
        echo -e "  ${GREEN}●${NC} Web Server (port $WEB_HTTPS_PORT) - running"
    else
        echo -e "  ${RED}○${NC} Web Server (port $WEB_HTTPS_PORT) - not responding"
    fi

    echo ""
}

################################################################################
# Usage
################################################################################

show_usage() {
    echo "Usage: $0 [command] [options]"
    echo ""
    echo "Commands:"
    echo "  start       Start all services in tmux session (default)"
    echo "  stop        Stop the tmux session and all services"
    echo "  restart     Restart all services"
    echo "  status      Show status of all services"
    echo "  attach      Attach to the tmux session"
    echo "  logs        Show recent logs from all panes"
    echo ""
    echo "Options:"
    echo "  --only-vllm       Start only vLLM server"
    echo "  --only-tts        Start only TTS server"
    echo "  --only-whisper    Start only Whisper server"
    echo "  --only-web        Start only web server"
    echo "  --no-vllm         Start all except vLLM"
    echo "  --no-tts          Start all except TTS"
    echo "  --no-whisper      Start all except Whisper"
    echo "  --no-web          Start all except web server"
    echo ""
    echo "Ports (configurable via environment):"
    echo "  VLLM_PORT=$VLLM_PORT"
    echo "  TTS_PORT=$TTS_PORT"
    echo "  WHISPER_PORT=$WHISPER_PORT"
    echo "  WEB_HTTPS_PORT=$WEB_HTTPS_PORT"
    echo "  WEB_HTTP_PORT=$WEB_HTTP_PORT"
    echo ""
    echo "Examples:"
    echo "  $0                     # Start all services"
    echo "  $0 start --no-vllm    # Start TTS, Whisper, Web only"
    echo "  $0 stop               # Stop all services"
    echo "  $0 attach             # Attach to session (Ctrl+B D to detach)"
    echo "  $0 status             # Check service status"
    echo ""
    echo "tmux Tips:"
    echo "  Ctrl+B D              Detach from session"
    echo "  Ctrl+B [arrow]        Navigate between panes"
    echo "  Ctrl+B Z              Toggle pane zoom (fullscreen)"
    echo "  Ctrl+B [              Enter scroll mode (q to exit)"
    echo ""
}

################################################################################
# Main
################################################################################

print_header "VL Demo Stack Manager"
echo ""

# Parse command
COMMAND="${1:-start}"
shift 2>/dev/null || true

# Parse options
while [[ $# -gt 0 ]]; do
    case $1 in
        --only-vllm)
            START_VLLM=true; START_TTS=false; START_WHISPER=false; START_WEB=false
            shift ;;
        --only-tts)
            START_VLLM=false; START_TTS=true; START_WHISPER=false; START_WEB=false
            shift ;;
        --only-whisper)
            START_VLLM=false; START_TTS=false; START_WHISPER=true; START_WEB=false
            shift ;;
        --only-web)
            START_VLLM=false; START_TTS=false; START_WHISPER=false; START_WEB=true
            shift ;;
        --no-vllm)
            START_VLLM=false
            shift ;;
        --no-tts)
            START_TTS=false
            shift ;;
        --no-whisper)
            START_WHISPER=false
            shift ;;
        --no-web)
            START_WEB=false
            shift ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            echo "Use --help for usage"
            exit 1
            ;;
    esac
done

# Check dependencies
check_dependencies

# Execute command
case $COMMAND in
    start)
        start_session
        echo ""
        print_info "Demo stack starting in background"
        echo ""
        print_info "Access points:"
        [ "$START_WEB" = true ] && echo "  Web UI:      https://localhost:$WEB_HTTPS_PORT"
        [ "$START_WEB" = true ] && echo "               http://localhost:$WEB_HTTP_PORT (redirects to HTTPS)"
        [ "$START_VLLM" = true ] && echo "  vLLM API:    http://localhost:$VLLM_PORT/v1"
        [ "$START_TTS" = true ] && echo "  TTS API:     http://localhost:$TTS_PORT"
        [ "$START_WHISPER" = true ] && echo "  Whisper WS:  ws://localhost:$WHISPER_PORT"
        echo ""
        print_info "To attach to the session: $0 attach"
        print_info "To view status: $0 status"
        echo ""

        # Try to get network IP
        LOCAL_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
        if [ -n "$LOCAL_IP" ]; then
            print_info "Network access (from other devices):"
            [ "$START_WEB" = true ] && echo "  Web UI:      https://$LOCAL_IP:$WEB_HTTPS_PORT"
            echo ""
        fi
        ;;

    stop)
        print_info "Stopping demo stack..."
        kill_session
        print_status "All services stopped"
        ;;

    restart)
        print_info "Restarting demo stack..."
        kill_session
        sleep 2
        start_session
        print_status "Demo stack restarted"
        ;;

    status)
        show_status
        ;;

    attach)
        if is_session_running; then
            print_info "Attaching to session '$SESSION_NAME'..."
            print_info "Use Ctrl+B D to detach"
            echo ""
            exec tmux attach-session -t "$SESSION_NAME"
        else
            print_error "Session '$SESSION_NAME' is not running"
            echo "Start it with: $0 start"
            exit 1
        fi
        ;;

    logs)
        if is_session_running; then
            print_info "Recent output from each pane:"
            echo ""
            tmux list-panes -t "$SESSION_NAME" -F '#{pane_index}:#{pane_title}' | while read pane; do
                idx=${pane%%:*}
                title=${pane#*:}
                echo -e "${CYAN}=== $title (pane $idx) ===${NC}"
                tmux capture-pane -t "$SESSION_NAME:0.$idx" -p | tail -20
                echo ""
            done
        else
            print_error "Session '$SESSION_NAME' is not running"
            exit 1
        fi
        ;;

    help|-h|--help)
        show_usage
        ;;

    *)
        print_error "Unknown command: $COMMAND"
        echo "Use --help for usage"
        exit 1
        ;;
esac
