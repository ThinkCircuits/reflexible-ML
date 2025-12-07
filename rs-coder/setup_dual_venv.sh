#!/bin/bash
# Setup dual virtual environments for quantization and deployment

set -e

# Virtual environment paths
QUANTIZE_VENV="${QUANTIZE_VENV:-./venv-quantize}"
INFERENCE_VENV="${INFERENCE_VENV:-$HOME/inference-venv}"

echo "================================================================================"
echo "Dual Virtual Environment Setup"
echo "================================================================================"
echo ""
echo "Creating two virtual environments:"
echo "  1. $QUANTIZE_VENV: For FP8 quantization (torch 2.7-2.8)"
echo "  2. $INFERENCE_VENV: For vLLM deployment (torch 2.9.0)"
echo ""

# Create quantization venv
echo "Creating quantization venv at $QUANTIZE_VENV..."
python3 -m venv "$QUANTIZE_VENV"

# Activate and install quantization dependencies
echo "Installing quantization dependencies (torch 2.8.0 + llmcompressor)..."
source "$QUANTIZE_VENV/bin/activate"

# Install specific torch version for llmcompressor
pip install --upgrade pip
pip install torch==2.8.0 torchvision==0.23.0 torchaudio==2.8.0
pip install transformers accelerate
pip install llmcompressor[transformers]

deactivate

# Create inference venv
echo ""
echo "Creating inference venv at $INFERENCE_VENV..."
python3 -m venv "$INFERENCE_VENV"

# Activate and install inference dependencies
echo "Installing inference dependencies (torch 2.9.0 + vLLM)..."
source "$INFERENCE_VENV/bin/activate"

pip install --upgrade pip
pip install torch torchvision torchaudio
pip install transformers accelerate
pip install vllm
pip install openai requests psutil GPUtil

deactivate

echo ""
echo "================================================================================"
echo "Setup Complete!"
echo "================================================================================"
echo ""
echo "Two environments created:"
echo ""
echo "1. QUANTIZATION ENVIRONMENT ($QUANTIZE_VENV):"
echo "   - torch 2.8.0"
echo "   - llmcompressor"
echo "   - Use this to quantize models"
echo ""
echo "   Activate with:"
echo "     source $QUANTIZE_VENV/bin/activate"
echo "     python3 quantize_fp8_llmcompressor.py"
echo "     deactivate"
echo ""
echo "2. INFERENCE ENVIRONMENT ($INFERENCE_VENV):"
echo "   - torch 2.9.0"
echo "   - vLLM"
echo "   - Use this to run vLLM server"
echo ""
echo "   Activate with:"
echo "     source $INFERENCE_VENV/bin/activate"
echo "     vllm serve ./deepseek-fp8 --quantization fp8"
echo ""
echo "   Or run scripts directly (they auto-activate):"
echo "     bash run_fp8_model.sh"
echo "     bash jetson_deploy.sh"
echo ""
echo "================================================================================"
echo ""
echo "Quick workflow:"
echo ""
echo "# Step 1: Quantize (in quantize venv)"
echo "source $QUANTIZE_VENV/bin/activate"
echo "python3 quantize_fp8_llmcompressor.py"
echo "deactivate"
echo ""
echo "# Step 2: Deploy (in inference venv)"
echo "source $INFERENCE_VENV/bin/activate"
echo "vllm serve ./deepseek-coder-v2-lite-instruct-fp8 --quantization fp8"
echo ""
echo "================================================================================"
