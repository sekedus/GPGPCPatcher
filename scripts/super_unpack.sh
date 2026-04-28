#!/bin/bash
# ================================================================
# Unpack super.img using lpunpack
# Usage: super_unpack.sh <super.img> <version>
# Outputs: SUPER_UNPACKED_DIR path to stdout
# ================================================================

set -e
set -o pipefail

# Preserve original stdout on fd 3 so only the final path is emitted on stdout.
exec 3>&1 1>&2

SUPER_IMG="$1"

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

# ================================================================
# Validate Arguments
# ================================================================

if [ -z "$SUPER_IMG" ]; then
    echo "Usage: $0 <input_super.img>"
    echo ""
    echo "Example: $0 super.img"
    echo ""
    exit 1
fi

if [ ! -f "$SUPER_IMG" ]; then
    print_error "Super image not found: $SUPER_IMG"
    echo ""
    exit 1
fi

# ================================================================
# Check required tools
# ================================================================

echo ""
print_header "Checking Required Tools"

# Get script directory for resolving /resources/bin folder
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WSL_BIN_DIR="$SCRIPT_DIR/../resources/bin"

for tool in lpunpack; do
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

print_success "All required commands available"
echo ""

# ================================================================
# Resolve Super Unpacked Directory
# ================================================================

# Place super_unpacked directory next to the input super image for re-use across runs
SUPER_IMG_DIR="$(cd "$(dirname "$SUPER_IMG")" && pwd)"
SUPER_UNPACKED_DIR="$SUPER_IMG_DIR/super_unpacked"

# ================================================================
# Unpack Super Image
# ================================================================

print_header "Unpacking Super Image"

if [ -d "$SUPER_UNPACKED_DIR" ]; then
    print_info "Re-using existing unpacked super dir: $SUPER_UNPACKED_DIR"
    print_success "Skipping lpunpack"
else
    print_info "Unpacking super image to: $SUPER_UNPACKED_DIR"
    mkdir -p "$SUPER_UNPACKED_DIR"
    lpunpack "$SUPER_IMG" "$SUPER_UNPACKED_DIR/"
    print_success "Super image unpacked"
fi

echo ""

print_highlight "Partitions found:"
ls -lh "$SUPER_UNPACKED_DIR/" | grep '\.img$'
echo ""

# Output the directory path to stdout for capture by caller
echo "$SUPER_UNPACKED_DIR" >&3
