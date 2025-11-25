#!/bin/bash
################################################################################
# Jetson AGX Thor Setup Script for vLLM Deployment
# This script sets up the Jetson environment for running vLLM
################################################################################

set -e  # Exit on error

echo "================================================================================"
echo "Jetson AGX Thor - vLLM Setup Script"
echo "================================================================================"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_info() {
    echo -e "${YELLOW}[i]${NC} $1"
}

# Check if running on Jetson
print_info "Checking if running on Jetson platform..."
if [ -f /etc/nv_tegra_release ]; then
    print_status "Running on Jetson platform"
    cat /etc/nv_tegra_release
else
    print_info "Not running on Jetson (this is okay for preparation)"
fi

# Update system
print_info "Step 1/8: Updating system packages..."
sudo apt-get update
print_status "System updated"

# Install system dependencies
print_info "Step 2/8: Installing system dependencies..."
sudo apt-get install -y \
    python3-pip \
    python3-dev \
    build-essential \
    git \
    wget \
    curl \
    cmake \
    pkg-config \
    libhdf5-dev \
    libssl-dev \
    libffi-dev

print_status "System dependencies installed"

# Upgrade pip
print_info "Step 3/8: Upgrading pip..."
python3 -m pip install --upgrade pip
print_status "pip upgraded"

# Install PyTorch (Jetson-compatible version)
print_info "Step 4/8: Checking PyTorch installation..."
if python3 -c "import torch" 2>/dev/null; then
    TORCH_VERSION=$(python3 -c "import torch; print(torch.__version__)")
    print_status "PyTorch already installed: $TORCH_VERSION"
else
    print_info "Installing PyTorch for Jetson..."
    print_info "Please install PyTorch manually from NVIDIA's instructions:"
    print_info "https://forums.developer.nvidia.com/t/pytorch-for-jetson/72048"
    echo ""
    echo "Typical installation:"
    echo "  wget https://developer.download.nvidia.com/compute/redist/jp/v60/pytorch/torch-2.1.0a0+41361538.nv23.06-cp310-cp310-linux_aarch64.whl"
    echo "  pip3 install torch-2.1.0a0+41361538.nv23.06-cp310-cp310-linux_aarch64.whl"
    echo ""
    read -p "Press Enter after PyTorch is installed, or Ctrl+C to exit..."
fi

# Install transformers and dependencies
print_info "Step 5/8: Installing transformers and dependencies..."
pip3 install --upgrade \
    transformers \
    accelerate \
    sentencepiece \
    protobuf \
    huggingface-hub

print_status "Transformers installed"

# Install vLLM
print_info "Step 6/8: Installing vLLM..."
print_info "This may take several minutes..."

# Try to install vLLM
if pip3 install vllm; then
    print_status "vLLM installed successfully"
else
    print_error "vLLM installation failed"
    print_info "You may need to build vLLM from source for Jetson"
    print_info "See: https://github.com/vllm-project/vllm#build-from-source"
    echo ""
    echo "Quick source install:"
    echo "  git clone https://github.com/vllm-project/vllm.git"
    echo "  cd vllm"
    echo "  pip3 install -e ."
    echo ""
    read -p "Press Enter after vLLM is installed, or Ctrl+C to exit..."
fi

# Install additional utilities
print_info "Step 7/8: Installing additional utilities..."
pip3 install --upgrade \
    openai \
    requests \
    psutil \
    GPUtil

print_status "Additional utilities installed"

# Verify installation
print_info "Step 8/8: Verifying installation..."
echo ""

# Check Python version
PYTHON_VERSION=$(python3 --version)
print_status "Python: $PYTHON_VERSION"

# Check PyTorch
if python3 -c "import torch; print(f'PyTorch: {torch.__version__}, CUDA: {torch.cuda.is_available()}')" 2>/dev/null; then
    print_status "PyTorch is installed and working"
else
    print_error "PyTorch verification failed"
fi

# Check CUDA
if python3 -c "import torch; assert torch.cuda.is_available()" 2>/dev/null; then
    CUDA_VERSION=$(python3 -c "import torch; print(torch.version.cuda)")
    GPU_NAME=$(python3 -c "import torch; print(torch.cuda.get_device_name(0))")
    print_status "CUDA $CUDA_VERSION available"
    print_status "GPU: $GPU_NAME"
else
    print_error "CUDA not available - check NVIDIA drivers"
fi

# Check vLLM
if python3 -c "import vllm" 2>/dev/null; then
    VLLM_VERSION=$(python3 -c "import vllm; print(vllm.__version__)")
    print_status "vLLM $VLLM_VERSION installed"
else
    print_error "vLLM not available"
fi

# Check transformers
if python3 -c "import transformers" 2>/dev/null; then
    HF_VERSION=$(python3 -c "import transformers; print(transformers.__version__)")
    print_status "Transformers $HF_VERSION installed"
fi

# Create model directory
print_info "Creating model directory..."
mkdir -p ~/models
print_status "Model directory created at ~/models"

# Print summary
echo ""
echo "================================================================================"
echo "Setup Summary"
echo "================================================================================"
echo ""
echo "Installation complete! Here's what's installed:"
echo ""
python3 -c "
import sys
try:
    import torch
    print(f'✓ PyTorch {torch.__version__}')
    print(f'  - CUDA available: {torch.cuda.is_available()}')
    if torch.cuda.is_available():
        print(f'  - GPU: {torch.cuda.get_device_name(0)}')
except: print('✗ PyTorch not found')

try:
    import vllm
    print(f'✓ vLLM {vllm.__version__}')
except: print('✗ vLLM not found')

try:
    import transformers
    print(f'✓ Transformers {transformers.__version__}')
except: print('✗ Transformers not found')
"

echo ""
echo "================================================================================"
echo "Next Steps:"
echo "================================================================================"
echo ""
echo "1. Transfer your model to Jetson:"
echo "   scp -r ./deepseek-coder-v2-lite-instruct jetson@<ip>:~/models/"
echo ""
echo "2. Run the deployment script:"
echo "   bash jetson_deploy.sh"
echo ""
echo "3. Or manually start vLLM:"
echo "   vllm serve ~/models/deepseek-coder-v2-lite-instruct --quantization fp8"
echo ""
echo "================================================================================"
