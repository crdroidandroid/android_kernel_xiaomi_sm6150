#!/bin/bash

# ==============================================
#  Improved Build Script for SM6150 Kernel
#  Supports: Proton Clang + AnyKernel3 Packaging
# ==============================================

set -e
set -o pipefail

# ------------------- Colors -------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ------------------- Variables -------------------
# ------------------- Clang Toolchain (auto-download if missing) -------------------
CLANG_INSTALL_DIR="$HOME/bhairava"
CLANG_TAR_FILE="$HOME/bhairava-x-clang-20260725.tar.gz"
CLANG_DOWNLOAD_URL="https://github.com/San4255/bhairava-x-clang/releases/latest/download/bhairava-x-clang-20260725.tar.gz"
CLANG_PATH="$CLANG_INSTALL_DIR/bin"
CLANG_BIN="$CLANG_PATH/clang"

ANYKERNEL_DIR="AnyKernel3"
ANYKERNEL_REPO="https://github.com/San4255/AnyKernel3.git"
ANYKERNEL_BRANCH="master"

OUT_DIR="out"
FINAL_ZIP_NAME="Mahashunya-Kernel-Phoenix.zip"
LOCALVERSION="-Mahashunya"

# Clean only runs if the script is invoked as: sh build.sh clean
# Plain "sh build.sh" (no argument) will NOT clean, and reuses the existing out/ dir.
DO_CLEAN=0
if [ "$1" = "clean" ]; then
    DO_CLEAN=1
fi

# Build with all available cores (was hardcoded to 1 - huge slowdown)
#JOBS=$(nproc --all)
JOBS=1
# ------------------- Functions -------------------

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

setup_clang() {
    if [ -x "$CLANG_BIN" ]; then
        print_info "Clang already installed at $CLANG_BIN"
        "$CLANG_BIN" --version | head -1
        export PATH="${CLANG_PATH}:${PATH}"
        return
    fi

    print_info "Clang not found at $CLANG_BIN, downloading..."

    if ! curl -fL --retry 3 --retry-delay 5 \
        "$CLANG_DOWNLOAD_URL" \
        -o "$CLANG_TAR_FILE"; then
        print_error "Download failed! Check the URL/network and try again."
        rm -f "$CLANG_TAR_FILE"
        exit 1
    fi

    mkdir -p "$CLANG_INSTALL_DIR"

    print_info "Extracting toolchain..."
    if ! tar -xf "$CLANG_TAR_FILE" -C "$CLANG_INSTALL_DIR"; then
        print_error "Extraction failed! Tarball may be corrupt or incomplete."
        rm -f "$CLANG_TAR_FILE"
        exit 1
    fi

    if [ -x "$CLANG_BIN" ]; then
        print_success "Clang installed successfully!"
        "$CLANG_BIN" --version | head -1
        rm -f "$CLANG_TAR_FILE"
        export PATH="${CLANG_PATH}:${PATH}"
    else
        print_error "Install failed: clang binary not found in $CLANG_INSTALL_DIR"
        exit 1
    fi
}

check_clang() {
    print_info "Checking Clang toolchain..."
    if ! command -v clang &> /dev/null; then
        print_error "Clang not found in PATH!"
        exit 1
    fi
    echo -e "${GREEN}Using:$(which clang)${NC}"
    clang --version | head -1
}

setup_anykernel() {
    if [ ! -d "$ANYKERNEL_DIR" ]; then
        print_info "AnyKernel3 not found. Cloning..."
        git clone --depth=1 "$ANYKERNEL_REPO" -b "$ANYKERNEL_BRANCH" "$ANYKERNEL_DIR"
        print_success "AnyKernel3 cloned successfully."
        print_warning "Fresh clone detected — anykernel.sh still has EXAMPLE values"
        print_warning "(kernel.string, device.name1-5, BLOCK, etc.)."
        print_warning "You MUST edit $ANYKERNEL_DIR/anykernel.sh before flashing,"
        print_warning "or the zip will fail the device-check / not flash correctly."
    else
        print_info "AnyKernel3 already exists. Skipping clone."
    fi

    # Sanity check: warn (don't block) if anykernel.sh still looks like the default template
    if grep -q "device.name1=maguro" "$ANYKERNEL_DIR/anykernel.sh" 2>/dev/null; then
        print_warning "anykernel.sh still contains DEFAULT/example device names (maguro/toro/tuna)."
        print_warning "This zip will likely FAIL the device check on your phone."
        print_warning "Edit $ANYKERNEL_DIR/anykernel.sh: kernel.string, device.name1..5, BLOCK, IS_SLOT_DEVICE"
    fi
}

clean_build() {
    print_info "Cleaning previous build..."
    make O=$OUT_DIR clean
    print_success "Clean completed."
}

build_defconfig() {
    print_info "Applying defconfig..."
    make O=$OUT_DIR ARCH=arm64 \
        LLVM=1 \
        LLVM_IAS=1 \
        CC=${CLANG_PATH}/clang \
        LD=${CLANG_PATH}/ld.lld \
        AR=${CLANG_PATH}/llvm-ar \
        NM=${CLANG_PATH}/llvm-nm \
        STRIP=${CLANG_PATH}/llvm-strip \
        OBJCOPY=${CLANG_PATH}/llvm-objcopy \
        OBJDUMP=${CLANG_PATH}/llvm-objdump \
        READELF=${CLANG_PATH}/llvm-readelf \
        HOSTCC=${CLANG_PATH}/clang \
        HOSTCXX=${CLANG_PATH}/clang++ \
        HOSTLD=${CLANG_PATH}/ld.lld \
        HOSTAR=${CLANG_PATH}/llvm-ar \
        CROSS_COMPILE=aarch64-linux-gnu- \
        CROSS_COMPILE_ARM32=arm-linux-gnueabi- \
        LOCALVERSION="$LOCALVERSION" \
        KBUILD_BUILD_VERSION="" \
        CLANG_TRIPLE=aarch64-linux-gnu- \
        vendor/sdmsteppe-perf_defconfig vendor/phoenix.config

    print_success "Defconfig applied."
}

build_kernel() {
    print_info "Starting kernel build with $JOBS threads..."
    local START_TIME=$(date +%s)

    make -j$JOBS O=$OUT_DIR ARCH=arm64 \
        LLVM=1 \
        LLVM_IAS=1 \
        CC=${CLANG_PATH}/clang \
        LD=${CLANG_PATH}/ld.lld \
        AR=${CLANG_PATH}/llvm-ar \
        NM=${CLANG_PATH}/llvm-nm \
        STRIP=${CLANG_PATH}/llvm-strip \
        OBJCOPY=${CLANG_PATH}/llvm-objcopy \
        OBJDUMP=${CLANG_PATH}/llvm-objdump \
        READELF=${CLANG_PATH}/llvm-readelf \
        HOSTCC=${CLANG_PATH}/clang \
        HOSTCXX=${CLANG_PATH}/clang++ \
        HOSTLD=${CLANG_PATH}/ld.lld \
        HOSTAR=${CLANG_PATH}/llvm-ar \
        CROSS_COMPILE=aarch64-linux-gnu- \
        CROSS_COMPILE_ARM32=arm-linux-gnueabi- \
        LOCALVERSION="$LOCALVERSION" \
        CLANG_TRIPLE=aarch64-linux-gnu- \
        KBUILD_BUILD_VERSION=""

    local END_TIME=$(date +%s)
    local ELAPSED=$((END_TIME - START_TIME))
    print_success "Kernel build completed in $((ELAPSED / 60))m $((ELAPSED % 60))s!"
}

package_kernel() {
    print_info "Packaging kernel using AnyKernel3..."

    local IMAGE_GZ="$OUT_DIR/arch/arm64/boot/Image.gz"
    local DTBO_IMG="$OUT_DIR/arch/arm64/boot/dtbo.img"
    local DTS_DIR="$OUT_DIR/arch/arm64/boot/dts/qcom"

    if [ ! -f "$IMAGE_GZ" ]; then
        print_error "Image.gz not found! Build may have failed."
        exit 1
    fi

    # Dynamically find the DTB instead of a hardcoded (possibly wrong) filename.
    # Hardcoding a filename from another device's tree is a real risk of
    # packaging the wrong DTB and causing a bootloop.
    local DTB_COUNT
    DTB_COUNT=$(find "$DTS_DIR" -maxdepth 1 -name "*.dtb" 2>/dev/null | wc -l)

    if [ "$DTB_COUNT" -eq 0 ]; then
        print_error "No .dtb files found in $DTS_DIR! Build may have failed."
        exit 1
    elif [ "$DTB_COUNT" -gt 1 ]; then
        print_warning "Multiple .dtb files found in $DTS_DIR:"
        find "$DTS_DIR" -maxdepth 1 -name "*.dtb"
        print_warning "Using the first match. If this is wrong, set DTB manually in the script."
    fi
    local DTB
    DTB=$(find "$DTS_DIR" -maxdepth 1 -name "*.dtb" | head -1)
    print_info "Using DTB: $DTB"

    if [ ! -f "$DTBO_IMG" ]; then
        print_warning "dtbo.img not found at $DTBO_IMG — skipping (device may not need it)."
    fi

    # Move files to AnyKernel3
    cp "$IMAGE_GZ" "$ANYKERNEL_DIR/Image.gz"
    cp "$DTB" "$ANYKERNEL_DIR/dtb"
    [ -f "$DTBO_IMG" ] && cp "$DTBO_IMG" "$ANYKERNEL_DIR/dtbo.img"

    # Remove any stale zip from a previous run before creating a new one
    rm -f "$OUT_DIR/$FINAL_ZIP_NAME"

    cd "$ANYKERNEL_DIR"
    # Exclude .git and README.md per AnyKernel3's own recommended packaging command.
    # LICENSE must stay in the zip (required for redistribution).
    zip -r9 "../$OUT_DIR/$FINAL_ZIP_NAME" * -x .git README.md "*placeholder*"
    cd - > /dev/null

    # Cleanup
    rm -f "$ANYKERNEL_DIR/Image.gz"
    rm -f "$ANYKERNEL_DIR/dtb"
    rm -f "$ANYKERNEL_DIR/dtbo.img"

    print_success "Kernel packaged successfully!"
    print_success "Final ZIP: $OUT_DIR/$FINAL_ZIP_NAME"
}

# ------------------- Main -------------------

echo "=============================================="
echo "     SM6150 Kernel Build Script (Improved)"
echo "=============================================="

setup_clang
check_clang
setup_anykernel

if [ "$DO_CLEAN" -eq 1 ]; then
    print_info "'clean' argument detected — doing a full clean build."
    clean_build
else
    print_info "No 'clean' argument passed — skipping clean, reusing existing out/ dir."
    print_info "(Run 'sh build.sh clean' to force a clean build.)"
fi

build_defconfig
build_kernel
package_kernel

print_success "Build process completed successfully!"
