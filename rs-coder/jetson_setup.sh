#!/bin/bash
################################################################################
# Jetson AGX Thor Setup Script for vLLM Deployment
# This script sets up the Jetson environment for running vLLM
################################################################################

set -e  # Exit on error

echo "================================================================================"
echo "Jetson AGX Thor - vLLM Setup Script"
echo "================================================================================"

# Virtual environment configuration
VENV_DIR="${VENV_DIR:-$HOME/inference-venv}"

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

# Create virtual environment
print_info "Step 3/9: Creating virtual environment..."
if [ ! -d "$VENV_DIR" ]; then
    python3 -m venv "$VENV_DIR"
    print_status "Virtual environment created at $VENV_DIR"
else
    print_info "Virtual environment already exists at $VENV_DIR"
fi

# Activate virtual environment
print_info "Activating virtual environment..."
source "$VENV_DIR/bin/activate"
print_status "Virtual environment activated"

# Upgrade pip
print_info "Step 4/9: Upgrading pip..."
python3 -m pip install --upgrade pip
print_status "pip upgraded"

# Install PyTorch (Jetson-compatible version with CUDA)
print_info "Step 5/9: Checking PyTorch installation..."

# Check if PyTorch with CUDA is installed
PYTORCH_CUDA_OK=false
if python3 -c "import torch; assert torch.cuda.is_available()" 2>/dev/null; then
    TORCH_VERSION=$(python3 -c "import torch; print(torch.__version__)")
    print_status "PyTorch with CUDA already installed: $TORCH_VERSION"
    PYTORCH_CUDA_OK=true
elif python3 -c "import torch" 2>/dev/null; then
    TORCH_VERSION=$(python3 -c "import torch; print(torch.__version__)")
    print_error "PyTorch $TORCH_VERSION is installed but WITHOUT CUDA support!"
    print_info "Will need to reinstall with CUDA support..."
fi

if [ "$PYTORCH_CUDA_OK" = false ]; then
    print_info "Installing PyTorch with CUDA for Jetson..."

    # Check if this is a Jetson device
    if [ -f /etc/nv_tegra_release ]; then
        print_info "Detected Jetson platform - installing PyTorch from Jetson AI Lab..."
        print_info "See: https://forums.developer.nvidia.com/t/pytorch-for-jetson/72048"
        echo ""

        # Try the Jetson AI Lab pip index first (JetPack 6.2+)
        print_info "Attempting install from Jetson AI Lab PyPI (JetPack 6.2+)..."
        if pip install torch torchvision --index-url=https://pypi.jetson-ai-lab.dev/jp6/cu126 2>/dev/null; then
            print_status "PyTorch installed from Jetson AI Lab"
        else
            # Fallback to direct NVIDIA wheel (JetPack 6.0/6.1)
            print_info "Jetson AI Lab install failed, trying NVIDIA wheel for JetPack 6.0/6.1..."
            pip install --no-cache https://developer.download.nvidia.com/compute/redist/jp/v61/pytorch/torch-2.5.0a0+872d972e41.nv24.08.17622132-cp310-cp310-linux_aarch64.whl || {
                print_error "Automatic PyTorch install failed"
                echo ""
                echo "Please install manually. Check your JetPack version:"
                echo "  cat /etc/nv_tegra_release"
                echo ""
                echo "Then visit: https://forums.developer.nvidia.com/t/pytorch-for-jetson/72048"
                echo ""
                read -p "Press Enter after PyTorch with CUDA is installed, or Ctrl+C to exit..."
            }
        fi
    else
        # Non-Jetson Linux - install PyTorch with CUDA from pip
        print_info "Installing PyTorch with CUDA support..."
        pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121
    fi

    # Verify CUDA is now available
    if python3 -c "import torch; assert torch.cuda.is_available()" 2>/dev/null; then
        print_status "PyTorch with CUDA installed successfully"
    else
        print_error "PyTorch CUDA still not available after installation"
        print_info "Please check your NVIDIA drivers and CUDA installation"
    fi
fi

# Install transformers and dependencies
print_info "Step 6/9: Installing transformers and dependencies..."
pip install --upgrade \
    transformers \
    accelerate \
    sentencepiece \
    protobuf \
    huggingface-hub

print_status "Transformers installed"

# Install vLLM
print_info "Step 7/9: Installing vLLM..."
print_info "This may take several minutes..."

# Check if this is a Jetson device - recommend container approach
if [ -f /etc/nv_tegra_release ]; then
    print_info "On Jetson, the recommended approach is using jetson-containers (NVIDIA-supported)"
    print_info "See: https://github.com/dusty-nv/jetson-containers"
    echo ""
    echo "Option 1: Use jetson-containers (RECOMMENDED for Jetson)"
    echo "  git clone https://github.com/dusty-nv/jetson-containers"
    echo "  bash jetson-containers/install.sh"
    echo "  jetson-containers run \$(autotag vllm)"
    echo ""
    echo "  Or run directly with docker:"
    echo "  sudo docker run --runtime nvidia -it --rm --network=host \\"
    echo "    -v ~/models:/models \\"
    echo "    dustynv/vllm:0.8.6-r36.4.0-cu128-24.04"
    echo ""
    echo "Option 2: Try pip install (may not work on all Jetson configs)"
    echo ""
    read -p "Try pip install anyway? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        # Try pip install from Jetson AI Lab first
        print_info "Attempting vLLM install from Jetson AI Lab PyPI..."
        if pip install vllm --index-url=https://pypi.jetson-ai-lab.dev/jp6/cu126 2>/dev/null; then
            print_status "vLLM installed from Jetson AI Lab"
        elif pip install vllm; then
            print_status "vLLM installed from PyPI"
        else
            print_error "vLLM pip installation failed"
            print_info "Please use jetson-containers instead (see above)"
        fi
    else
        print_info "Skipping vLLM pip install - use jetson-containers instead"
    fi
else
    # Non-Jetson Linux - standard pip install
    if pip install vllm; then
        print_status "vLLM installed successfully"
    else
        print_error "vLLM installation failed"
        print_info "See: https://github.com/vllm-project/vllm#build-from-source"
        echo ""
        echo "Quick source install:"
        echo "  git clone https://github.com/vllm-project/vllm.git"
        echo "  cd vllm"
        echo "  pip install -e ."
        echo ""
        read -p "Press Enter after vLLM is installed, or Ctrl+C to exit..."
    fi
fi

# Install additional utilities
print_info "Step 8/9: Installing additional utilities..."
pip install --upgrade \
    openai \
    requests \
    psutil \
    GPUtil

print_status "Additional utilities installed"

# Verify installation
print_info "Step 9/9: Verifying installation..."
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
echo "Virtual environment location: $VENV_DIR"
echo ""
echo "1. Transfer your model to Jetson:"
echo "   scp -r ./deepseek-coder-v2-lite-instruct jetson@<ip>:~/models/"
echo ""
echo "2. Activate the inference environment:"
echo "   source $VENV_DIR/bin/activate"
echo ""
echo "3. Run the deployment script:"
echo "   bash jetson_deploy.sh"
echo ""
echo "4. Or manually start vLLM:"
echo "   vllm serve ~/models/deepseek-coder-v2-lite-instruct --quantization fp8"
echo ""
echo "================================================================================"
