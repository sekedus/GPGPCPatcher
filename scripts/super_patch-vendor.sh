#!/bin/bash
# ================================================================
# Patch vendor_a.img: Add adbproxy to /vendor/bin/
# ================================================================

set -e
set -o pipefail

UNPACKED_DIR="${SUPER_UNPACKED_DIR}"
ADBPROXY_FILE="$1"
WORK_DIR="${2:-/tmp/super_patch_vendor_$$}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
GRAY='\033[0;37m'
HPURPLE='\033[0;95m'
NC='\033[0m' # No Color

# ================================================================
# Helper Functions
# ================================================================

print_header() {
    echo -e "${CYAN}====================================================${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}====================================================${NC}"
    echo ""
}

print_success() { echo -e "${GREEN}$1${NC}"; }
print_error() { echo -e "${RED}ERROR: $1${NC}"; }
print_warning() { echo -e "${YELLOW}WARNING: $1${NC}"; }
print_info() { echo -e "${GRAY}$1${NC}"; }
print_highlight() { echo -e "${HPURPLE}$1${NC}"; }

check_command() {
    if ! command -v "$1" &> /dev/null; then
        print_error "Required command not found: $1"
        echo ""
        echo "Please install it:"
        case "$1" in
            bc)
                echo "  sudo apt install bc"
                ;;
        esac
        echo ""
        exit 1
    fi
}

# ================================================================
# Validate Arguments
# ================================================================

if [ -z "$UNPACKED_DIR" ] || [ -z "$ADBPROXY_FILE" ]; then
    echo "Usage: SUPER_UNPACKED_DIR=<super_unpacked_dir> $0 <adbproxy_file> [work_dir]"
    echo ""
    echo "Example:"
    echo "  SUPER_UNPACKED_DIR=\"/mnt/d/GPGPC/avd/super_unpacked_25.3.22.5\" $0 super_patched.img resources/adbproxy"
    echo ""
    exit 1
fi

if [ ! -d "$UNPACKED_DIR" ]; then
    print_error "Unpacked super directory not found: $UNPACKED_DIR"
    echo ""
    exit 1
fi

if [ ! -f "$ADBPROXY_FILE" ]; then
    print_error "adbproxy file not found: $ADBPROXY_FILE"
    echo ""
    exit 1
fi

# ================================================================
# Check required tools
# ================================================================

print_header "Checking Required Tools"

check_command bc

print_success "All required commands available"
echo ""

# ================================================================
# Create Work Directory
# ================================================================

mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# ================================================================
# STEP 1: Check Vendor Partition
# ================================================================

print_header "STEP 1: Check Vendor Partition"

if [ ! -f "$UNPACKED_DIR/vendor_a.img" ]; then
    print_error "vendor_a.img not found in super unpacked dir"
    echo ""
    print_info "Contents of super unpacked dir:"
    ls -la "$UNPACKED_DIR/"
    echo ""
    exit 1
fi

# Store original vendor_a size
ORIGINAL_SIZE=$(stat -c%s "$UNPACKED_DIR/vendor_a.img" 2>/dev/null || stat -f%z "$UNPACKED_DIR/vendor_a.img")
print_info "Original vendor_a.img size: ${ORIGINAL_SIZE} bytes ($(echo "scale=2; $ORIGINAL_SIZE / 1048576" | bc) MB)"
echo ""

# ================================================================
# STEP 2: Convert Sparse to Raw
# ================================================================

print_header "STEP 2: Converting Sparse to Raw"

# Always attempt simg2img conversion; it will fail gracefully if already
WAS_SPARSE=false
if simg2img "$UNPACKED_DIR/vendor_a.img" vendor_a_raw.img 2>/dev/null; then
    print_success "Converted sparse image to raw ext4"
    WAS_SPARSE=true
else
    cp "$UNPACKED_DIR/vendor_a.img" vendor_a_raw.img
    print_warning "simg2img failed or image is already raw, copying directly..."
fi
echo ""

FS_TYPE=$(file vendor_a_raw.img)
print_info "Detected image type: $FS_TYPE"
echo ""

RAW_SIZE=$(stat -c%s vendor_a_raw.img 2>/dev/null || stat -f%z vendor_a_raw.img)
print_info "Raw vendor_a_raw.img size: ${RAW_SIZE} bytes ($(echo "scale=2; $RAW_SIZE / 1048576" | bc) MB)"
echo ""

# ================================================================
# STEP 3: Prepare adbproxy File
# ================================================================

print_header "STEP 3: Preparing adbproxy File"

ADBPROXY_SIZE=$(stat -c%s "$ADBPROXY_FILE" 2>/dev/null || stat -f%z "$ADBPROXY_FILE")

print_info "adbproxy file: $ADBPROXY_FILE"
print_info "File size: ${ADBPROXY_SIZE} bytes ($(echo "scale=2; $ADBPROXY_SIZE / 1024" | bc) KB)"
echo ""

# Copy adbproxy to current directory with executable permissions
cp "$ADBPROXY_FILE" adbproxy
chmod +x adbproxy

print_success "adbproxy file ready"
echo ""

# ================================================================
# STEP 4: Mount and Modify Vendor Partition
# ================================================================

print_header "STEP 4: Mounting and Modifying Vendor Partition"

print_highlight "Ensuring vendor_a_raw.img is large enough to mount..."
fallocate -l 500M vendor_a_raw.img
resize2fs vendor_a_raw.img 500M

print_highlight "Checking, repairing, and preventing corruption..."
e2fsck -y -E unshare_blocks vendor_a_raw.img 1>/dev/null
echo ""

# Create mount point
mkdir -p vendor_mount

# Mount
print_info "Mounting vendor_a.img..."
sudo mount -o loop vendor_a_raw.img vendor_mount

if ! mountpoint -q vendor_mount; then
    print_error "Failed to mount vendor_a.img"
    echo ""
    exit 1
fi

print_success "Mounted at: $WORK_DIR/vendor_mount"
echo ""

# ================================================================
# STEP 5: Add adbproxy to /vendor/bin/
# ================================================================

print_header "STEP 5: Adding adbproxy to /vendor/bin/"

# Check if /vendor/bin/ exists
if [ ! -d "vendor_mount/bin" ]; then
    print_warning "/vendor/bin/ directory not found"
    print_info "Creating directory..."
    sudo mkdir -p vendor_mount/bin
fi

# Check if adbproxy already exists
if [ -f "vendor_mount/bin/adbproxy" ]; then
    print_warning "adbproxy already exists in /vendor/bin/"
    echo ""

    EXISTING_DIGEST=$(sha256sum vendor_mount/bin/adbproxy | awk '{print $1}')
    NEW_DIGEST=$(sha256sum adbproxy | awk '{print $1}')
    print_info "Existing adbproxy SHA256: ${EXISTING_DIGEST}"
    print_info "New adbproxy SHA256: ${NEW_DIGEST}"
    echo ""

    if [ "$EXISTING_DIGEST" = "$NEW_DIGEST" ]; then
        print_success "File digest matches - adbproxy already up-to-date"
        print_info "Skipping installation"
        echo ""

        # Unmount and skip
        sudo umount vendor_mount

        print_header "NO CHANGES NEEDED"
        echo -e "${GREEN}adbproxy is already installed and up-to-date${NC}"
        echo ""

        rm -rf "$WORK_DIR"
        exit 0
    else
        print_info "File digest differs - replacing with new version..."
        sudo rm -f vendor_mount/bin/adbproxy
        echo ""
    fi
fi

# Copy adbproxy
print_info "Copying adbproxy to /vendor/bin/..."
sudo cp adbproxy vendor_mount/bin/adbproxy

# Set permissions (executable, root:root)
print_info "Setting permissions..."
sudo chmod 755 vendor_mount/bin/adbproxy  # -rwxr-xr-x
sudo chcon u:object_r:adbproxy_exec:s0 vendor_mount/bin/adbproxy

echo ""

# Verify installation
if [ -f "vendor_mount/bin/adbproxy" ]; then
    INSTALLED_SIZE=$(stat -c%s vendor_mount/bin/adbproxy 2>/dev/null || stat -f%z vendor_mount/bin/adbproxy)

    print_success "adbproxy installed successfully"
    print_info "Location: /vendor/bin/adbproxy"
    print_info "Size: ${INSTALLED_SIZE} bytes ($(echo "scale=2; $INSTALLED_SIZE / 1024" | bc) KB)"
    print_info "Permissions: $(stat -c "%A" vendor_mount/bin/adbproxy)"
    print_info "SELinux context: $(ls -ZR vendor_mount/bin/adbproxy)"
else
    print_error "Failed to install adbproxy"
    sudo umount vendor_mount
    echo ""
    exit 1
fi

sync
echo ""

# ================================================================
# STEP 6: Verify Vendor Partition
# ================================================================

print_header "STEP 6: Verifying Vendor Partition Modifications"

print_highlight "Contents of /vendor/bin/ (partial):"
ls -lh vendor_mount/bin/ | tail -n +2

echo ""

print_info "Unmounting..."
sudo umount vendor_mount

print_success "Vendor partition modifications complete"
echo ""

# ================================================================
# STEP 7: Resize to smallest size that fits data
# ================================================================

print_header "STEP 7: Resizing to smallest size that fits data"

print_highlight "Checking & repairing vendor_a_raw.img before resize..."
e2fsck -yf vendor_a_raw.img
echo ""

print_info "Resizing vendor_a_raw.img to the smallest size that still fits all its data"
resize2fs -M vendor_a_raw.img

CURRENT_SIZE=$(stat -c%s vendor_a_raw.img 2>/dev/null || stat -f%z vendor_a_raw.img)
print_info "Current vendor_a_raw.img size: ${CURRENT_SIZE} bytes ($(echo "scale=2; $CURRENT_SIZE / 1048576" | bc) MB)"
print_info "Original vendor_a_raw.img size: ${ORIGINAL_SIZE} bytes ($(echo "scale=2; $ORIGINAL_SIZE / 1048576" | bc) MB)"
echo ""

# ================================================================
# STEP 8: Convert Back to Sparse
# ================================================================

print_header "STEP 8: Converting Back to Sparse Format"

if [ ! -d "$UNPACKED_DIR/new" ]; then
    print_info "Creating output directory: $UNPACKED_DIR/new"
    mkdir -p "$UNPACKED_DIR/new"
    echo ""
fi

if [ "$WAS_SPARSE" = true ]; then
    img2simg vendor_a_raw.img "$UNPACKED_DIR/new/vendor_a_new.img"

    SPARSE_SIZE=$(stat -c%s "$UNPACKED_DIR/new/vendor_a_new.img" 2>/dev/null || stat -f%z "$UNPACKED_DIR/new/vendor_a_new.img")
    print_info "Sparse vendor_a_new.img size: ${SPARSE_SIZE} bytes ($(echo "scale=2; $SPARSE_SIZE / 1048576" | bc) MB)"
else
    print_warning "Original image was not sparse, skipping conversion..."
    echo ""
    cp vendor_a_raw.img "$UNPACKED_DIR/new/vendor_a_new.img"
    print_success "Using raw image directly"
fi

echo ""

FS_TYPE=$(file "$UNPACKED_DIR/new/vendor_a_new.img")
print_info "Detected image type: $FS_TYPE"
echo ""

# ================================================================
# Cleanup
# ================================================================

print_info "Cleaning up temporary work directory..."
rm -rf "$WORK_DIR"
echo ""

# ================================================================
# Summary
# ================================================================

print_header "PATCH VENDOR COMPLETE"

echo -e "${GREEN}Summary:${NC}"
echo -e "${GRAY}  Unpacked super image${NC}"
[ "$WAS_SPARSE" = true ] && echo -e "${GRAY}  Converted vendor_a from sparse to raw format${NC}"
echo -e "${GRAY}  Added adbproxy to /vendor/bin/${NC}"
echo -e "${GRAY}  File size: ${ADBPROXY_SIZE} bytes ($(echo "scale=2; $ADBPROXY_SIZE / 1024" | bc) KB)"
echo -e "${GRAY}  Permissions: 755 (executable)${NC}"
echo -e "${GRAY}  Resized to smallest size that fits data${NC}"
[ "$WAS_SPARSE" = true ] && echo -e "${GRAY}  Converted back to sparse format${NC}"
echo ""

echo -e "${CYAN}Patched image written to:${NC}"
echo -e "${GRAY}  $UNPACKED_DIR/new/vendor_a_new.img${NC}"
echo ""
