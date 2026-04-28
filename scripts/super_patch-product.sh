#!/bin/bash

# ================================================================
# Patch product_a.img: Remove /etc/init/init.user.rc
# ================================================================

set -e
set -o pipefail

UNPACKED_DIR="${SUPER_UNPACKED_DIR}"
WORK_DIR="${1:-/tmp/super_patch_product_$$}"

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
    echo -e "${CYAN}================================================${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}================================================${NC}"
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
            simg2img|img2simg)
                echo "  sudo apt install android-sdk-libsparse-utils"
                ;;
            e2fsck|resize2fs)
                echo "  sudo apt install e2fsprogs"
                ;;
        esac
        echo ""
        exit 1
    fi
}

# ================================================================
# Validate Arguments
# ================================================================


if [ -z "$UNPACKED_DIR" ]; then
    echo "Usage: SUPER_UNPACKED_DIR=<super_unpacked_dir> $0 [work_dir]"
    echo ""
    echo "Example:"
    echo "  SUPER_UNPACKED_DIR=\"/mnt/d/GPGPC/avd/super_unpacked_25.3.22.5\" $0"
    echo ""
    exit 1
fi

if [ ! -d "$UNPACKED_DIR" ]; then
    print_error "Unpacked super directory not found: $UNPACKED_DIR"
    echo ""
    exit 1
fi

# ================================================================
# Check required tools
# ================================================================

print_header "Checking Required Tools"

check_command bc
check_command simg2img
check_command img2simg
check_command e2fsck
check_command resize2fs

print_success "All required commands available"
echo ""

# ================================================================
# Create Work Directory
# ================================================================

mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# ================================================================
# STEP 1: Check Product Partition
# ================================================================

print_header "STEP 1: Check Product Partition"

if [ ! -f "$UNPACKED_DIR/product_a.img" ]; then
    print_error "product_a.img not found in super unpacked dir"
    echo ""
    print_info "Contents of super unpacked dir:"
    ls -la "$UNPACKED_DIR/"
    echo ""
    exit 1
fi

# Store original product_a size
ORIGINAL_SIZE=$(stat -c%s "$UNPACKED_DIR/product_a.img" 2>/dev/null || stat -f%z "$UNPACKED_DIR/product_a.img")
print_info "Original product_a.img size: ${ORIGINAL_SIZE} bytes ($(echo "scale=2; $ORIGINAL_SIZE / 1048576" | bc) MB)"
echo ""

# ================================================================
# STEP 2: Convert Sparse to Raw
# ================================================================

print_header "STEP 2: Converting Sparse to Raw"

# Always attempt simg2img conversion; it will fail gracefully if already
WAS_SPARSE=false
if simg2img "$UNPACKED_DIR/product_a.img" product_a_raw.img 2>/dev/null; then
    print_success "Converted sparse image to raw ext4"
    WAS_SPARSE=true
else
    cp "$UNPACKED_DIR/product_a.img" product_a_raw.img
    print_warning "simg2img failed or image is already raw, copying directly..."
fi
echo ""

FS_TYPE=$(file product_a_raw.img)
print_info "Detected image type: $FS_TYPE"
echo ""

RAW_SIZE=$(stat -c%s product_a_raw.img 2>/dev/null || stat -f%z product_a_raw.img)
print_info "Raw product_a_raw.img size: ${RAW_SIZE} bytes ($(echo "scale=2; $RAW_SIZE / 1048576" | bc) MB)"
echo ""

# ================================================================
# STEP 3: Mount and Modify Product Partition
# ================================================================

print_header "STEP 3: Mounting and Modifying Product Partition"

print_highlight "Ensuring product_a_raw.img is large enough to mount..."
fallocate -l 1G product_a_raw.img
resize2fs product_a_raw.img 1G

print_highlight "Checking, repairing, and preventing corruption..."
e2fsck -y -E unshare_blocks product_a_raw.img 1>/dev/null
echo ""

# Create mount point
mkdir -p product_mount

print_info "Mounting product_a.img..."
sudo mount -o loop product_a_raw.img product_mount

if ! mountpoint -q product_mount; then
    print_error "Failed to mount product_a.img"
    echo ""
    exit 1
fi

print_success "Mounted at: $WORK_DIR/product_mount"
echo ""

# ================================================================
# STEP 4: Remove init.user.rc
# ================================================================

print_header "STEP 4: Removing /etc/init/init.user.rc"

TARGET_FILE="product_mount/etc/init/init.user.rc"

if [ -f "$TARGET_FILE" ]; then
    print_info "Found: /etc/init/init.user.rc"
    print_info "File size: $(stat -c%s \"$TARGET_FILE\" 2>/dev/null || stat -f%z \"$TARGET_FILE\") bytes"
    echo ""

    print_info "File content:"
    echo "------------------------------------------------"
    cat "$TARGET_FILE"
    echo "------------------------------------------------"
    echo ""

    print_info "Removing file contents..."
    sudo rm -f "$TARGET_FILE"
    sync

    # Verify removal
    if [ -f "$TARGET_FILE" ]; then
        print_error "Failed to remove file!"
        sudo umount product_mount
        echo ""
        exit 1
    fi

    print_success "init.user.rc removed successfully"
else
    print_warning "init.user.rc not found"
    print_info "Possible reasons:"
    print_info "  - File already removed"
    print_info "  - Different product image version"
    print_info "  - Wrong partition"
    echo ""

    print_info "Checking directory structure..."
    if [ -d "product_mount/etc/init" ]; then
        print_info "Contents of /etc/init/:"
        ls -la product_mount/etc/init/ | tail -n +2
    else
        print_warning "/etc/init/ directory not found"
    fi
fi
echo ""

print_info "Unmounting..."
sudo umount product_mount

print_success "Product partition modifications complete"
echo ""

# ================================================================
# STEP 5: Resize to smallest size that fits data
# ================================================================

print_header "STEP 5: Resizing to smallest size that fits data"

print_highlight "Checking & repairing product_a_raw.img before resize..."
e2fsck -yf product_a_raw.img
echo ""

print_info "Resizing product_a_raw.img to the smallest size that still fits all its data"
resize2fs -M product_a_raw.img

CURRENT_SIZE=$(stat -c%s product_a_raw.img 2>/dev/null || stat -f%z product_a_raw.img)
print_info "Current product_a_raw.img size: ${CURRENT_SIZE} bytes ($(echo "scale=2; $CURRENT_SIZE / 1048576" | bc) MB)"
print_info "Original product_a_raw.img size: ${ORIGINAL_SIZE} bytes ($(echo "scale=2; $ORIGINAL_SIZE / 1048576" | bc) MB)"
echo ""

# ================================================================
# STEP 6: Convert Back to Sparse
# ================================================================

print_header "STEP 6: Converting Back to Sparse Format"

if [ ! -d "$UNPACKED_DIR/new" ]; then
    print_info "Creating output directory: $UNPACKED_DIR/new"
    mkdir -p "$UNPACKED_DIR/new"
    echo ""
fi

if [ "$WAS_SPARSE" = true ]; then
    img2simg product_a_raw.img "$UNPACKED_DIR/new/product_a_new.img"

    SPARSE_SIZE=$(stat -c%s "$UNPACKED_DIR/new/product_a_new.img" 2>/dev/null || stat -f%z "$UNPACKED_DIR/new/product_a_new.img")
    print_info "Sparse product_a_new.img size: ${SPARSE_SIZE} bytes ($(echo "scale=2; $SPARSE_SIZE / 1048576" | bc) MB)"
else
    print_warning "Original image was not sparse, skipping conversion..."
    echo ""
    cp product_a_raw.img "$UNPACKED_DIR/new/product_a_new.img"
    print_success "Using raw image directly"
fi

echo ""

FS_TYPE=$(file "$UNPACKED_DIR/new/product_a_new.img")
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

print_header "PATCH PRODUCT COMPLETE"

echo -e "${GREEN}Summary:${NC}"
echo -e "${GRAY}  Unpacked super image (or reused existing)${NC}"
[ "$WAS_SPARSE" = true ] && echo -e "${GRAY}  Converted product_a to raw format${NC}"
echo -e "${GRAY}  Removed /etc/init/init.user.rc in product_a${NC}"
echo -e "${GRAY}  Resized to smallest size that fits data${NC}"
[ "$WAS_SPARSE" = true ] && echo -e "${GRAY}  Converted back to sparse format${NC}"
echo ""

echo -e "${CYAN}Patched image written to:${NC}"
echo -e "${GRAY}  $UNPACKED_DIR/new/product_a_new.img${NC}"
echo ""
