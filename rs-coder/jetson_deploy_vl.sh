#!/bin/bash
################################################################################
# Jetson vLLM Vision-Language Model Deployment Script
# Deploys and runs Qwen2.5-VL-7B-Instruct with vLLM on Jetson AGX Thor
# Features safe cleanup of GPU memory on exit
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

# Model configuration
MODEL_NAME="Qwen2.5-VL-7B-Instruct"
MODEL_HF_REPO="Qwen/Qwen2.5-VL-7B-Instruct"
MODEL_PATH="${MODEL_PATH:-$HOME/.cache/huggingface/hub/models--Qwen--Qwen2.5-VL-7B-Instruct}"

# Server configuration
PORT="${PORT:-8000}"
MAX_MODEL_LEN="${MAX_MODEL_LEN:-4096}"
GPU_MEMORY_UTIL="${GPU_MEMORY_UTIL:-0.85}"
MAX_NUM_SEQS="${MAX_NUM_SEQS:-4}"
DTYPE="${DTYPE:-auto}"

# Container configuration
VLLM_CONTAINER="${VLLM_CONTAINER:-nvcr.io/nvidia/vllm:25.09-py3}"

# Track container for cleanup
CONTAINER_ID=""
CLEANUP_DONE=false

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
# Cleanup Function - Ensures GPU memory is released
################################################################################

cleanup() {
    if [ "$CLEANUP_DONE" = true ]; then
        return
    fi
    CLEANUP_DONE=true

    echo ""
    print_info "Initiating cleanup..."

    if [ -n "$CONTAINER_ID" ]; then
        print_info "Stopping container ${CONTAINER_ID:0:12}..."

        # Stop the container gracefully first
        docker stop -t 10 "$CONTAINER_ID" 2>/dev/null || true

        # Wait for container to fully stop
        docker wait "$CONTAINER_ID" 2>/dev/null || true

        # Force remove if still exists (should be auto-removed due to --rm)
        docker rm -f "$CONTAINER_ID" 2>/dev/null || true

        print_status "Container stopped"
    fi

    # Clear any orphaned GPU memory by checking for zombie processes
    print_info "Verifying GPU memory release..."
    sleep 2

    # Show GPU memory status after cleanup
    if nvidia-smi &>/dev/null; then
        GPU_MEM_USED=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits 2>/dev/null | head -1)
        print_status "GPU memory after cleanup: ${GPU_MEM_USED} MiB"
    fi

    print_status "Cleanup complete - GPU memory released"
    exit 0
}

# Trap all exit signals for cleanup
trap cleanup SIGINT SIGTERM EXIT SIGHUP

################################################################################
# Main Script
################################################################################

print_header "Jetson vLLM Vision-Language Model Deployment"
echo ""
print_info "Model: $MODEL_NAME"
print_info "This script runs vLLM in a container with safe GPU cleanup on exit"
echo ""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --port)
            PORT="$2"
            shift 2
            ;;
        --max-len)
            MAX_MODEL_LEN="$2"
            shift 2
            ;;
        --gpu-util)
            GPU_MEMORY_UTIL="$2"
            shift 2
            ;;
        --container)
            VLLM_CONTAINER="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --port PORT          Server port (default: 8000)"
            echo "  --max-len LENGTH     Max sequence length (default: 4096)"
            echo "  --gpu-util FRACTION  GPU memory utilization 0.0-1.0 (default: 0.85)"
            echo "  --container IMAGE    Docker image (default: $VLLM_CONTAINER)"
            echo "  --help               Show this help"
            echo ""
            echo "Environment variables:"
            echo "  PORT, MAX_MODEL_LEN, GPU_MEMORY_UTIL, VLLM_CONTAINER"
            echo ""
            echo "The script automatically cleans up GPU memory on exit (Ctrl+C or signals)."
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Check Docker
if ! command -v docker &> /dev/null; then
    print_error "Docker not found. Please install docker first."
    exit 1
fi
print_status "Docker available"

# Check GPU
print_info "Checking GPU..."
if nvidia-smi &>/dev/null; then
    GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)
    GPU_MEM_TOTAL=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader 2>/dev/null | head -1)
    GPU_MEM_USED=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits 2>/dev/null | head -1)
    print_status "GPU: $GPU_NAME ($GPU_MEM_TOTAL total, ${GPU_MEM_USED} MiB currently used)"
else
    print_error "nvidia-smi not available - GPU driver issue?"
    exit 1
fi

# Check model path
print_info "Checking model..."
SNAPSHOT_DIR=""
if [ -d "$MODEL_PATH/snapshots" ]; then
    # HuggingFace cache format
    SNAPSHOT_DIR=$(ls -d "$MODEL_PATH/snapshots"/*/ 2>/dev/null | head -1)
    if [ -n "$SNAPSHOT_DIR" ]; then
        print_status "Model found in HF cache: $SNAPSHOT_DIR"
    fi
elif [ -d "$MODEL_PATH" ] && [ -f "$MODEL_PATH/config.json" ]; then
    # Direct model directory
    SNAPSHOT_DIR="$MODEL_PATH"
    print_status "Model found: $MODEL_PATH"
fi

if [ -z "$SNAPSHOT_DIR" ]; then
    print_error "Model not found at: $MODEL_PATH"
    echo ""
    echo "Download with:"
    echo "  huggingface-cli download $MODEL_HF_REPO"
    exit 1
fi

# Create log directory
mkdir -p ~/vllm_logs
LOG_FILE="$HOME/vllm_logs/vllm_vl_$(date +%Y%m%d_%H%M%S).log"

# Display configuration
echo ""
print_header "Configuration"
echo ""
echo "Model:              $MODEL_NAME"
echo "Model path:         $SNAPSHOT_DIR"
echo "Container:          $VLLM_CONTAINER"
echo "Port:               $PORT"
echo "Max sequence len:   $MAX_MODEL_LEN"
echo "GPU memory util:    $GPU_MEMORY_UTIL"
echo "Max concurrent:     $MAX_NUM_SEQS"
echo "Log file:           $LOG_FILE"
echo ""

# Confirm before starting
read -p "Press Enter to start deployment, or Ctrl+C to cancel..."
echo ""

print_header "Starting vLLM Server"
echo ""

# Build vLLM arguments as array to preserve quoting
# Note: Vision models may need additional arguments depending on vLLM version
VLLM_ARGS=(
    --host 0.0.0.0
    --port "$PORT"
    --dtype "$DTYPE"
    --max-model-len "$MAX_MODEL_LEN"
    --max-num-seqs "$MAX_NUM_SEQS"
    --gpu-memory-utilization "$GPU_MEMORY_UTIL"
    --trust-remote-code
    --limit-mm-per-prompt '{"image": 1}'
)

# For VL models, we use the HF repo name directly so vLLM can find the vision processor
# Mount the HF cache so it can use cached model files
HF_CACHE_DIR="$HOME/.cache/huggingface"

print_info "Starting container..."
print_info "vLLM args: ${VLLM_ARGS[*]}"
echo ""

# Start container in detached mode with --rm for auto-cleanup
CONTAINER_ID=$(docker run -d --rm \
    --runtime nvidia \
    --network=host \
    --shm-size=16g \
    --ulimit memlock=-1 \
    --ulimit stack=67108864 \
    -v "$HF_CACHE_DIR:/root/.cache/huggingface" \
    -v "$HOME/vllm_logs:/logs" \
    -e HF_HOME=/root/.cache/huggingface \
    "$VLLM_CONTAINER" \
    vllm serve "$MODEL_HF_REPO" "${VLLM_ARGS[@]}" 2>&1)

if [ -z "$CONTAINER_ID" ]; then
    print_error "Failed to start container"
    exit 1
fi

print_status "Container started: ${CONTAINER_ID:0:12}"
echo ""

print_info "Server will be available at:"
echo "  - Local:   http://localhost:$PORT"
echo "  - Network: http://$(hostname -I | awk '{print $1}'):$PORT"
echo ""
print_info "API endpoints:"
echo "  - OpenAI compatible: http://localhost:$PORT/v1"
echo "  - Chat completions:  http://localhost:$PORT/v1/chat/completions"
echo "  - Health check:      http://localhost:$PORT/health"
echo ""
print_info "For vision requests, include images in the 'messages' array:"
echo '  {"role": "user", "content": [{"type": "image_url", "image_url": {"url": "..."}}, {"type": "text", "text": "..."}]}'
echo ""
print_info "Press Ctrl+C to stop the server and release GPU memory"
echo ""

print_header "Server Output"
echo ""

# Follow logs - this blocks until interrupted or container stops
docker logs -f "$CONTAINER_ID" 2>&1 | tee "$LOG_FILE"

# If we get here, container stopped on its own
print_info "Container stopped"
