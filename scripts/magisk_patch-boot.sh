#!/bin/bash
# ================================================================
# Magisk Boot Patcher with WSL
# ================================================================
#
# Description:
#   Patches Android boot images with Magisk using libmagiskboot.so
#   extracted from Magisk APK.
#
# Usage:
#   ./magisk_patch-boot.sh <boot.img> <magisk.apk> <superpower.apk> <output.img>
#
# Arguments:
#   $1 - Path to boot_a.img (input)
#   $2 - Path to Magisk.apk
#   $3 - Path to superpower.apk
#   $4 - Path to output image
#
# ================================================================

set -e  # Exit on error
set -o pipefail  # Pipe failures cause script to fail

# ================================================================
# Configuration
# ================================================================

BOOT_PATH="$1"
MAGISK_APK="$2"
SUPER_APK="$3"
OUTPUT_PATH="$4"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
GRAY='\033[0;37m'
BLUE='\033[0;34m'
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

check_command() {
    if ! command -v "$1" &> /dev/null; then
        print_error "Required command not found: $1"
        echo ""
        echo "Please install it:"
        case "$1" in
            unzip)
                echo "  sudo apt install unzip"
                ;;
            sha1sum)
                echo "  sudo apt install coreutils"
                ;;
        esac
        echo ""
        exit 1
    fi
}

# ================================================================
# Validate Arguments
# ================================================================

if [ -z "$BOOT_PATH" ] || [ -z "$MAGISK_APK" ] || [ -z "$SUPER_APK" ] || [ -z "$OUTPUT_PATH" ]; then
    echo "Usage: $0 <boot.img> <magisk.apk> <superpower.apk> <output.img>"
    echo ""
    echo "Arguments:"
    echo "  boot.img   - Input boot image to patch"
    echo "  magisk.apk - Magisk APK file"
    echo "  superpower.apk - Superpower APK file"
    echo "  output.img - Output patched boot image"
    echo ""
    echo "Example:"
    echo "  $0 boot_a.img Magisk.apk superpower.apk boot_a-patched.img"
    echo ""
    exit 1
fi

if [ ! -f "$BOOT_PATH" ]; then
    print_error "Boot image not found: $BOOT_PATH"
    echo ""
    exit 1
fi

if [ ! -f "$MAGISK_APK" ]; then
    print_error "Magisk APK not found: $MAGISK_APK"
    echo ""
    exit 1
fi

if [ ! -f "$SUPER_APK" ]; then
    print_error "Superpower APK not found: $SUPER_APK"
    echo ""
    exit 1
fi

# Store original size
ORIGINAL_SIZE=$(stat -f%z "$BOOT_PATH" 2>/dev/null || stat -c%s "$BOOT_PATH")
ORIGINAL_SIZE_MB=$(echo "scale=2; $ORIGINAL_SIZE / 1048576" | bc 2>/dev/null || awk "BEGIN {printf \"%.2f\", $ORIGINAL_SIZE/1048576}")

print_info "Original size: ${ORIGINAL_SIZE} bytes (${ORIGINAL_SIZE_MB} MB)"
echo ""

# ================================================================
# Check Prerequisites
# ================================================================

print_header "Checking Prerequisites"

check_command unzip
check_command sha1sum

print_success "All required commands available"
echo ""

# ================================================================
# Setup Working Directory
# ================================================================

WORK_DIR="/tmp/magisk_patch_$$"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

print_info "Working directory: $WORK_DIR"
echo ""

# Cleanup on exit
trap 'cd /tmp && rm -rf "$WORK_DIR"' EXIT

# ================================================================
# STEP 1: Extract libmagiskboot.so from Magisk APK
# ================================================================

print_header "STEP 1: Extracting libmagiskboot.so"

print_info "Extracting from: $MAGISK_APK"

# Try x86_64 first
if unzip -q "$MAGISK_APK" "lib/x86_64/libmagiskboot.so" -d . 2>/dev/null; then
    mv lib/x86_64/libmagiskboot.so magiskboot
    print_info "Extracted lib/x86_64/libmagiskboot.so"
elif unzip -q "$MAGISK_APK" "lib/x86/libmagiskboot.so" -d . 2>/dev/null; then
    mv lib/x86/libmagiskboot.so magiskboot
    print_info "Extracted lib/x86/libmagiskboot.so"
else
    print_error "libmagiskboot.so not found in APK!"
    echo ""
    exit 1
fi

echo ""

# Make it executable
chmod +x magiskboot

print_success "magiskboot ready"
echo ""

# ================================================================
# STEP 2: Unpack Boot Image
# ================================================================

print_header "STEP 2: Unpacking Boot Image"

# Copy boot image for analysis
cp "$BOOT_PATH" boot.img

print_info "Unpacking boot image for analysis..."
./magiskboot unpack boot.img >/dev/null 2>&1

if [ ! -f "ramdisk.cpio" ]; then
    print_error "Failed to unpack boot image"
    print_info "This may not be a valid Android boot image"
    echo ""
    exit 1
fi

print_success "Boot image unpacked"
echo ""

# ================================================================
# STEP 3: Detect Boot Image Type
# ================================================================

print_header "STEP 3: Detecting Boot Image Type"

STATUS=0
./magiskboot cpio ramdisk.cpio test || STATUS=$?

IS_STOCK=false
SHA1=""
BOOT_TYPE=""

# Parse magiskboot test result
# Status codes (from Magisk source):
#   0 - Stock boot image
#   1 - Magisk patched
#   2 - Unsupported/Other patched

case $((STATUS & 3)) in
    0)
        BOOT_TYPE="Stock"
        print_success "Boot image type: ${BOOT_TYPE}"
        print_info "This is an unmodified boot image"

        # Calculate SHA1 for stock image
        SHA1=$(sha1sum boot.img | awk '{print $1}')
        print_info "SHA1: $SHA1"
        IS_STOCK=true
        ;;
    1)
        BOOT_TYPE="Patched"
        print_warning "Boot image type: ${BOOT_TYPE}"
        print_info "This boot image is already patched by Magisk"

        # Extract original SHA1 from existing Magisk config
        ./magiskboot cpio ramdisk.cpio \
            "extract .backup/.magisk config.orig" \
            "restore" 2>/dev/null || true

        if [ -f "config.orig" ]; then
            # Ensure file is readable
            chmod 644 config.orig 2>/dev/null || true

            SHA1=$(grep "^SHA1=" config.orig | cut -d= -f2)
            print_info "Original SHA1: $SHA1"

            # Check Magisk version
            if grep -q "MAGISK_VER=" config.orig; then
                MAGISK_VER=$(grep "^MAGISK_VER=" config.orig | cut -d= -f2)
                print_info "Current Magisk version: $MAGISK_VER"
            fi
        fi
        IS_STOCK=false
        ;;
    2)
        BOOT_TYPE="Other_Patched"
        print_error "Boot image type: ${BOOT_TYPE}"
        print_info "Patched by unsupported program (not Magisk)"
        echo ""
        print_error "Cannot patch this boot image!"
        print_info "Please use original stock boot image"
        echo ""
        exit 1
        ;;
    *)
        print_error "Unknown boot image status: $STATUS"
        echo ""
        exit 1
        ;;
esac

echo ""

# ================================================================
# STEP 4: Detect if Boot Image is Already Patched
# ================================================================

print_header "STEP 4: Detect if Boot Image is Already Patched"

if [ "$IS_STOCK" = false ]; then
    print_warning "This boot image is already patched with Magisk."
    echo ""

    print_info "Options:"
    print_info "  1. Use stock boot_a.img to patch"
    print_info "  2. Continue to re-patch (may update Magisk version)"
    print_info "  3. Skip and use this image as-is"
    echo ""

    read -p "Continue to re-patch anyway? (yes/no): " CONTINUE

    if [ "$CONTINUE" != "yes" ]; then
        print_info "Skipping Magisk patching..."
        print_info "Copying input to output..."

        cp "$BOOT_PATH" "$OUTPUT_PATH"

        echo ""
        print_header "OPERATION COMPLETE (No Changes)"

        echo -e "${GREEN}Output:${NC}"
        echo -e "${GRAY}  $OUTPUT_PATH${NC}"
        echo -e "${GRAY}  (Same as input - already patched)${NC}"
        echo ""

        print_info "Boot image already contains Magisk"
        print_info "Flash this image to maintain Magisk installation"
        echo ""

        exit 0
    fi

    echo ""
    print_warning "Re-patching existing Magisk installation..."
    print_info "This will update/reinstall Magisk"
else
    print_success "Boot image is stock - ready for Magisk patching"
fi

echo ""

# ================================================================
# STEP 5: Extract Magisk Components
# ================================================================

print_header "STEP 5: Extracting Magisk Components"

extract_lib() {
    local ABI="$1"
    local lib="$2"
    local output="$3"

    if unzip -q "$MAGISK_APK" "lib/$ABI/$lib" -d . 2>/dev/null; then
        mv "lib/$ABI/$lib" "$output"
    else
        print_error "$lib not found in APK"
        echo ""
        exit 1
    fi
}

# Extract required libraries
extract_lib "x86_64" "libmagisk.so" "magisk"
extract_lib "x86_64" "libmagiskinit.so" "magiskinit"
extract_lib "x86_64" "libinit-ld.so" "init-ld"

# Extract stub.apk
unzip -q "$MAGISK_APK" "assets/stub.apk" -d .
mv assets/stub.apk stub.apk

print_success "Extracted components:"
print_info "- magisk"
print_info "- magiskinit"
print_info "- init-ld"
print_info "- stub.apk"
echo ""

# ================================================================
# STEP 6: Backup Original Ramdisk
# ================================================================

print_header "STEP 6: Backing Up Original Ramdisk"
cp ramdisk.cpio ramdisk.cpio.orig

print_success "Original ramdisk backed up as ramdisk.cpio.orig"
echo ""

# ================================================================
# STEP 7: Compress Magisk Components
# ================================================================

print_header "STEP 7: Compressing Magisk Components"

./magiskboot compress=xz magisk magisk.xz
./magiskboot compress=xz stub.apk stub.xz
./magiskboot compress=xz init-ld init-ld.xz

print_success "Compressed components:"
print_info "- magisk.xz"
print_info "- stub.xz"
print_info "- init-ld.xz"
echo ""

# ================================================================
# STEP 8: Create Magisk Configuration
# ================================================================

print_header "STEP 8: Creating Magisk Configuration"

cat > config << EOF
KEEPVERITY=true
KEEPFORCEENCRYPT=true
RECOVERYMODE=false
PREINITDEVICE=metadata
SHA1=$SHA1
EOF

print_success "Configuration created"
print_info "KEEPVERITY=true"
print_info "KEEPFORCEENCRYPT=true"
if [ -n "$SHA1" ]; then
    print_info "SHA1=$SHA1"
fi
echo ""

# ================================================================
# STEP 9: Inject Magisk into Ramdisk
# ================================================================

print_header "STEP 9: Injecting Magisk into Ramdisk"

if [ "$IS_STOCK" = true ]; then
    print_info "Patching stock boot image..."
else
    print_info "Re-patching Magisk boot image..."
fi

./magiskboot cpio ramdisk.cpio \
    "add 0750 init magiskinit" \
    "mkdir 0750 overlay.d" \
    "mkdir 0750 overlay.d/sbin" \
    "add 0644 overlay.d/sbin/magisk.xz magisk.xz" \
    "add 0644 overlay.d/sbin/stub.xz stub.xz" \
    "add 0644 overlay.d/sbin/init-ld.xz init-ld.xz" \
    "patch" \
    "backup ramdisk.cpio.orig" \
    "mkdir 000 .backup" \
    "add 000 .backup/.magisk config"

print_success "Magisk injected into ramdisk"
echo ""

# ================================================================
# STEP 10: Inject Superpower into Ramdisk
# ================================================================

print_header "STEP 10: Injecting Superpower into Ramdisk"

# Copy superpower.apk into working directory
cp "$SUPER_APK" superpower.apk

# Write custom.rc that run superpower.apk on boot with Magisk context
cat > custom.rc << 'EOF_RC'
on boot
    exec_background u:r:magisk:s0 root root -- /system/bin/app_process -cp ${MAGISKTMP}/superpower.apk /sdcard Superpower
EOF_RC

# Inject both superpower.apk and custom.rc into the ramdisk
./magiskboot cpio ramdisk.cpio \
    "add 0644 overlay.d/custom.rc custom.rc" \
    "add 0755 overlay.d/sbin/superpower.apk superpower.apk"

echo ""
print_success "Superpower injected into ramdisk"
echo ""

# ================================================================
# STEP 11: Repack Boot Image
# ================================================================

print_header "STEP 11: Repacking Boot Image"

print_info "Repacking boot.img..."
./magiskboot repack boot.img

if [ ! -f "new-boot.img" ]; then
    print_error "new-boot.img not created after repacking!"
    echo ""
    exit 1
fi

NEW_SIZE=$(stat -f%z new-boot.img 2>/dev/null || stat -c%s new-boot.img)
NEW_SIZE_MB=$(echo "scale=2; $NEW_SIZE / 1048576" | bc 2>/dev/null || echo "$(($NEW_SIZE / 1048576))")

print_success "Boot image repacked"
print_info "Output size: ${NEW_SIZE} bytes (${NEW_SIZE_MB} MB)"
echo ""

# ================================================================
# STEP 12: Adjust Size to Match Original
# ================================================================

print_header "STEP 12: Adjusting Size"

print_info "Original: ${ORIGINAL_SIZE} bytes (${ORIGINAL_SIZE_MB} MB)"
print_info "New:      ${NEW_SIZE} bytes (${NEW_SIZE_MB} MB)"

if [ $NEW_SIZE -eq $ORIGINAL_SIZE ]; then
    print_success "Perfect size match!"
else
    SIZE_DIFF=$((NEW_SIZE - ORIGINAL_SIZE))
    SIZE_DIFF_KB=$(echo "scale=2; $SIZE_DIFF / 1024" | bc 2>/dev/null || awk "BEGIN {printf \"%.2f\", $SIZE_DIFF/1024}")

    print_warning "New boot image is ${SIZE_DIFF_KB} KB larger!"
fi

cp new-boot.img "$OUTPUT_PATH"
echo ""

# Verify final size
FINAL_SIZE=$(stat -f%z "$OUTPUT_PATH" 2>/dev/null || stat -c%s "$OUTPUT_PATH")
FINAL_SIZE_MB=$(echo "scale=2; $FINAL_SIZE / 1048576" | bc 2>/dev/null || awk "BEGIN {printf \"%.2f\", $FINAL_SIZE/1048576}")

# ================================================================
# Summary
# ================================================================

print_header "PATCH BOOT COMPLETE"

echo -e "${GREEN}Output:${NC}"
echo -e "${GRAY}  $OUTPUT_PATH${NC}"
echo -e "${GRAY}  Size: ${FINAL_SIZE} bytes (${FINAL_SIZE_MB} MB)${NC}"
echo ""

echo -e "${GREEN}What was done:${NC}"
echo -e "${GRAY}  Magisk injected into boot${NC}"
echo -e "${GRAY}  Superpower injected into boot${NC}"
echo ""
