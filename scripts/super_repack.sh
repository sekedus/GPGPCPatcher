#!/bin/bash
# ================================================================
# Repack Super Image from unpacked partitions
# ================================================================

set -e
set -o pipefail

UNPACKED_DIR="${SUPER_UNPACKED_DIR}"
SUPER_IMG="$1"
OUTPUT_SUPER="$2"
USE_SYSTEM_PATCH="${3,,}"  # Convert to lowercase for easier checks

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
        esac
        echo ""
        exit 1
    fi
}

# ================================================================
# Validate Arguments
# ================================================================

if [ -z "$UNPACKED_DIR" ] || [ -z "$SUPER_IMG" ] || [ -z "$OUTPUT_SUPER" ]; then
    echo "Usage: SUPER_UNPACKED_DIR=<super_unpacked_dir> $0 <original_super.img> <output_super.img>"
    echo ""
    echo "Example:"
    echo "  SUPER_UNPACKED_DIR=\"/mnt/d/GPGPC/avd/super_unpacked_25.3.22.5\" $0 super.img super-patched.img"
    echo ""
    exit 1
fi

if [ ! -d "$UNPACKED_DIR" ]; then
    print_error "Unpacked super directory not found: $UNPACKED_DIR"
    echo ""
    exit 1
fi

if [ ! -f "$SUPER_IMG" ]; then
    print_error "Original super image not found: $SUPER_IMG"
    echo ""
    exit 1
fi

# ================================================================
# Check required tools
# ================================================================

print_header "Checking Required Tools"

# Get script directory for resolving /resources/bin folder
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WSL_BIN_DIR="$SCRIPT_DIR/../resources/bin"

for tool in lpdump lpmake; do
    if ! command -v "$tool" &> /dev/null; then
        if [ -f "$WSL_BIN_DIR/$tool" ]; then
            print_info "Copying $tool from $WSL_BIN_DIR to /usr/local/bin/..."
            sudo cp "$WSL_BIN_DIR/$tool" /usr/local/bin/"$tool"
            sudo chmod +x /usr/local/bin/"$tool"
            print_success "$tool installed to /usr/local/bin/"
        else
            print_error "Required tool not found: $tool"
            echo ""
            echo "Place the binary in: $WSL_BIN_DIR/$tool"
            echo ""
            exit 1
        fi
    fi
done

check_command bc

print_success "All required commands available"
echo ""

# ================================================================
# Repack Super Image
# ================================================================

print_header "Repacking Super Image"

ORIGINAL_SUPER_SIZE=$(stat -c%s "$SUPER_IMG" 2>/dev/null || stat -f%z "$SUPER_IMG")

# Get metadata from original super
print_highlight "Reading original super.img metadata..."
lpdump "$SUPER_IMG"
echo ""

# Must match original super metadata, obtained from lpdump output
METADATA_SIZE=65536
METADATA_SLOTS=3

print_info "Building new super image..."
print_info "  Metadata size: $METADATA_SIZE bytes"
print_info "  Metadata slots: $METADATA_SLOTS"
print_info "  Device size: $ORIGINAL_SUPER_SIZE bytes"
echo ""

# ----------------------------------------------------------------
# Helper: resolve partition image - prefer patched version in new/
# ----------------------------------------------------------------
resolve_partition_img() {
    local name="$1"
    local new_path="$UNPACKED_DIR/new/${name}_new.img"
    local orig_path="$UNPACKED_DIR/${name}.img"
    local checked_paths=()

    # If this is system_a/system_b and system patch is skipped, use original image
    if [[ "$USE_SYSTEM_PATCH" == "false" && ( "$name" == "system_a" || "$name" == "system_b" ) ]]; then
        checked_paths=("$orig_path")
        if [ -f "$orig_path" ]; then
            echo "$orig_path"
            return
        fi
    else
        checked_paths=("$new_path" "$orig_path")
        if [ -f "$new_path" ]; then
            echo "$new_path"
            return
        fi
        if [ -f "$orig_path" ]; then
            echo "$orig_path"
            return
        fi
    fi

    print_error "Partition image not found for: $name"
    for path in "${checked_paths[@]}"; do
        print_info "  Checked: $path"
    done
    echo ""
    exit 1
}

# Resolve all partition images
SYSTEM_A_IMG=$(resolve_partition_img "system_a")
SYSTEM_B_IMG=$(resolve_partition_img "system_b")
VENDOR_A_IMG=$(resolve_partition_img "vendor_a")
VENDOR_B_IMG=$(resolve_partition_img "vendor_b")
PRODUCT_A_IMG=$(resolve_partition_img "product_a")
PRODUCT_B_IMG=$(resolve_partition_img "product_b")

print_info "Partition images resolved:"
print_info "  system_a:  $SYSTEM_A_IMG"
print_info "  system_b:  $SYSTEM_B_IMG"
print_info "  vendor_a:  $VENDOR_A_IMG"
print_info "  vendor_b:  $VENDOR_B_IMG"
print_info "  product_a: $PRODUCT_A_IMG"
print_info "  product_b: $PRODUCT_B_IMG"
echo ""

# Get sizes
SYSTEM_A_SIZE=$(stat -c%s  "$SYSTEM_A_IMG"  2>/dev/null || stat -f%z "$SYSTEM_A_IMG")
SYSTEM_B_SIZE=$(stat -c%s  "$SYSTEM_B_IMG"  2>/dev/null || stat -f%z "$SYSTEM_B_IMG")
VENDOR_A_SIZE=$(stat -c%s  "$VENDOR_A_IMG"  2>/dev/null || stat -f%z "$VENDOR_A_IMG")
VENDOR_B_SIZE=$(stat -c%s  "$VENDOR_B_IMG"  2>/dev/null || stat -f%z "$VENDOR_B_IMG")
PRODUCT_A_SIZE=$(stat -c%s "$PRODUCT_A_IMG" 2>/dev/null || stat -f%z "$PRODUCT_A_IMG")
PRODUCT_B_SIZE=$(stat -c%s "$PRODUCT_B_IMG" 2>/dev/null || stat -f%z "$PRODUCT_B_IMG")

GROUP_A="google_dynamic_partitions_a"
GROUP_B="google_dynamic_partitions_b"

GROUP_A_SIZE=$((SYSTEM_A_SIZE + VENDOR_A_SIZE + PRODUCT_A_SIZE))
GROUP_B_SIZE=$((SYSTEM_B_SIZE + VENDOR_B_SIZE + PRODUCT_B_SIZE))

# Build lpmake command
LPMAKE_ARGS=(
    --metadata-size="$METADATA_SIZE"
    --metadata-slots="$METADATA_SLOTS"
    --super-name=super
    --device-size="$ORIGINAL_SUPER_SIZE"
    --group="$GROUP_A:$GROUP_A_SIZE"
    --group="$GROUP_B:$GROUP_B_SIZE"
    --partition="system_a:readonly:${SYSTEM_A_SIZE}:$GROUP_A"
    --image="system_a=$SYSTEM_A_IMG"
    --partition="system_b:readonly:${SYSTEM_B_SIZE}:$GROUP_B"
    --image="system_b=$SYSTEM_B_IMG"
    --partition="vendor_a:readonly:${VENDOR_A_SIZE}:$GROUP_A"
    --image="vendor_a=$VENDOR_A_IMG"
    --partition="vendor_b:readonly:${VENDOR_B_SIZE}:$GROUP_B"
    --image="vendor_b=$VENDOR_B_IMG"
    --partition="product_a:readonly:${PRODUCT_A_SIZE}:$GROUP_A"
    --image="product_a=$PRODUCT_A_IMG"
    --partition="product_b:readonly:${PRODUCT_B_SIZE}:$GROUP_B"
    --image="product_b=$PRODUCT_B_IMG"
    --virtual-ab
    --output="$OUTPUT_SUPER"
)

print_highlight "Executing lpmake:"
print_info "lpmake ${LPMAKE_ARGS[*]}"
echo ""
lpmake "${LPMAKE_ARGS[@]}"

if [ ! -f "$OUTPUT_SUPER" ]; then
    print_error "Failed to create new super image"
    echo ""
    exit 1
fi

echo ""

NEW_SUPER_SIZE=$(stat -c%s "$OUTPUT_SUPER" 2>/dev/null || stat -f%z "$OUTPUT_SUPER")
print_info "New super.img size: $(echo "scale=2; $NEW_SUPER_SIZE / 1048576" | bc) MB"

if [ "$NEW_SUPER_SIZE" -ne "$ORIGINAL_SUPER_SIZE" ]; then
    print_warning "New super image size ($NEW_SUPER_SIZE bytes) does not match original size ($ORIGINAL_SUPER_SIZE bytes)"
else
    print_success "Super image size already matches: $NEW_SUPER_SIZE bytes"
fi

echo ""

print_header "REPACK SUPER COMPLETE"
echo -e "${CYAN}Output:${NC}"
echo -e "${GRAY}  File: $OUTPUT_SUPER${NC}"
echo -e "${GRAY}  Size: $ORIGINAL_SUPER_SIZE bytes ($(echo "scale=2; $ORIGINAL_SUPER_SIZE / 1048576" | bc) MB)${NC}"
echo ""
