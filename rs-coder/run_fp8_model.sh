#!/bin/bash
# Simple script to run DeepSeek FP8 model with vLLM and prefix caching

set -e

# Virtual environment configuration
VENV_DIR="${VENV_DIR:-$HOME/inference-venv}"

# Activate virtual environment
if [ -d "$VENV_DIR" ]; then
    echo "Activating inference virtual environment..."
    source "$VENV_DIR/bin/activate"
else
    echo "Warning: Virtual environment not found at $VENV_DIR"
    echo "Run jetson_setup.sh first, or set VENV_DIR to your venv path"
    exit 1
fi

# Configuration
MODEL_PATH="${MODEL_PATH:-./deepseek-coder-v2-lite-instruct-fp8}"
HOST="${HOST:-0.0.0.0}"
PORT="${PORT:-8000}"
MAX_MODEL_LEN="${MAX_MODEL_LEN:-8192}"
GPU_MEMORY_UTIL="${GPU_MEMORY_UTIL:-0.9}"
MAX_NUM_SEQS="${MAX_NUM_SEQS:-4}"

echo "========================================================================"
echo "Starting vLLM with FP8 Quantized DeepSeek Model"
echo "========================================================================"
echo ""
echo "Configuration:"
echo "  Model:              $MODEL_PATH"
echo "  Host:               $HOST"
echo "  Port:               $PORT"
echo "  Max Context Length: $MAX_MODEL_LEN"
echo "  GPU Memory Util:    $GPU_MEMORY_UTIL"
echo "  Max Sequences:      $MAX_NUM_SEQS"
echo "  Prefix Caching:     ENABLED"
echo "  Quantization:       FP8"
echo ""
echo "========================================================================"
echo ""

# Check if model exists
if [ ! -d "$MODEL_PATH" ]; then
    echo "Error: Model not found at $MODEL_PATH"
    echo "Please ensure the FP8 quantized model is available."
    exit 1
fi

# Run vLLM server
vllm serve "$MODEL_PATH" \
    --host "$HOST" \
    --port "$PORT" \
    --max-model-len "$MAX_MODEL_LEN" \
    --gpu-memory-utilization "$GPU_MEMORY_UTIL" \
    --max-num-seqs "$MAX_NUM_SEQS" \
    --enable-prefix-caching \
    --trust-remote-code
