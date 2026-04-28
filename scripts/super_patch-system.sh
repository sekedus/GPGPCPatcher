#!/bin/bash
# ================================================================
# Patch system_a.img: Pre-install APK as a system app
#
# Credits: https://android.stackexchange.com/a/161288
# ================================================================

set -e
set -o pipefail

UNPACKED_DIR="${SUPER_UNPACKED_DIR}"
APK_PATH="$1"
TARGET_DIR="${2:-system/app}"
WORK_DIR="${3:-/tmp/super_patch_system_$$}"

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

if [ -z "$UNPACKED_DIR" ] || [ -z "$APK_PATH" ]; then
    echo "Usage: SUPER_UNPACKED_DIR=<super_unpacked_dir> $0 <myapp.apk|myapp.zip> [target_dir] [work_dir]"
    echo ""
    echo "  target_dir  Where to install the APK inside the system partition"
    echo "              Default: system/app"
    echo ""
    echo "  Valid target directories:"
    echo "    system/app/                    (default, regular system apps)"
    echo "    system/priv-app/               (privileged system apps)"
    echo "    system/system_ext/priv-app/    (system_ext privileged apps)"
    echo ""
    echo "  Input file formats:"
    echo "    myapp.apk - Plain APK file"
    echo "    myapp.zip - ZIP containing myapp.apk and optional oat/ subfolder"
    echo "                Example structure:"
    echo "                  Launcher3QuickStep.zip"
    echo "                  ├── oat"
    echo "                  │   └── x86_64"
    echo "                  │       ├── Launcher3QuickStep.odex"
    echo "                  │       └── Launcher3QuickStep.vdex"
    echo "                  └── Launcher3QuickStep.apk"
    echo ""
    echo "Example:"
    echo "  SUPER_UNPACKED_DIR=\"/mnt/d/GPGPC/avd/super_unpacked_25.3.22.5\" $0 MyApp.apk"
    echo "  SUPER_UNPACKED_DIR=\"/mnt/d/GPGPC/avd/super_unpacked_25.3.22.5\" $0 MyApp.zip"
    echo "  SUPER_UNPACKED_DIR=\"/mnt/d/GPGPC/avd/super_unpacked_25.3.22.5\" $0 MyApp.apk system/app/"
    echo ""
    exit 1
fi

if [ ! -d "$UNPACKED_DIR" ]; then
    print_error "Unpacked super directory not found: $UNPACKED_DIR"
    echo ""
    exit 1
fi

if [ ! -f "$APK_PATH" ]; then
    print_error "Input file not found: $APK_PATH"
    echo ""
    exit 1
fi

# Validate file extension
INPUT_EXT="${APK_PATH##*.}"
INPUT_EXT="${INPUT_EXT,,}"  # lowercase
if [ "$INPUT_EXT" != "apk" ] && [ "$INPUT_EXT" != "zip" ]; then
    print_error "Unsupported file type: .$INPUT_EXT (expected .apk or .zip)"
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
# STEP 1: Check System Partition
# ================================================================

print_header "STEP 1: Check System Partition"

if [ ! -f "$UNPACKED_DIR/system_a.img" ]; then
    print_error "system_a.img not found in super unpacked dir"
    echo ""
    print_info "Contents of super unpacked dir:"
    ls -la "$UNPACKED_DIR/"
    echo ""
    exit 1
fi

# Store original system_a size
ORIGINAL_SIZE=$(stat -c%s "$UNPACKED_DIR/system_a.img" 2>/dev/null || stat -f%z "$UNPACKED_DIR/system_a.img")
print_info "Original system_a.img size: ${ORIGINAL_SIZE} bytes ($(echo "scale=2; $ORIGINAL_SIZE / 1048576" | bc) MB)"
echo ""

# ================================================================
# STEP 2: Convert Sparse to Raw
# ================================================================

print_header "STEP 2: Converting Sparse to Raw"

# Always attempt simg2img conversion; it will fail gracefully if already
WAS_SPARSE=false
if simg2img "$UNPACKED_DIR/system_a.img" system_a_raw.img 2>/dev/null; then
    print_success "Converted sparse image to raw ext4"
    WAS_SPARSE=true
else
    cp "$UNPACKED_DIR/system_a.img" system_a_raw.img
    print_warning "simg2img failed or image is already raw, copying directly..."
fi
echo ""

FS_TYPE=$(file system_a_raw.img)
print_info "Detected image type: $FS_TYPE"
echo ""

RAW_SIZE=$(stat -c%s system_a_raw.img 2>/dev/null || stat -f%z system_a_raw.img)
print_info "Raw system_a_raw.img size: ${RAW_SIZE} bytes ($(echo "scale=2; $RAW_SIZE / 1048576" | bc) MB)"
echo ""

# ================================================================
# STEP 3: Prepare Input File (APK or ZIP)
# ================================================================

print_header "STEP 3: Preparing Input File"

INPUT_BASENAME="$(basename "$APK_PATH")"
INPUT_NAME="${INPUT_BASENAME%.*}"
APK_DIR_NAME="${INPUT_NAME// /_}"

# Staging directory for the app files to be copied into the system image
STAGE_DIR="$WORK_DIR/stage/$APK_DIR_NAME"
mkdir -p "$STAGE_DIR"

if [ "$INPUT_EXT" = "zip" ]; then
    print_info "Input: ZIP archive - $APK_PATH"

    # Check unzip is available
    if ! command -v unzip &> /dev/null; then
        print_error "Required command not found: unzip"
        echo "  sudo apt install unzip"
        echo ""
        exit 1
    fi

    # Extract zip to a temp dir
    ZIP_EXTRACT_DIR="$WORK_DIR/zip_extract"
    mkdir -p "$ZIP_EXTRACT_DIR"
    unzip -q "$APK_PATH" -d "$ZIP_EXTRACT_DIR"

    print_info "ZIP contents:"
    find "$ZIP_EXTRACT_DIR" | sed "s|$ZIP_EXTRACT_DIR/||" | sort
    echo ""

    # Find the APK inside the zip (must be at root level)
    INNER_APK=$(find "$ZIP_EXTRACT_DIR" -maxdepth 1 -name "*.apk" | head -n 1)
    if [ -z "$INNER_APK" ]; then
        print_error "No .apk file found at the root of the ZIP archive"
        echo ""
        exit 1
    fi

    APK_BASENAME="$(basename "$INNER_APK")"
    APK_SIZE=$(stat -c%s "$INNER_APK" 2>/dev/null || stat -f%z "$INNER_APK")
    print_info "Found APK: $APK_BASENAME ($(echo "scale=2; $APK_SIZE / 1048576" | bc) MB)"

    # Copy APK into staging dir
    cp "$INNER_APK" "$STAGE_DIR/${APK_DIR_NAME}.apk"

    # Copy oat/ subfolder if present
    if [ -d "$ZIP_EXTRACT_DIR/oat" ]; then
        print_info "Found oat/ subfolder - copying pre-compiled artifacts..."
        cp -r "$ZIP_EXTRACT_DIR/oat" "$STAGE_DIR/oat"

        print_info "oat/ contents:"
        find "$STAGE_DIR/oat" | sed "s|$STAGE_DIR/||" | sort
    else
        print_info "No oat/ subfolder found in ZIP - plain APK only"
    fi

else
    # Plain APK
    print_info "Input: APK file - $APK_PATH"
    APK_BASENAME="$(basename "$APK_PATH")"
    APK_SIZE=$(stat -c%s "$APK_PATH" 2>/dev/null || stat -f%z "$APK_PATH")

    cp "$APK_PATH" "$STAGE_DIR/${APK_DIR_NAME}.apk"
fi

print_info "APK install directory name: $APK_DIR_NAME"
print_info "APK size: ${APK_SIZE} bytes ($(echo "scale=2; $APK_SIZE / 1048576" | bc) MB)"
echo ""

print_info "Staged files:"
find "$STAGE_DIR" | sed "s|$STAGE_DIR|  $APK_DIR_NAME|" | sort
echo ""

print_success "Input file ready"
echo ""

# ================================================================
# STEP 4: Mount and Modify System Partition
# ================================================================

print_header "STEP 4: Mounting and Modifying System Partition"

print_highlight "Ensuring system_a_raw.img is large enough to mount..."
fallocate -l 1500M system_a_raw.img
resize2fs system_a_raw.img 1500M

print_highlight "Checking, repairing, and preventing corruption..."
e2fsck -y -E unshare_blocks system_a_raw.img 1>/dev/null
echo ""

# Create mount point
mkdir -p system_mount

print_info "Mounting system_a.img..."
sudo mount -o loop system_a_raw.img system_mount

if ! mountpoint -q system_mount; then
    print_error "Failed to mount system_a.img"
    echo ""
    exit 1
fi

print_success "Mounted at: $WORK_DIR/system_mount"
echo ""

# ================================================================
# STEP 5: Editing system build.prop for ADB/debuggable
# ================================================================

print_header "STEP 5: Editing system build.prop for ADB/debuggable"

BUILD_PROP_PATH="system_mount/system/build.prop"

if [ -f "$BUILD_PROP_PATH" ]; then
    print_info "Found build.prop: $BUILD_PROP_PATH - backing up to build.prop.bak"
    sudo cp "$BUILD_PROP_PATH" "${BUILD_PROP_PATH}.bak"

    # Desired properties to set/replace
    props=(
        "ro.adb.secure=0"
        "ro.debuggable=1"
        "ro.boot.kiwi.adbproxy.enabled=1"
        "persist.sys.usb.config=adb"
    )

    # Replace existing keys, collect missing ones to insert
    missing=()
    for p in "${props[@]}"; do
        key="${p%%=*}"
        if sudo grep -q -E "^${key}=" "$BUILD_PROP_PATH"; then
            sudo sed -i "s/^${key}=.*/${p}/" "$BUILD_PROP_PATH"
            print_info "Replaced property: ${key}"
        else
            missing+=("$p")
        fi
    done

    # If there are missing properties, try inserting them under the
    # ADDITIONAL_SYSTEM_PROPERTIES header if present, otherwise append.
    if [ ${#missing[@]} -gt 0 ]; then
        if grep -q -F "# from variable ADDITIONAL_SYSTEM_PROPERTIES" "$BUILD_PROP_PATH"; then
            header_line=$(grep -n -F "# from variable ADDITIONAL_SYSTEM_PROPERTIES" "$BUILD_PROP_PATH" | head -n1 | cut -d: -f1)
            insert_after=$((header_line+1))
            block="$(printf "%s\n" "${missing[@]}")"
            awk -v n="$insert_after" -v blk="$block" 'NR==n{print; print blk; next} {print}' "$BUILD_PROP_PATH" | sudo tee "${BUILD_PROP_PATH}.tmp" > /dev/null
            sudo mv "${BUILD_PROP_PATH}.tmp" "$BUILD_PROP_PATH"
            print_info "Inserted missing properties under ADDITIONAL_SYSTEM_PROPERTIES header"
        else
            printf "%s\n" "${missing[@]}" | sudo tee -a "$BUILD_PROP_PATH" > /dev/null
            print_info "Appended missing properties to end of build.prop"
        fi
    fi

    print_success "build.prop updated"
else
    print_warning "build.prop not found at $BUILD_PROP_PATH - skipping edit"
fi


# ================================================================
# (Optional) Remove KiwiEmptyLauncher
# ================================================================

# print_header "(Optional) Removing KiwiEmptyLauncher"

# KIWI_DIR="system_mount/system/app/KiwiEmptyLauncher"
# if [ -d "$KIWI_DIR" ]; then
#     print_info "Removing KiwiEmptyLauncher..."
#     sudo rm -rf "$KIWI_DIR"
#     print_success "Removed: /system/app/KiwiEmptyLauncher/"
# else
#     print_info "KiwiEmptyLauncher not found, skipping removal"
# fi
# echo ""

# ================================================================
# STEP 6: Pre-install APK
# ================================================================

print_header "STEP 6: Pre-installing APK as a System App"

APP_INSTALL_DIR="system_mount/$TARGET_DIR"

# Check if target directory exists
if [ ! -d "$APP_INSTALL_DIR" ]; then
    print_warning "Target directory not found: /$TARGET_DIR"
    print_info "Creating target directory..."
    sudo mkdir -p "$APP_INSTALL_DIR"
fi

# Check if app directory already exists
if [ -d "$APP_INSTALL_DIR/$APK_DIR_NAME" ]; then
    print_warning "$APK_DIR_NAME directory already exists in /$TARGET_DIR/"
    print_info "Removing old installation..."
    sudo rm -rf "$APP_INSTALL_DIR/$APK_DIR_NAME"
fi

# Copy entire staged directory (APK + optional oat/)
print_info "Copying staged files to /$TARGET_DIR/$APK_DIR_NAME/..."
sudo cp -r "$STAGE_DIR" "$APP_INSTALL_DIR/$APK_DIR_NAME"

# Recursively set permissions for all files and directories inside the app directory
print_info "Setting permissions..."
sudo find "$APP_INSTALL_DIR/$APK_DIR_NAME" -type d -exec chmod 755 {} \;  # drwxr-xr-x
sudo find "$APP_INSTALL_DIR/$APK_DIR_NAME" -type f -exec chmod 644 {} \;  # -rw-r--r--

print_info "Setting SELinux context..."
sudo chcon -R u:object_r:system_file:s0 "$APP_INSTALL_DIR/$APK_DIR_NAME"

echo ""

# Verify installation
if [ -f "$APP_INSTALL_DIR/$APK_DIR_NAME/${APK_DIR_NAME}.apk" ]; then
    INSTALLED_SIZE=$(stat -c%s "$APP_INSTALL_DIR/$APK_DIR_NAME/${APK_DIR_NAME}.apk" 2>/dev/null || stat -f%z "$APP_INSTALL_DIR/$APK_DIR_NAME/${APK_DIR_NAME}.apk")
    print_success "APK pre-installed"
    print_info "Location: /$TARGET_DIR/$APK_DIR_NAME/${APK_DIR_NAME}.apk"
    print_info "Size: ${INSTALLED_SIZE} bytes ($(echo "scale=2; $INSTALLED_SIZE / 1048576" | bc) MB)"
    print_info "Permissions:"
    print_info "  Directory: $(stat -c "%A" "$APP_INSTALL_DIR/$APK_DIR_NAME")"
    print_info "  APK: $(stat -c "%A" "$APP_INSTALL_DIR/$APK_DIR_NAME/${APK_DIR_NAME}.apk")"
    print_info "Installed files:"
    find "$APP_INSTALL_DIR/$APK_DIR_NAME" | sed "s|$APP_INSTALL_DIR/|  |" | sort
    echo ""
    print_info "SELinux context - $(ls -ZR "$APP_INSTALL_DIR/$APK_DIR_NAME")"
else
    print_error "Failed to install APK"
    sudo umount system_mount
    echo ""
    exit 1
fi

sync
echo ""

# ================================================================
# STEP 7: Verify System Partition
# ================================================================

print_header "STEP 7: Verifying System Partition Modifications"

print_highlight "Target directory contents (/$TARGET_DIR/):"
ls -lh "$APP_INSTALL_DIR/" | tail -n +2
echo ""

print_info "Unmounting..."
sudo umount system_mount

print_success "System partition modifications complete"
echo ""

# ================================================================
# STEP 8: Resize to smallest size that fits data
# ================================================================

print_header "STEP 8: Resizing to smallest size that fits data"

print_highlight "Checking & repairing system_a_raw.img before resize..."
e2fsck -yf system_a_raw.img
echo ""

print_info "Resizing system_a_raw.img to the smallest size that still fits all its data"
resize2fs -M system_a_raw.img

CURRENT_SIZE=$(stat -c%s system_a_raw.img 2>/dev/null || stat -f%z system_a_raw.img)
print_info "Current system_a_raw.img size: ${CURRENT_SIZE} bytes ($(echo "scale=2; $CURRENT_SIZE / 1048576" | bc) MB)"
print_info "Original system_a_raw.img size: ${ORIGINAL_SIZE} bytes ($(echo "scale=2; $ORIGINAL_SIZE / 1048576" | bc) MB)"
echo ""

# ================================================================
# STEP 9: Convert Back to Sparse
# ================================================================

print_header "STEP 9: Converting Back to Sparse Format"

if [ ! -d "$UNPACKED_DIR/new" ]; then
    print_info "Creating output directory: $UNPACKED_DIR/new"
    mkdir -p "$UNPACKED_DIR/new"
    echo ""
fi

if [ "$WAS_SPARSE" = true ]; then
    img2simg system_a_raw.img "$UNPACKED_DIR/new/system_a_new.img"

    SPARSE_SIZE=$(stat -c%s "$UNPACKED_DIR/new/system_a_new.img" 2>/dev/null || stat -f%z "$UNPACKED_DIR/new/system_a_new.img")
    print_info "Sparse system_a_new.img size: ${SPARSE_SIZE} bytes ($(echo "scale=2; $SPARSE_SIZE / 1048576" | bc) MB)"
else
    print_warning "Original image was not sparse, skipping conversion..."
    echo ""
    cp system_a_raw.img "$UNPACKED_DIR/new/system_a_new.img"
    print_success "Using raw image directly"
fi

echo ""

FS_TYPE=$(file "$UNPACKED_DIR/new/system_a_new.img")
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

print_header "PATCH SYSTEM COMPLETE"

echo -e "${GREEN}Summary:${NC}"
echo -e "${GRAY}  Unpacked super image${NC}"
[ "$WAS_SPARSE" = true ] && echo -e "${GRAY}  Converted system_a from sparse to raw format${NC}"
echo -e "${GRAY}  Pre-installed $INPUT_BASENAME to /$TARGET_DIR/${APK_DIR_NAME}/${NC}"
[ -d "$STAGE_DIR/oat" ] && echo -e "${GRAY}  Included pre-compiled oat/ artifacts${NC}"
echo -e "${GRAY}  APK size: ${APK_SIZE} bytes ($(echo "scale=2; $APK_SIZE / 1048576" | bc) MB)${NC}"
echo -e "${GRAY}  Resized to smallest size that fits data${NC}"
[ "$WAS_SPARSE" = true ] && echo -e "${GRAY}  Converted back to sparse format${NC}"
echo ""

echo -e "${CYAN}Patched image written to:${NC}"
echo -e "${GRAY}  $UNPACKED_DIR/new/system_a_new.img${NC}"
echo ""
