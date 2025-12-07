#!/bin/bash
################################################################################
# Jetson vLLM Deployment Script
# Deploys and runs LLMs with vLLM on Jetson AGX Thor
# Supports multiple models: DeepSeek-Coder, Qwen2.5, Llama-3.1
# Supports both native venv and jetson-containers (Docker) deployment
################################################################################

set -e

# Colors (defined first for use in cleanup)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

################################################################################
# Model Presets - Add new models here
################################################################################
declare -A MODEL_PRESETS
declare -A MODEL_HF_REPOS
declare -A MODEL_MAX_LEN
declare -A MODEL_GPU_UTIL
declare -A MODEL_DESCRIPTION

# DeepSeek-Coder-V2-Lite (current default)
MODEL_PRESETS["deepseek-coder"]="deepseek-coder-v2-lite-instruct"
MODEL_HF_REPOS["deepseek-coder"]="deepseek-ai/DeepSeek-Coder-V2-Lite-Instruct"
MODEL_MAX_LEN["deepseek-coder"]=160000
MODEL_GPU_UTIL["deepseek-coder"]=0.5
MODEL_DESCRIPTION["deepseek-coder"]="DeepSeek-Coder-V2-Lite 16B - Fast code generation"

# Qwen2.5-72B-Instruct (recommended for complex tasks)
MODEL_PRESETS["qwen-72b"]="Qwen2.5-72B-Instruct"
MODEL_HF_REPOS["qwen-72b"]="Qwen/Qwen2.5-72B-Instruct"
MODEL_MAX_LEN["qwen-72b"]=32768
MODEL_GPU_UTIL["qwen-72b"]=0.9
MODEL_DESCRIPTION["qwen-72b"]="Qwen2.5-72B-Instruct - Best instruction following (72B)"

# Qwen2.5-Coder-32B-Instruct
MODEL_PRESETS["qwen-coder-32b"]="Qwen2.5-Coder-32B-Instruct"
MODEL_HF_REPOS["qwen-coder-32b"]="Qwen/Qwen2.5-Coder-32B-Instruct"
MODEL_MAX_LEN["qwen-coder-32b"]=65536
MODEL_GPU_UTIL["qwen-coder-32b"]=0.7
MODEL_DESCRIPTION["qwen-coder-32b"]="Qwen2.5-Coder-32B - Code-focused with good instruction following"

# Llama-3.1-70B-Instruct
MODEL_PRESETS["llama-70b"]="Meta-Llama-3.1-70B-Instruct"
MODEL_HF_REPOS["llama-70b"]="meta-llama/Llama-3.1-70B-Instruct"
MODEL_MAX_LEN["llama-70b"]=32768
MODEL_GPU_UTIL["llama-70b"]=0.9
MODEL_DESCRIPTION["llama-70b"]="Llama-3.1-70B-Instruct - Meta's flagship model"

# Qwen2.5-32B-Instruct (good balance)
MODEL_PRESETS["qwen-32b"]="Qwen2.5-32B-Instruct"
MODEL_HF_REPOS["qwen-32b"]="Qwen/Qwen2.5-32B-Instruct"
MODEL_MAX_LEN["qwen-32b"]=32768
MODEL_GPU_UTIL["qwen-32b"]=0.6
MODEL_DESCRIPTION["qwen-32b"]="Qwen2.5-32B-Instruct - Good balance of speed and capability"

# Models directory
MODELS_DIR="${MODELS_DIR:-$HOME/models}"

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
# Model Management Functions
################################################################################

list_models() {
    echo ""
    print_header "Available Model Presets"
    echo ""
    printf "%-20s %-50s\n" "PRESET" "DESCRIPTION"
    printf "%-20s %-50s\n" "------" "-----------"
    for preset in "${!MODEL_PRESETS[@]}"; do
        printf "%-20s %-50s\n" "$preset" "${MODEL_DESCRIPTION[$preset]}"
    done
    echo ""
    echo "Usage: $0 --preset <name>    (e.g., --preset qwen-72b)"
    echo "       $0 --preset <name> --download   (download if not present)"
    echo ""
}

download_model() {
    local preset=$1
    local hf_repo="${MODEL_HF_REPOS[$preset]}"
    local model_name="${MODEL_PRESETS[$preset]}"
    local model_path="$MODELS_DIR/$model_name"

    if [ -z "$hf_repo" ]; then
        print_error "Unknown preset: $preset"
        list_models
        exit 1
    fi

    print_header "Downloading Model: $preset"
    echo ""
    print_info "HuggingFace repo: $hf_repo"
    print_info "Local path: $model_path"
    echo ""

    # Create models directory
    mkdir -p "$MODELS_DIR"

    # Find huggingface CLI tool - can be 'huggingface-cli' or 'hf'
    HF_CLI=""
    HF_CMD_TYPE=""  # "huggingface-cli" or "hf" - affects command syntax

    # Helper to check and set CLI
    check_hf_cli() {
        local cli_path="$1"
        local cli_name="$2"
        if [ -x "$cli_path" ]; then
            HF_CLI="$cli_path"
            # Determine command type based on binary name
            if [[ "$cli_path" == */hf ]]; then
                HF_CMD_TYPE="hf"
            else
                HF_CMD_TYPE="huggingface-cli"
            fi
            return 0
        fi
        return 1
    }

    # 1. Check if huggingface-cli or hf is in PATH
    if command -v huggingface-cli &> /dev/null; then
        HF_CLI="$(command -v huggingface-cli)"
        HF_CMD_TYPE="huggingface-cli"
        print_status "Found huggingface-cli in PATH"
    elif command -v hf &> /dev/null; then
        HF_CLI="$(command -v hf)"
        HF_CMD_TYPE="hf"
        print_status "Found hf in PATH"
    # 2. Check inference venv
    elif check_hf_cli "$VENV_DIR/bin/huggingface-cli"; then
        print_status "Found huggingface-cli in inference venv"
    elif check_hf_cli "$VENV_DIR/bin/hf"; then
        print_status "Found hf in inference venv"
    # 3. Check ~/.local/bin
    elif check_hf_cli "$HOME/.local/bin/huggingface-cli"; then
        print_status "Found huggingface-cli in ~/.local/bin"
    elif check_hf_cli "$HOME/.local/bin/hf"; then
        print_status "Found hf in ~/.local/bin"
    # 4. Check pipx venv directly (newer versions use 'hf')
    elif check_hf_cli "$HOME/.local/share/pipx/venvs/huggingface-hub/bin/hf"; then
        print_status "Found hf in pipx venv"
    elif check_hf_cli "$HOME/.local/share/pipx/venvs/huggingface-hub/bin/huggingface-cli"; then
        print_status "Found huggingface-cli in pipx venv"
    # 5. Check common conda/mamba locations
    elif check_hf_cli "$HOME/miniforge3/bin/huggingface-cli"; then
        print_status "Found huggingface-cli in miniforge3"
    elif check_hf_cli "$HOME/miniconda3/bin/huggingface-cli"; then
        print_status "Found huggingface-cli in miniconda3"
    fi

    # If not found, try to find or install it
    if [ -z "$HF_CLI" ]; then
        print_info "HuggingFace CLI not found in standard locations..."

        # Search for it in pipx venvs
        if [ -d "$HOME/.local/share/pipx/venvs" ]; then
            # Try 'hf' first (newer), then 'huggingface-cli'
            for cli_name in hf huggingface-cli; do
                FOUND_CLI=$(find "$HOME/.local/share/pipx/venvs" -name "$cli_name" -type f -executable 2>/dev/null | head -1)
                if [ -n "$FOUND_CLI" ] && [ -x "$FOUND_CLI" ]; then
                    HF_CLI="$FOUND_CLI"
                    HF_CMD_TYPE="$cli_name"
                    print_status "Found $cli_name in pipx: $HF_CLI"
                    break
                fi
            done
        fi

        # If still not found, install it
        if [ -z "$HF_CLI" ]; then
            print_info "Installing huggingface_hub..."

            # Try pipx first (cleanest option)
            if command -v pipx &> /dev/null; then
                print_info "Installing via pipx..."
                pipx install huggingface_hub --force 2>/dev/null || pipx install huggingface_hub
                pipx ensurepath 2>/dev/null || true

                # Find the installed binary (prefer hf)
                for cli_name in hf huggingface-cli; do
                    if [ -x "$HOME/.local/bin/$cli_name" ]; then
                        HF_CLI="$HOME/.local/bin/$cli_name"
                        HF_CMD_TYPE="$cli_name"
                        break
                    fi
                    FOUND_CLI=$(find "$HOME/.local/share/pipx/venvs" -name "$cli_name" -type f -executable 2>/dev/null | head -1)
                    if [ -n "$FOUND_CLI" ]; then
                        HF_CLI="$FOUND_CLI"
                        HF_CMD_TYPE="$cli_name"
                        break
                    fi
                done
            # Try inference venv if it exists
            elif [ -d "$VENV_DIR" ]; then
                print_info "Installing in inference venv..."
                "$VENV_DIR/bin/pip" install -U huggingface_hub
                if [ -x "$VENV_DIR/bin/hf" ]; then
                    HF_CLI="$VENV_DIR/bin/hf"
                    HF_CMD_TYPE="hf"
                else
                    HF_CLI="$VENV_DIR/bin/huggingface-cli"
                    HF_CMD_TYPE="huggingface-cli"
                fi
            # Last resort: create a temp venv
            else
                print_info "Creating temporary venv for download tools..."
                TEMP_VENV="/tmp/hf-download-venv"
                python3 -m venv "$TEMP_VENV"
                "$TEMP_VENV/bin/pip" install -q huggingface_hub
                if [ -x "$TEMP_VENV/bin/hf" ]; then
                    HF_CLI="$TEMP_VENV/bin/hf"
                    HF_CMD_TYPE="hf"
                else
                    HF_CLI="$TEMP_VENV/bin/huggingface-cli"
                    HF_CMD_TYPE="huggingface-cli"
                fi
            fi
        fi

        # Final check
        if [ -z "$HF_CLI" ] || [ ! -x "$HF_CLI" ]; then
            print_error "Failed to find or install HuggingFace CLI"
            echo ""
            echo "Please install manually:"
            echo "  pipx install huggingface_hub --force"
            echo "  pipx ensurepath"
            echo "  # then restart your shell"
            exit 1
        fi
        print_status "HuggingFace CLI ready: $HF_CLI"
    fi

    # Check if already downloaded
    if [ -d "$model_path" ] && [ "$(ls -A $model_path 2>/dev/null)" ]; then
        print_info "Model already exists at $model_path"
        read -p "Re-download? (y/N): " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            print_status "Using existing model"
            return 0
        fi
    fi

    print_info "Downloading from HuggingFace (this may take a while)..."
    print_info "Using: $HF_CLI ($HF_CMD_TYPE)"

    # Enable fast transfer if hf_transfer is available
    export HF_HUB_ENABLE_HF_TRANSFER=1
    print_info "Fast transfer enabled (HF_HUB_ENABLE_HF_TRANSFER=1)"
    echo ""

    # For gated models (like Llama), user needs to be logged in
    if [[ "$hf_repo" == meta-llama/* ]]; then
        print_info "Note: Llama models require HuggingFace login and license acceptance"
        if [ "$HF_CMD_TYPE" = "hf" ]; then
            print_info "Run '$HF_CLI auth login' first if you haven't"
        else
            print_info "Run '$HF_CLI login' first if you haven't"
        fi
        echo ""
    fi

    # Download using appropriate command syntax
    # 'hf' uses: hf download REPO --local-dir PATH
    # 'huggingface-cli' uses: huggingface-cli download REPO --local-dir PATH
    if [ "$HF_CMD_TYPE" = "hf" ]; then
        "$HF_CLI" download "$hf_repo" \
            --local-dir "$model_path"
    else
        "$HF_CLI" download "$hf_repo" \
            --local-dir "$model_path" \
            --local-dir-use-symlinks False
    fi

    if [ $? -eq 0 ]; then
        print_status "Model downloaded successfully to: $model_path"
    else
        print_error "Download failed!"
        exit 1
    fi
}

get_model_path_from_preset() {
    local preset=$1
    local model_name="${MODEL_PRESETS[$preset]}"

    if [ -z "$model_name" ]; then
        print_error "Unknown preset: $preset"
        list_models
        exit 1
    fi

    echo "$MODELS_DIR/$model_name"
}

# Track container ID for cleanup
CONTAINER_ID=""
CLEANUP_DONE=false

cleanup() {
    if [ "$CLEANUP_DONE" = true ]; then
        return
    fi
    CLEANUP_DONE=true

    echo ""
    print_info "Shutting down..."

    if [ "$DEPLOY_MODE" = "container" ] && [ -n "$CONTAINER_ID" ]; then
        print_info "Stopping Docker container ${CONTAINER_ID:0:12}..."
        docker stop "$CONTAINER_ID" 2>/dev/null || true
        # Wait for container to fully stop and release GPU memory
        docker wait "$CONTAINER_ID" 2>/dev/null || true
        print_status "Container stopped and GPU memory released"
    fi

    # Deactivate venv if active
    if [ "$DEPLOY_MODE" = "venv" ]; then
        deactivate 2>/dev/null || true
    fi

    print_status "Cleanup complete"
    exit 0
}

# Trap signals for cleanup
trap cleanup SIGINT SIGTERM EXIT

# Deployment mode: "venv" or "container"
DEPLOY_MODE="${DEPLOY_MODE:-auto}"
# NGC vLLM container for Jetson Thor (JetPack 7.x / R38.x / CUDA 13.0)
VLLM_CONTAINER="${VLLM_CONTAINER:-nvcr.io/nvidia/vllm:25.09-py3}"

# Virtual environment configuration (for venv mode)
VENV_DIR="${VENV_DIR:-$HOME/inference-venv}"

# Default configuration (will be overridden by preset if specified)
MODEL_PRESET=""
MODEL_PATH=""
DO_DOWNLOAD=false
KV_CACHE_DTYPE="auto"  # Options: fp8, int8, auto
DTYPE="auto"  # Model precision: bfloat16, float16, auto
MAX_MODEL_LEN=""  # Will be set from preset or default
GPU_MEMORY_UTIL=""  # Will be set from preset or default
PORT=8000
MAX_NUM_SEQS=4

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --preset)
            MODEL_PRESET="$2"
            shift 2
            ;;
        --download)
            DO_DOWNLOAD=true
            shift
            ;;
        --list-models)
            list_models
            exit 0
            ;;
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
        --gpu-util)
            GPU_MEMORY_UTIL="$2"
            shift 2
            ;;
        --port)
            PORT="$2"
            shift 2
            ;;
        --mode)
            DEPLOY_MODE="$2"
            shift 2
            ;;
        --container)
            VLLM_CONTAINER="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [options]"
            echo ""
            echo "Model Selection (recommended):"
            echo "  --preset NAME          Use a model preset (see --list-models)"
            echo "  --download             Download model from HuggingFace if not present"
            echo "  --list-models          List available model presets"
            echo ""
            echo "Manual Model Path:"
            echo "  --model PATH           Path to model directory"
            echo ""
            echo "Server Options:"
            echo "  --kv-cache-dtype TYPE  KV cache quantization: fp8, int8, auto (default: auto)"
            echo "  --dtype TYPE           Model precision: bfloat16, float16, auto (default: auto)"
            echo "  --max-len LENGTH       Maximum sequence length (default: from preset)"
            echo "  --gpu-util FRACTION    GPU memory utilization 0.0-1.0 (default: from preset)"
            echo "  --port PORT            Server port (default: 8000)"
            echo "  --mode MODE            Deployment mode: venv, container, auto (default: auto)"
            echo "  --container IMAGE      Docker image for container mode"
            echo "  --help                 Show this help message"
            echo ""
            echo "Model Presets:"
            for preset in "${!MODEL_PRESETS[@]}"; do
                printf "  %-20s %s\n" "$preset" "${MODEL_DESCRIPTION[$preset]}"
            done
            echo ""
            echo "Examples:"
            echo "  $0 --preset qwen-72b --download       # Download & run Qwen2.5-72B"
            echo "  $0 --preset deepseek-coder            # Run DeepSeek-Coder (default)"
            echo "  $0 --preset llama-70b                 # Run Llama-3.1-70B"
            echo "  $0 --list-models                      # Show all available presets"
            echo "  $0 --model ~/my-model --max-len 8192  # Custom model path"
            echo "  $0 --max-len 8192 --port 8080         # Long context"
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

################################################################################
# Resolve Model Configuration
################################################################################

# If preset specified, resolve it
if [ -n "$MODEL_PRESET" ]; then
    if [ -z "${MODEL_PRESETS[$MODEL_PRESET]}" ]; then
        print_error "Unknown preset: $MODEL_PRESET"
        list_models
        exit 1
    fi

    # Get model path from preset (if not manually specified)
    if [ -z "$MODEL_PATH" ]; then
        MODEL_PATH=$(get_model_path_from_preset "$MODEL_PRESET")
    fi

    # Get defaults from preset (if not manually overridden)
    if [ -z "$MAX_MODEL_LEN" ]; then
        MAX_MODEL_LEN="${MODEL_MAX_LEN[$MODEL_PRESET]}"
    fi
    if [ -z "$GPU_MEMORY_UTIL" ]; then
        GPU_MEMORY_UTIL="${MODEL_GPU_UTIL[$MODEL_PRESET]}"
    fi

    print_info "Using preset: $MODEL_PRESET"
    print_info "  ${MODEL_DESCRIPTION[$MODEL_PRESET]}"

    # Download if requested
    if [ "$DO_DOWNLOAD" = true ]; then
        download_model "$MODEL_PRESET"
    fi
else
    # No preset - use defaults or manual path
    if [ -z "$MODEL_PATH" ]; then
        # Default to deepseek-coder preset
        MODEL_PRESET="deepseek-coder"
        MODEL_PATH=$(get_model_path_from_preset "$MODEL_PRESET")
        print_info "No model specified, using default: $MODEL_PRESET"
    fi
    if [ -z "$MAX_MODEL_LEN" ]; then
        MAX_MODEL_LEN=32768
    fi
    if [ -z "$GPU_MEMORY_UTIL" ]; then
        GPU_MEMORY_UTIL=0.9
    fi
fi

print_header "Jetson vLLM Deployment"

# Determine deployment mode
if [ "$DEPLOY_MODE" = "auto" ]; then
    # Check if vLLM is available in venv
    if [ -d "$VENV_DIR" ]; then
        source "$VENV_DIR/bin/activate"
        if python3 -c "import vllm" 2>/dev/null; then
            DEPLOY_MODE="venv"
            print_info "Auto-detected: vLLM available in venv, using venv mode"
        else
            deactivate 2>/dev/null || true
            DEPLOY_MODE="container"
            print_info "Auto-detected: vLLM not in venv, using container mode"
        fi
    else
        DEPLOY_MODE="container"
        print_info "Auto-detected: No venv found, using container mode"
    fi
fi

# Setup based on deployment mode
if [ "$DEPLOY_MODE" = "venv" ]; then
    print_info "Deployment mode: Virtual Environment"
    if [ -d "$VENV_DIR" ]; then
        source "$VENV_DIR/bin/activate"
        print_status "Activated venv at $VENV_DIR"
    else
        print_error "Virtual environment not found at $VENV_DIR"
        echo "Run jetson_setup.sh first, or use --mode container"
        exit 1
    fi
elif [ "$DEPLOY_MODE" = "container" ]; then
    print_info "Deployment mode: Docker Container (jetson-containers)"
    print_info "Container image: $VLLM_CONTAINER"
    # Check if docker is available
    if ! command -v docker &> /dev/null; then
        print_error "Docker not found. Please install docker first."
        exit 1
    fi
fi

# Check if model exists
print_info "Checking model path..."
if [ ! -d "$MODEL_PATH" ]; then
    print_error "Model not found at: $MODEL_PATH"
    echo ""
    if [ -n "$MODEL_PRESET" ]; then
        echo "To download this model, run:"
        echo "  $0 --preset $MODEL_PRESET --download"
        echo ""
        echo "Or download manually:"
        echo "  huggingface-cli download ${MODEL_HF_REPOS[$MODEL_PRESET]} --local-dir $MODEL_PATH"
    else
        echo "Please download the model first or specify a different path with --model"
        echo ""
        echo "Available presets (use --preset NAME --download):"
        for preset in "${!MODEL_PRESETS[@]}"; do
            printf "  %-20s %s\n" "$preset" "${MODEL_DESCRIPTION[$preset]}"
        done
    fi
    exit 1
fi
print_status "Model found at: $MODEL_PATH"

# Check GPU - use nvidia-smi for container mode, torch for venv mode
print_info "Checking GPU availability..."
if [ "$DEPLOY_MODE" = "container" ]; then
    # For container mode, just check nvidia-smi
    if nvidia-smi &>/dev/null; then
        GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)
        print_status "GPU: $GPU_NAME (nvidia-smi available)"
    else
        print_error "nvidia-smi not available - GPU driver issue?"
        exit 1
    fi
else
    # For venv mode, check torch CUDA
    if python3 -c "import torch; assert torch.cuda.is_available()" 2>/dev/null; then
        GPU_NAME=$(python3 -c "import torch; print(torch.cuda.get_device_name(0))")
        GPU_MEMORY=$(python3 -c "import torch; print(f'{torch.cuda.get_device_properties(0).total_memory / 1024**3:.1f}')")
        print_status "GPU: $GPU_NAME ($GPU_MEMORY GB)"
    else
        print_error "CUDA not available in venv!"
        print_info "Try: --mode container (uses jetson-containers docker image)"
        exit 1
    fi
fi

# Check vLLM (only for venv mode)
if [ "$DEPLOY_MODE" = "venv" ]; then
    print_info "Checking vLLM installation..."
    if python3 -c "import vllm" 2>/dev/null; then
        VLLM_VERSION=$(python3 -c "import vllm; print(vllm.__version__)")
        print_status "vLLM $VLLM_VERSION installed"
    else
        print_error "vLLM not installed in venv!"
        print_info "Try: --mode container (uses jetson-containers docker image)"
        exit 1
    fi
else
    print_info "vLLM will run inside container: $VLLM_CONTAINER"
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

# Build vLLM command arguments
VLLM_ARGS="--host 0.0.0.0"
VLLM_ARGS="$VLLM_ARGS --port $PORT"
VLLM_ARGS="$VLLM_ARGS --dtype $DTYPE"
VLLM_ARGS="$VLLM_ARGS --kv-cache-dtype $KV_CACHE_DTYPE"
VLLM_ARGS="$VLLM_ARGS --max-model-len $MAX_MODEL_LEN"
VLLM_ARGS="$VLLM_ARGS --max-num-seqs $MAX_NUM_SEQS"
VLLM_ARGS="$VLLM_ARGS --gpu-memory-utilization $GPU_MEMORY_UTIL"
VLLM_ARGS="$VLLM_ARGS --enable-prefix-caching"
VLLM_ARGS="$VLLM_ARGS --trust-remote-code"

if [ "$DEPLOY_MODE" = "container" ]; then
    # Container mode: mount model directory and run in docker
    MODEL_DIR=$(dirname "$MODEL_PATH")
    MODEL_BASENAME=$(basename "$MODEL_PATH")
    CONTAINER_MODEL_PATH="/models/$MODEL_BASENAME"

    # NGC container requires additional flags for Jetson Thor
    DOCKER_CMD="docker run --runtime nvidia -it --rm --network=host"
    DOCKER_CMD="$DOCKER_CMD --shm-size=16g"
    DOCKER_CMD="$DOCKER_CMD --ulimit memlock=-1"
    DOCKER_CMD="$DOCKER_CMD --ulimit stack=67108864"
    DOCKER_CMD="$DOCKER_CMD -v $MODEL_DIR:/models"
    DOCKER_CMD="$DOCKER_CMD -v $HOME/vllm_logs:/logs"
    DOCKER_CMD="$DOCKER_CMD -v $HOME/.cache/huggingface:/root/.cache/huggingface"
    DOCKER_CMD="$DOCKER_CMD $VLLM_CONTAINER"
    DOCKER_CMD="$DOCKER_CMD vllm serve $CONTAINER_MODEL_PATH $VLLM_ARGS"

    echo "Docker command:"
    echo "  $DOCKER_CMD"
else
    # Venv mode: run directly
    VLLM_CMD="vllm serve $MODEL_PATH $VLLM_ARGS"
    echo "Command: $VLLM_CMD"
fi
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

# Run vLLM
if [ "$DEPLOY_MODE" = "container" ]; then
    # Run container in detached mode to capture container ID for cleanup
    # Remove -it and add -d for detached mode
    DOCKER_CMD_DETACHED=$(echo "$DOCKER_CMD" | sed 's/-it //')
    DOCKER_CMD_DETACHED=$(echo "$DOCKER_CMD_DETACHED" | sed 's/--rm //')

    # Start container in detached mode
    CONTAINER_ID=$(docker run -d --rm \
        --runtime nvidia \
        --network=host \
        --shm-size=16g \
        --ulimit memlock=-1 \
        --ulimit stack=67108864 \
        -v "$MODEL_DIR:/models" \
        -v "$HOME/vllm_logs:/logs" \
        -v "$HOME/.cache/huggingface:/root/.cache/huggingface" \
        "$VLLM_CONTAINER" \
        vllm serve "$CONTAINER_MODEL_PATH" $VLLM_ARGS 2>&1)

    if [ -z "$CONTAINER_ID" ]; then
        print_error "Failed to start container"
        exit 1
    fi

    print_status "Container started: ${CONTAINER_ID:0:12}"
    print_info "Following container logs (Ctrl+C to stop)..."
    echo ""

    # Follow logs - this will block until container stops or we get interrupted
    docker logs -f "$CONTAINER_ID" 2>&1 | tee "$LOG_FILE"
else
    # Venv mode: run directly
    $VLLM_CMD 2>&1 | tee "$LOG_FILE"
fi
