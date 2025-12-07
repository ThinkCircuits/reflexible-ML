#!/bin/bash
################################################################################
# Build CTranslate2 with CUDA support for Jetson
# This builds ctranslate2 from source with CUDA/cuDNN for faster-whisper GPU
################################################################################

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/ctranslate2-build"
VENV_DIR="$PROJECT_DIR/whisper-venv"

print_status() { echo -e "${GREEN}[✓]${NC} $1"; }
print_error() { echo -e "${RED}[✗]${NC} $1"; }
print_info() { echo -e "${YELLOW}[i]${NC} $1"; }

echo -e "${BLUE}================================================================================${NC}"
echo -e "${BLUE}Building CTranslate2 with CUDA support for Jetson${NC}"
echo -e "${BLUE}================================================================================${NC}"
echo ""

# Check CUDA
if ! command -v nvcc &>/dev/null; then
    print_error "CUDA toolkit not found. Install with: sudo apt install cuda-toolkit"
    exit 1
fi

CUDA_VERSION=$(nvcc --version | grep "release" | sed 's/.*release \([0-9]*\.[0-9]*\).*/\1/')
print_status "CUDA version: $CUDA_VERSION"

# Check for cuDNN
if [ ! -f /usr/include/cudnn.h ] && [ ! -f /usr/local/cuda/include/cudnn.h ]; then
    print_info "cuDNN headers not found in standard locations"
    print_info "Make sure cuDNN is installed: sudo apt install libcudnn8-dev"
fi

# Install build dependencies
print_info "Installing build dependencies..."
sudo apt-get update
sudo apt-get install -y \
    cmake \
    build-essential \
    git \
    libopenblas-dev \
    libsndfile1-dev

# Clone ctranslate2
if [ ! -d "$BUILD_DIR" ]; then
    print_info "Cloning CTranslate2..."
    git clone --recursive https://github.com/OpenNMT/CTranslate2.git "$BUILD_DIR"
fi

cd "$BUILD_DIR"

# Checkout a stable version (4.x branch for compatibility with faster-whisper)
print_info "Fetching latest tags..."
git fetch --tags

LATEST_V4=$(git tag -l 'v4.*' | sort -V | tail -1)
if [ -n "$LATEST_V4" ]; then
    print_info "Using version: $LATEST_V4"
    git checkout "$LATEST_V4"
    git submodule update --init --recursive
else
    print_info "Using main branch"
    git checkout main
    git pull
    git submodule update --init --recursive
fi

# Patch CMakeLists.txt for very new CUDA architectures (like Blackwell 11.0)
# The deprecated cuda_select_nvcc_arch_flags doesn't know about new architectures
print_info "Patching CMakeLists.txt for modern CUDA architectures..."

# Backup and patch
cp CMakeLists.txt CMakeLists.txt.orig 2>/dev/null || true

# Replace the cuda_select_nvcc_arch_flags call with direct CMAKE_CUDA_FLAGS setting
sed -i 's/cuda_select_nvcc_arch_flags(ARCH_FLAGS ${CUDA_ARCH_LIST})/# Patched: using CMAKE_CUDA_ARCHITECTURES instead\n  set(ARCH_FLAGS "-gencode=arch=compute_${CMAKE_CUDA_ARCHITECTURES},code=sm_${CMAKE_CUDA_ARCHITECTURES}")/' CMakeLists.txt

# Create build directory
rm -rf build
mkdir -p build
cd build

# Configure with CUDA support
print_info "Configuring with CUDA support..."

# Detect CUDA compute capability for Jetson
# Thor (Blackwell) = 11.0, Orin = 8.7, AGX Xavier = 7.2, Nano = 5.3
# Auto-detect from nvidia-smi if not specified
if [ -z "$CUDA_ARCH" ]; then
    DETECTED_ARCH=$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | head -1 | tr -d ' ')
    if [ -n "$DETECTED_ARCH" ]; then
        CUDA_ARCH="$DETECTED_ARCH"
        print_info "Auto-detected CUDA compute capability: $CUDA_ARCH"
    else
        CUDA_ARCH="8.7"  # Fallback to Orin
    fi
fi

# Convert arch format (11.0 -> 110, 8.7 -> 87)
CUDA_ARCH_NUM="${CUDA_ARCH//./}"

# For very new architectures (like 11.0/Blackwell), CMake's FindCUDA doesn't recognize them
# We need to pass the flags directly to nvcc
print_info "Building for CUDA architecture: sm_$CUDA_ARCH_NUM"

cmake .. \
    -DCMAKE_BUILD_TYPE=Release \
    -DWITH_CUDA=ON \
    -DWITH_CUDNN=ON \
    -DWITH_MKL=OFF \
    -DWITH_OPENBLAS=ON \
    -DOPENMP_RUNTIME=COMP \
    -DCMAKE_CUDA_ARCHITECTURES="$CUDA_ARCH_NUM" \
    -DCUDA_NVCC_FLAGS="-gencode=arch=compute_${CUDA_ARCH_NUM},code=sm_${CUDA_ARCH_NUM}" \
    -DCMAKE_INSTALL_PREFIX="$BUILD_DIR/install" \
    -DBUILD_CLI=OFF \
    -Wno-dev

# Build (use multiple cores but leave some for system)
JOBS=$(( $(nproc) - 2 ))
[ $JOBS -lt 1 ] && JOBS=1

print_info "Building with $JOBS parallel jobs (this may take 10-30 minutes)..."
cmake --build . --config Release --parallel $JOBS

# Install to local directory
print_info "Installing to $BUILD_DIR/install..."
cmake --install .

print_status "C++ library built successfully"

# Build Python bindings
print_info "Building Python bindings..."
cd "$BUILD_DIR/python"

# Activate the venv
source "$VENV_DIR/bin/activate"

# Set environment for finding the built library
export CTRANSLATE2_ROOT="$BUILD_DIR/install"
export CMAKE_PREFIX_PATH="$BUILD_DIR/install"
export LD_LIBRARY_PATH="$BUILD_DIR/install/lib:$LD_LIBRARY_PATH"

# Uninstall existing ctranslate2
pip uninstall -y ctranslate2 2>/dev/null || true

# Build and install Python package
print_info "Installing Python bindings to venv..."
pip install .

deactivate

print_status "CTranslate2 with CUDA support installed!"
echo ""
print_info "The whisper-venv now has GPU-accelerated ctranslate2"
print_info "Test with: ./scripts/start_whisper_ws.sh --model large-v3-turbo"
echo ""

# Verify installation
print_info "Verifying CUDA support..."
source "$VENV_DIR/bin/activate"
python3 -c "
import ctranslate2
print(f'CTranslate2 version: {ctranslate2.__version__}')
print(f'CUDA available: {\"cuda\" in ctranslate2.get_supported_compute_types()}')
print(f'Supported devices: {ctranslate2.get_supported_compute_types()}')
" 2>&1 || print_error "Verification failed"
deactivate

echo ""
echo -e "${BLUE}================================================================================${NC}"
echo -e "${GREEN}Build complete!${NC}"
echo -e "${BLUE}================================================================================${NC}"
