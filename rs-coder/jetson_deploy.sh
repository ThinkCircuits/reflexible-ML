#!/bin/bash
################################################################################
# Jetson vLLM Deployment Script
# Deploys and runs DeepSeek-Coder-V2-Lite with vLLM runtime quantization
################################################################################

set -e

# Configuration
MODEL_NAME="deepseek-coder-v2-lite-instruct"
MODEL_PATH="$HOME/models/$MODEL_NAME"
KV_CACHE_DTYPE="fp8"  # Options: fp8, int8, auto
DTYPE="bfloat16"  # Model precision: bfloat16, float16, auto
MAX_MODEL_LEN=4096
GPU_MEMORY_UTIL=0.9
PORT=8000
MAX_NUM_SEQS=4

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --model)
            MODEL_PATH="$2"
            shift 2
            ;;
        --kv-cache-dtype)
            KV_CACHE_DTYPE="$2"
            shift 2
            ;;
        --dtype)
            DTYPE="$2"
            shift 2
            ;;
        --max-len)
            MAX_MODEL_LEN="$2"
            shift 2
            ;;
        --port)
            PORT="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --model PATH           Path to model (default: ~/models/$MODEL_NAME)"
            echo "  --kv-cache-dtype TYPE  KV cache quantization: fp8, int8, auto (default: fp8)"
            echo "  --dtype TYPE           Model precision: bfloat16, float16, auto (default: bfloat16)"
            echo "  --max-len LENGTH       Maximum sequence length (default: 4096)"
            echo "  --port PORT            Server port (default: 8000)"
            echo "  --help                 Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                                    # Use defaults (BF16 + FP8 KV cache)"
            echo "  $0 --kv-cache-dtype int8              # Use INT8 KV cache"
            echo "  $0 --max-len 8192 --port 8080         # Long context"
            echo "  $0 --dtype float16                    # Use FP16 instead of BF16"
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

print_header "Jetson vLLM Deployment"

# Check if model exists
print_info "Checking model path..."
if [ ! -d "$MODEL_PATH" ]; then
    print_error "Model not found at: $MODEL_PATH"
    echo ""
    echo "Please transfer your model first:"
    echo "  scp -r ./deepseek-coder-v2-lite-instruct jetson@<ip>:~/models/"
    echo ""
    echo "Or specify a different path with --model"
    exit 1
fi
print_status "Model found at: $MODEL_PATH"

# Check GPU
print_info "Checking GPU availability..."
if python3 -c "import torch; assert torch.cuda.is_available()" 2>/dev/null; then
    GPU_NAME=$(python3 -c "import torch; print(torch.cuda.get_device_name(0))")
    GPU_MEMORY=$(python3 -c "import torch; print(f'{torch.cuda.get_device_properties(0).total_memory / 1024**3:.1f}')")
    print_status "GPU: $GPU_NAME ($GPU_MEMORY GB)"
else
    print_error "CUDA not available!"
    exit 1
fi

# Check vLLM
print_info "Checking vLLM installation..."
if python3 -c "import vllm" 2>/dev/null; then
    VLLM_VERSION=$(python3 -c "import vllm; print(vllm.__version__)")
    print_status "vLLM $VLLM_VERSION installed"
else
    print_error "vLLM not installed!"
    echo "Please run: bash jetson_setup.sh"
    exit 1
fi

# Display configuration
echo ""
print_header "Deployment Configuration"
echo ""
echo "Model:              $MODEL_PATH"
echo "Model dtype:        $DTYPE"
echo "KV cache dtype:     $KV_CACHE_DTYPE"
echo "Max sequence len:   $MAX_MODEL_LEN"
echo "Max num seqs:       $MAX_NUM_SEQS"
echo "GPU memory util:    $GPU_MEMORY_UTIL"
echo "Server port:        $PORT"
echo ""

# Estimate memory usage
echo "Estimated memory usage:"
if [ "$KV_CACHE_DTYPE" = "fp8" ]; then
    if [ "$MAX_MODEL_LEN" -le 2048 ]; then
        echo "  - Model weights (~$DTYPE): ~30 GB"
        echo "  - KV cache (FP8):          ~2 GB"
        echo "  - Total:                   ~32 GB"
    elif [ "$MAX_MODEL_LEN" -le 4096 ]; then
        echo "  - Model weights (~$DTYPE): ~30 GB"
        echo "  - KV cache (FP8):          ~4 GB"
        echo "  - Total:                   ~34 GB"
    else
        echo "  - Model weights (~$DTYPE): ~30 GB"
        echo "  - KV cache (FP8):          ~8 GB"
        echo "  - Total:                   ~38 GB"
    fi
elif [ "$KV_CACHE_DTYPE" = "int8" ]; then
    echo "  - Model weights (~$DTYPE): ~30 GB"
    echo "  - KV cache (INT8):         ~2-4 GB"
    echo "  - Total:                   ~32-34 GB"
else
    echo "  - Model weights (~$DTYPE): ~30 GB"
    echo "  - KV cache (auto):         ~4-8 GB"
    echo "  - Total:                   ~34-38 GB"
fi
echo ""

read -p "Press Enter to start deployment, or Ctrl+C to cancel..."

# Create log directory
mkdir -p ~/vllm_logs
LOG_FILE="$HOME/vllm_logs/vllm_$(date +%Y%m%d_%H%M%S).log"

print_info "Starting vLLM server..."
print_info "Log file: $LOG_FILE"
echo ""

# Build vLLM command
VLLM_CMD="vllm serve $MODEL_PATH"
VLLM_CMD="$VLLM_CMD --host 0.0.0.0"
VLLM_CMD="$VLLM_CMD --port $PORT"
VLLM_CMD="$VLLM_CMD --dtype $DTYPE"
VLLM_CMD="$VLLM_CMD --kv-cache-dtype $KV_CACHE_DTYPE"
VLLM_CMD="$VLLM_CMD --max-model-len $MAX_MODEL_LEN"
VLLM_CMD="$VLLM_CMD --max-num-seqs $MAX_NUM_SEQS"
VLLM_CMD="$VLLM_CMD --gpu-memory-utilization $GPU_MEMORY_UTIL"
VLLM_CMD="$VLLM_CMD --enable-prefix-caching"
VLLM_CMD="$VLLM_CMD --trust-remote-code"

echo "Command: $VLLM_CMD"
echo ""

print_header "vLLM Server Starting"
echo ""
print_info "Server will be available at:"
echo "  - Local:  http://localhost:$PORT"
echo "  - Network: http://$(hostname -I | awk '{print $1}'):$PORT"
echo ""
print_info "API endpoints:"
echo "  - OpenAI compatible: http://localhost:$PORT/v1"
echo "  - Health check:      http://localhost:$PORT/health"
echo ""
print_info "Press Ctrl+C to stop the server"
echo ""
print_header "Server Output"
echo ""

# Run vLLM (this will block)
$VLLM_CMD 2>&1 | tee "$LOG_FILE"
