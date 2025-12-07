#!/bin/bash
################################################################################
# Jetson vLLM Mixtral 8x7B FP8 Deployment Script
# Deploys and runs Mixtral-8x7B-Instruct-v0.1-FP8 with vLLM on Jetson AGX Thor
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
MODEL_NAME="Mixtral-8x7B-Instruct-v0.1-FP8"
MODEL_HF_REPO="neuralmagic/Mixtral-8x7B-Instruct-v0.1-FP8"

# Server configuration
PORT="${PORT:-8000}"
MAX_MODEL_LEN="${MAX_MODEL_LEN:-8192}"
GPU_MEMORY_UTIL="${GPU_MEMORY_UTIL:-0.90}"
MAX_NUM_SEQS="${MAX_NUM_SEQS:-8}"

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

    # Show memory status after cleanup
    if nvidia-smi &>/dev/null; then
        GPU_MEM_USED=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits 2>/dev/null | head -1)
        if [[ "$GPU_MEM_USED" == *"N/A"* ]] || [[ -z "$GPU_MEM_USED" ]]; then
            # Unified memory - show system available memory
            SYS_MEM_AVAIL_KB=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
            SYS_MEM_AVAIL_GB=$((SYS_MEM_AVAIL_KB / 1024 / 1024))
            print_status "System memory available: ${SYS_MEM_AVAIL_GB} GB"
        else
            print_status "GPU memory after cleanup: ${GPU_MEM_USED} MiB"
        fi
    fi

    print_status "Cleanup complete - GPU memory released"
    exit 0
}

# Trap all exit signals for cleanup
trap cleanup SIGINT SIGTERM EXIT SIGHUP

################################################################################
# Main Script
################################################################################

print_header "Jetson vLLM Mixtral 8x7B FP8 Deployment"
echo ""
print_info "Model: $MODEL_NAME"
print_info "License: Apache 2.0 (commercial use permitted)"
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
        --max-seqs)
            MAX_NUM_SEQS="$2"
            shift 2
            ;;
        --container)
            VLLM_CONTAINER="$2"
            shift 2
            ;;
        --download-only)
            DOWNLOAD_ONLY=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --port PORT          Server port (default: 8000)"
            echo "  --max-len LENGTH     Max sequence length (default: 8192)"
            echo "  --max-seqs NUM       Max concurrent sequences (default: 8)"
            echo "  --gpu-util FRACTION  GPU memory utilization 0.0-1.0 (default: 0.90)"
            echo "  --container IMAGE    Docker image (default: $VLLM_CONTAINER)"
            echo "  --download-only      Download model and exit"
            echo "  --help               Show this help"
            echo ""
            echo "Environment variables:"
            echo "  PORT, MAX_MODEL_LEN, MAX_NUM_SEQS, GPU_MEMORY_UTIL, VLLM_CONTAINER"
            echo ""
            echo "Memory requirements:"
            echo "  FP8 Mixtral 8x7B requires ~50GB VRAM (fits on 128GB Thor)"
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

    # Jetson Thor uses unified memory - nvidia-smi returns [N/A]
    if [[ "$GPU_MEM_TOTAL" == *"N/A"* ]] || [[ -z "$GPU_MEM_TOTAL" ]]; then
        # Get system memory instead (unified memory architecture)
        SYS_MEM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
        SYS_MEM_GB=$((SYS_MEM_KB / 1024 / 1024))
        SYS_MEM_AVAIL_KB=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
        SYS_MEM_AVAIL_GB=$((SYS_MEM_AVAIL_KB / 1024 / 1024))
        print_status "GPU: $GPU_NAME (unified memory: ${SYS_MEM_GB}GB total, ${SYS_MEM_AVAIL_GB}GB available)"

        # Warn if not enough memory (need ~50GB for FP8 Mixtral)
        if [ "$SYS_MEM_GB" -lt 60 ]; then
            print_error "Warning: Mixtral 8x7B FP8 requires ~50GB memory. Your system has ${SYS_MEM_GB}GB."
            print_info "Consider using INT4 AWQ quantization instead (hugging-quants/Mixtral-8x7B-Instruct-v0.1-AWQ-INT4)"
        fi
    else
        GPU_MEM_USED=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits 2>/dev/null | head -1)
        GPU_MEM_TOTAL_MB=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -1)
        print_status "GPU: $GPU_NAME ($GPU_MEM_TOTAL total, ${GPU_MEM_USED} MiB currently used)"

        # Warn if not enough memory
        if [ "$GPU_MEM_TOTAL_MB" -lt 60000 ]; then
            print_error "Warning: Mixtral 8x7B FP8 requires ~50GB VRAM. Your GPU has ${GPU_MEM_TOTAL}."
            print_info "Consider using INT4 AWQ quantization instead (hugging-quants/Mixtral-8x7B-Instruct-v0.1-AWQ-INT4)"
        fi
    fi
else
    print_error "nvidia-smi not available - GPU driver issue?"
    exit 1
fi

# Check/download model
HF_CACHE_DIR="$HOME/.cache/huggingface"
MODEL_CACHE_PATH="$HF_CACHE_DIR/hub/models--neuralmagic--Mixtral-8x7B-Instruct-v0.1-FP8"

print_info "Checking for model in cache..."
if [ -d "$MODEL_CACHE_PATH/snapshots" ]; then
    SNAPSHOT_DIR=$(ls -d "$MODEL_CACHE_PATH/snapshots"/*/ 2>/dev/null | head -1)
    if [ -n "$SNAPSHOT_DIR" ]; then
        print_status "Model found in cache: $SNAPSHOT_DIR"
    fi
else
    print_info "Model not found in cache. Will be downloaded on first run."
    print_info "This may take a while (~50GB download)..."
    echo ""

    # Optionally pre-download the model
    if [ "$DOWNLOAD_ONLY" = true ]; then
        print_info "Downloading model..."
        if command -v huggingface-cli &> /dev/null; then
            huggingface-cli download "$MODEL_HF_REPO"
            print_status "Model downloaded successfully"
            exit 0
        else
            print_error "huggingface-cli not found. Install with: pip install huggingface_hub"
            print_info "Alternatively, the model will download automatically when vLLM starts."
            exit 1
        fi
    fi
fi

if [ "$DOWNLOAD_ONLY" = true ]; then
    print_status "Model already downloaded"
    exit 0
fi

# Create log directory
mkdir -p ~/vllm_logs
LOG_FILE="$HOME/vllm_logs/vllm_mixtral_$(date +%Y%m%d_%H%M%S).log"

# Display configuration
echo ""
print_header "Configuration"
echo ""
echo "Model:              $MODEL_NAME"
echo "HuggingFace repo:   $MODEL_HF_REPO"
echo "Container:          $VLLM_CONTAINER"
echo "Port:               $PORT"
echo "Max sequence len:   $MAX_MODEL_LEN"
echo "Max concurrent:     $MAX_NUM_SEQS"
echo "GPU memory util:    $GPU_MEMORY_UTIL"
echo "Log file:           $LOG_FILE"
echo ""

# Confirm before starting
read -p "Press Enter to start deployment, or Ctrl+C to cancel..."
echo ""

print_header "Starting vLLM Server"
echo ""

# Build vLLM arguments
# FP8 models are loaded natively by vLLM without extra quantization flags
VLLM_ARGS=(
    --host 0.0.0.0
    --port "$PORT"
    --max-model-len "$MAX_MODEL_LEN"
    --max-num-seqs "$MAX_NUM_SEQS"
    --gpu-memory-utilization "$GPU_MEMORY_UTIL"
    --trust-remote-code
    --enforce-eager
)

print_info "Starting container..."
print_info "vLLM args: ${VLLM_ARGS[*]}"
echo ""

# Start container in detached mode with --rm for auto-cleanup
CONTAINER_ID=$(docker run -d --rm \
    --runtime nvidia \
    --network=host \
    --shm-size=32g \
    --ulimit memlock=-1 \
    --ulimit stack=67108864 \
    -v "$HF_CACHE_DIR:/root/.cache/huggingface" \
    -v "$HOME/vllm_logs:/logs" \
    -e HF_HOME=/root/.cache/huggingface \
    -e VLLM_ATTENTION_BACKEND=FLASHINFER \
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
print_info "Example usage:"
echo '  curl http://localhost:8000/v1/chat/completions \'
echo '    -H "Content-Type: application/json" \'
echo '    -d '\''{"model": "neuralmagic/Mixtral-8x7B-Instruct-v0.1-FP8",'
echo '          "messages": [{"role": "user", "content": "Hello!"}]}'\'
echo ""
print_info "Press Ctrl+C to stop the server and release GPU memory"
echo ""

print_header "Server Output"
echo ""

# Follow logs - this blocks until interrupted or container stops
docker logs -f "$CONTAINER_ID" 2>&1 | tee "$LOG_FILE"

# If we get here, container stopped on its own
print_info "Container stopped"
