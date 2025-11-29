#!/bin/bash
################################################################################
# Piper TTS Server Startup Script (Optimized)
# Fast, local neural text-to-speech for Jetson ARM64
# Uses persistent model loading for ~100ms latency (vs ~1300ms cold start)
################################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PORT="${PORT:-7860}"

echo -e "${BLUE}============================================================${NC}"
echo -e "${BLUE}Piper TTS Server (Optimized)${NC}"
echo -e "${BLUE}============================================================${NC}"
echo ""

# Check if server is already running
if curl -s http://localhost:$PORT/health &>/dev/null; then
    echo -e "${YELLOW}[!]${NC} Piper TTS server already running on port $PORT"
    curl -s http://localhost:$PORT/health | python3 -m json.tool 2>/dev/null || true
    exit 0
fi

# Activate venv and run
if [ ! -f "$SCRIPT_DIR/tts-venv/bin/python" ]; then
    echo -e "${RED}[!]${NC} TTS venv not found. Creating..."
    python3 -m venv tts-venv
    ./tts-venv/bin/pip install piper-tts
fi

echo -e "${GREEN}[+]${NC} Starting Piper TTS server on port $PORT..."
echo -e "${GREEN}[+]${NC} Model will be loaded once at startup for fast inference"
echo ""
exec "$SCRIPT_DIR/tts-venv/bin/python" "$SCRIPT_DIR/piper_tts_server.py" --port "$PORT" "$@"
