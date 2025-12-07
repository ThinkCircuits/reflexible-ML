#!/bin/bash
################################################################################
# Jetson Whisper WebSocket Server Startup Script
# Starts the WebSocket-based Whisper ASR server for push-to-talk functionality
################################################################################

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

################################################################################
# Configuration
################################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Model options: tiny.en, base.en, small.en, small, medium, large-v3-turbo
MODEL="${MODEL:-large-v3-turbo}"

# Server configuration
PORT="${PORT:-8766}"
HOST="${HOST:-0.0.0.0}"

# Virtual environment (in project root)
VENV_DIR="$PROJECT_DIR/whisper-venv"

# CTranslate2 library path (if built from source for CUDA support)
CTRANSLATE2_LIB="$PROJECT_DIR/ctranslate2-build/install/lib"
if [ -d "$CTRANSLATE2_LIB" ]; then
    export LD_LIBRARY_PATH="$CTRANSLATE2_LIB:$LD_LIBRARY_PATH"
fi

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

################################################################################
# Installation
################################################################################

install_dependencies() {
    print_info "Installing/updating dependencies..."

    if [ ! -d "$VENV_DIR" ]; then
        print_info "Creating virtual environment..."
        python3 -m venv "$VENV_DIR"
    fi

    source "$VENV_DIR/bin/activate"

    print_info "Installing faster-whisper and websockets..."
    pip install --upgrade pip
    pip install faster-whisper websockets soundfile numpy

    print_status "Dependencies installed"
    deactivate
}

################################################################################
# Main
################################################################################

print_header "Jetson Whisper WebSocket Server"
echo ""

# Parse arguments
DO_INSTALL=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --install)
            DO_INSTALL=true
            shift
            ;;
        --model)
            MODEL="$2"
            shift 2
            ;;
        --port)
            PORT="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --install      Install dependencies first"
            echo "  --model NAME   Model to use (default: small.en)"
            echo "  --port PORT    WebSocket port (default: 8766)"
            echo ""
            echo "Available models:"
            echo "  tiny.en, tiny     - Fastest, lowest quality"
            echo "  base.en, base     - Fast, decent quality"
            echo "  small.en, small   - Good balance (recommended)"
            echo "  medium            - Better quality, slower"
            echo "  large-v3-turbo    - Best quality, requires more memory"
            echo ""
            echo "Examples:"
            echo "  $0 --install              # Install and start server"
            echo "  $0 --model large-v3-turbo # Use large model"
            echo "  $0 --port 9000            # Run on port 9000"
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Install if requested or venv doesn't exist
if [ "$DO_INSTALL" = true ] || [ ! -d "$VENV_DIR" ]; then
    install_dependencies
fi

# Check for whisper_ws_server.py
if [ ! -f "$SCRIPT_DIR/whisper_ws_server.py" ]; then
    print_error "whisper_ws_server.py not found in $SCRIPT_DIR"
    exit 1
fi

# Activate venv and run
print_info "Model: $MODEL"
print_info "Port: $PORT"
echo ""

source "$VENV_DIR/bin/activate"
python3 "$SCRIPT_DIR/whisper_ws_server.py" --model "$MODEL" --port "$PORT" --bind "$HOST"
