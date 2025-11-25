#!/bin/bash
# Setup dual virtual environments for quantization and deployment

set -e

echo "================================================================================"
echo "Dual Virtual Environment Setup"
echo "================================================================================"
echo ""
echo "Creating two virtual environments:"
echo "  1. venv-quantize: For FP8 quantization (torch 2.7-2.8)"
echo "  2. Current environment: For vLLM deployment (torch 2.9.0)"
echo ""

# Create quantization venv
echo "Creating venv-quantize..."
python3 -m venv venv-quantize

# Activate and install quantization dependencies
echo "Installing quantization dependencies (torch 2.8.0 + llmcompressor)..."
source venv-quantize/bin/activate

# Install specific torch version for llmcompressor
pip install --upgrade pip
pip install torch==2.8.0 torchvision==0.23.0 torchaudio==2.8.0
pip install transformers accelerate
pip install llmcompressor[transformers]

deactivate

echo ""
echo "================================================================================"
echo "Setup Complete!"
echo "================================================================================"
echo ""
echo "Two environments created:"
echo ""
echo "1. QUANTIZATION ENVIRONMENT (venv-quantize):"
echo "   - torch 2.8.0"
echo "   - llmcompressor"
echo "   - Use this to quantize models"
echo ""
echo "   Activate with:"
echo "     source venv-quantize/bin/activate"
echo "     python3 quantize_fp8_llmcompressor.py"
echo "     deactivate"
echo ""
echo "2. VLLM ENVIRONMENT (current/global):"
echo "   - torch 2.9.0"
echo "   - vLLM 0.11.2"
echo "   - Use this to run vLLM server"
echo ""
echo "   Run with:"
echo "     vllm serve ./deepseek-fp8 --quantization fp8"
echo ""
echo "================================================================================"
echo ""
echo "Quick workflow:"
echo ""
echo "# Step 1: Quantize (in venv-quantize)"
echo "source venv-quantize/bin/activate"
echo "python3 quantize_fp8_llmcompressor.py"
echo "deactivate"
echo ""
echo "# Step 2: Deploy (in main environment)"
echo "vllm serve ./deepseek-coder-v2-lite-instruct-fp8 --quantization fp8"
echo ""
echo "================================================================================"
