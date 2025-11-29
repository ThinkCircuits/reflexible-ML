#!/bin/bash
################################################################################
# Transfer Script - Copy model and deployment files to Jetson
################################################################################

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

# Check if IP provided
if [ -z "$1" ]; then
    print_error "Usage: $0 <jetson-ip> [jetson-user]"
    echo ""
    echo "Examples:"
    echo "  $0 192.168.1.100              # Default user: jetson"
    echo "  $0 192.168.1.100 ubuntu       # Custom user"
    echo ""
    exit 1
fi

JETSON_IP=$1
JETSON_USER=${2:-jetson}
JETSON_HOST="${JETSON_USER}@${JETSON_IP}"

print_header "Transfer to Jetson AGX Thor"

# Check if we can reach the Jetson
print_info "Testing connection to ${JETSON_HOST}..."
if ssh -o ConnectTimeout=5 -o BatchMode=yes ${JETSON_HOST} exit 2>/dev/null; then
    print_status "Connection successful"
else
    print_error "Cannot connect to ${JETSON_HOST}"
    echo ""
    echo "Please check:"
    echo "  1. Is the Jetson powered on?"
    echo "  2. Is the IP address correct?"
    echo "  3. Can you SSH with: ssh ${JETSON_HOST}"
    echo ""
    exit 1
fi

# Create directories on Jetson
print_info "Creating directories on Jetson..."
ssh ${JETSON_HOST} "mkdir -p ~/models ~/scripts"
print_status "Directories created"

# Check available space on Jetson
print_info "Checking available space on Jetson..."
AVAILABLE_GB=$(ssh ${JETSON_HOST} "df -BG ~ | tail -1 | awk '{print \$4}' | sed 's/G//'")
print_info "Available space: ${AVAILABLE_GB}GB"

if [ "$AVAILABLE_GB" -lt 35 ]; then
    print_error "Not enough space on Jetson (need ~35GB, have ${AVAILABLE_GB}GB)"
    echo ""
    echo "Please free up space on Jetson before continuing."
    exit 1
fi

# Ask for confirmation
echo ""
print_header "Transfer Plan"
echo ""
echo "Source:      $(pwd)"
echo "Destination: ${JETSON_HOST}"
echo ""
echo "Files to transfer:"
echo "  📁 Model:  ./deepseek-coder-v2-lite-instruct (~30GB)"
echo "  📜 Scripts:"
echo "     - jetson_setup.sh"
echo "     - jetson_deploy.sh"
echo "     - test_vllm_deployment.py"
echo "  📖 Guides:"
echo "     - JETSON_DEPLOYMENT_GUIDE.md"
echo ""
echo "Estimated time: 5-30 minutes (depending on network speed)"
echo ""

read -p "Continue with transfer? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Transfer cancelled."
    exit 0
fi

# Transfer model
print_header "Step 1/3: Transferring Model"
print_info "This will take some time (~30GB)..."
print_info "Using rsync for resumable transfer..."

if rsync -avz --progress \
    ./deepseek-coder-v2-lite-instruct \
    ${JETSON_HOST}:~/models/; then
    print_status "Model transferred successfully"
else
    print_error "Model transfer failed"
    echo ""
    echo "You can resume the transfer by running this script again."
    exit 1
fi

# Transfer scripts
print_header "Step 2/3: Transferring Scripts"

SCRIPTS=(
    "jetson_setup.sh"
    "jetson_deploy.sh"
    "test_vllm_deployment.py"
)

for script in "${SCRIPTS[@]}"; do
    if [ -f "$script" ]; then
        print_info "Transferring $script..."
        scp "$script" ${JETSON_HOST}:~/scripts/
        print_status "$script transferred"
    else
        print_error "$script not found"
    fi
done

# Make scripts executable on Jetson
ssh ${JETSON_HOST} "chmod +x ~/scripts/*.sh ~/scripts/*.py"

# Transfer documentation
print_header "Step 3/3: Transferring Documentation"

DOCS=(
    "JETSON_DEPLOYMENT_GUIDE.md"
    "QUANTIZATION_GUIDE.md"
)

for doc in "${DOCS[@]}"; do
    if [ -f "$doc" ]; then
        print_info "Transferring $doc..."
        scp "$doc" ${JETSON_HOST}:~/
        print_status "$doc transferred"
    fi
done

# Verify transfer
print_header "Verifying Transfer"

print_info "Checking model files..."
MODEL_EXISTS=$(ssh ${JETSON_HOST} "[ -d ~/models/deepseek-coder-v2-lite-instruct ] && echo 1 || echo 0")

if [ "$MODEL_EXISTS" = "1" ]; then
    print_status "Model directory exists"

    # Count model files
    FILE_COUNT=$(ssh ${JETSON_HOST} "ls ~/models/deepseek-coder-v2-lite-instruct/ | wc -l")
    print_info "Files in model directory: $FILE_COUNT"
else
    print_error "Model directory not found"
fi

print_info "Checking scripts..."
SCRIPT_COUNT=$(ssh ${JETSON_HOST} "ls ~/scripts/*.sh ~/scripts/*.py 2>/dev/null | wc -l")
print_info "Scripts transferred: $SCRIPT_COUNT"

# Print summary
print_header "Transfer Complete!"

echo ""
echo "✅ Model transferred to: ${JETSON_HOST}:~/models/deepseek-coder-v2-lite-instruct"
echo "✅ Scripts transferred to: ${JETSON_HOST}:~/scripts/"
echo "✅ Documentation transferred to: ${JETSON_HOST}:~/"
echo ""

print_header "Next Steps"

echo ""
echo "1. SSH to Jetson:"
echo "   ${BLUE}ssh ${JETSON_HOST}${NC}"
echo ""
echo "2. Run setup script (first time only):"
echo "   ${BLUE}cd ~/scripts && bash jetson_setup.sh${NC}"
echo ""
echo "3. Deploy the model:"
echo "   ${BLUE}cd ~/scripts && bash jetson_deploy.sh${NC}"
echo ""
echo "4. Test the deployment:"
echo "   ${BLUE}python3 ~/scripts/test_vllm_deployment.py${NC}"
echo ""
echo "5. Read the deployment guide:"
echo "   ${BLUE}cat ~/JETSON_DEPLOYMENT_GUIDE.md${NC}"
echo ""

print_header "Quick Deploy (Copy-Paste Ready)"

echo ""
echo "Run these commands on your Jetson:"
echo ""
echo -e "${GREEN}# Complete deployment in one go${NC}"
echo -e "${BLUE}ssh ${JETSON_HOST} << 'ENDSSH'
cd ~/scripts
bash jetson_setup.sh
bash jetson_deploy.sh
ENDSSH${NC}"
echo ""

print_info "Transfer completed successfully! 🚀"
echo ""
