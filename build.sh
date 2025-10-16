#!/bin/bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  Infinix X6512 Kernel Builder              ${NC}"
echo -e "${BLUE}  with KernelSU Next Support                ${NC}"
echo -e "${BLUE}  ARM32 + Binder64 Configuration            ${NC}"
echo -e "${BLUE}============================================${NC}"

# Setup directories
KERNEL_DIR="$HOME/kernel"
DEVICE_TREE="$HOME/device_tree"
OUT_DIR="$HOME/out"
MKBOOTIMG="$HOME/mkbootimg_tools"
DATE=$(date +"%Y%m%d_%H%M%S")

mkdir -p $OUT_DIR

# Export build variables
export ARCH=arm
export SUBARCH=arm
export CROSS_COMPILE=/opt/toolchain/arm32/bin/arm-linux-androideabi-
export CROSS_COMPILE_ARM32=/opt/toolchain/arm32/bin/arm-linux-androideabi-
export CC=/opt/toolchain/clang/bin/clang
export CLANG_TRIPLE=arm-linux-gnueabi-
export AR=/opt/toolchain/clang/bin/llvm-ar
export NM=/opt/toolchain/clang/bin/llvm-nm
export OBJCOPY=/opt/toolchain/clang/bin/llvm-objcopy
export OBJDUMP=/opt/toolchain/clang/bin/llvm-objdump
export STRIP=/opt/toolchain/clang/bin/llvm-strip

# Step 1: Extract boot.img info from device tree
echo -e "${YELLOW}[1/7] Extracting device information...${NC}"
cd $DEVICE_TREE

# Get board config values
if [ -f "BoardConfig.mk" ]; then
    BOARD_KERNEL_CMDLINE=$(grep "BOARD_KERNEL_CMDLINE" BoardConfig.mk | cut -d "=" -f2- | xargs)
    BOARD_KERNEL_BASE=$(grep "BOARD_KERNEL_BASE" BoardConfig.mk | grep -oE "0x[0-9a-fA-F]+" | head -1)
    BOARD_KERNEL_PAGESIZE=$(grep "BOARD_KERNEL_PAGESIZE" BoardConfig.mk | grep -oE "[0-9]+" | head -1)
    BOARD_RAMDISK_OFFSET=$(grep "BOARD_RAMDISK_OFFSET" BoardConfig.mk | grep -oE "0x[0-9a-fA-F]+" | head -1)
    BOARD_KERNEL_OFFSET=$(grep "BOARD_KERNEL_OFFSET" BoardConfig.mk | grep -oE "0x[0-9a-fA-F]+" | head -1)
    BOARD_TAGS_OFFSET=$(grep "BOARD_TAGS_OFFSET" BoardConfig.mk | grep -oE "0x[0-9a-fA-F]+" | head -1)
    BOARD_DTB_OFFSET=$(grep "BOARD_DTB_OFFSET" BoardConfig.mk | grep -oE "0x[0-9a-fA-F]+" | head -1)
    BOARD_HEADER_VERSION=$(grep "BOARD_BOOTIMG_HEADER_VERSION" BoardConfig.mk | grep -oE "[0-9]+" | head -1)
fi

# Set default values if not found
BOARD_KERNEL_BASE=${BOARD_KERNEL_BASE:-0x40078000}
BOARD_KERNEL_PAGESIZE=${BOARD_KERNEL_PAGESIZE:-2048}
BOARD_RAMDISK_OFFSET=${BOARD_RAMDISK_OFFSET:-0x11a88000}
BOARD_KERNEL_OFFSET=${BOARD_KERNEL_OFFSET:-0x00008000}
BOARD_TAGS_OFFSET=${BOARD_TAGS_OFFSET:-0x13f88000}
BOARD_DTB_OFFSET=${BOARD_DTB_OFFSET:-0x13f88000}
BOARD_HEADER_VERSION=${BOARD_HEADER_VERSION:-2}

echo "Board Configuration:"
echo "  Base: $BOARD_KERNEL_BASE"
echo "  Page Size: $BOARD_KERNEL_PAGESIZE"
echo "  Ramdisk Offset: $BOARD_RAMDISK_OFFSET"
echo "  Kernel Offset: $BOARD_KERNEL_OFFSET"
echo "  Tags Offset: $BOARD_TAGS_OFFSET"
echo "  DTB Offset: $BOARD_DTB_OFFSET"
echo "  Header Version: $BOARD_HEADER_VERSION"

# Step 2: Extract prebuilt boot.img for ramdisk
echo -e "${YELLOW}[2/7] Extracting prebuilt boot.img...${NC}"
if [ -f "$DEVICE_TREE/prebuilt/boot.img" ]; then
    cp $DEVICE_TREE/prebuilt/boot.img $OUT_DIR/boot_stock.img
    cd $MKBOOTIMG
    python3 unpackbootimg.py -i $OUT_DIR/boot_stock.img -o $OUT_DIR/boot_extracted
    echo "Boot image extracted successfully"
else
    echo -e "${RED}Warning: Prebuilt boot.img not found, will create minimal ramdisk${NC}"
fi

# Step 3: Setup kernel config
echo -e "${YELLOW}[3/7] Setting up kernel configuration...${NC}"
cd $KERNEL_DIR

# Create defconfig for X6512
cat > arch/arm/configs/x6512_ksu_defconfig << 'EOF'
# Base configuration from device tree
CONFIG_LOCALVERSION="-X6512-KSU"
CONFIG_LOCALVERSION_AUTO=n

# ARM32 Configuration
CONFIG_ARM=y
CONFIG_ARM_ARCH=y
CONFIG_CPU_V7=y
CONFIG_AEABI=y

# MediaTek Platform
CONFIG_ARCH_MEDIATEK=y
CONFIG_MACH_MT6761=y
CONFIG_MTK_PLATFORM="mt6761"

# Android Binder - 64bit on ARM32
CONFIG_ANDROID=y
CONFIG_ANDROID_BINDER_IPC=y
CONFIG_ANDROID_BINDER_IPC_32BIT=n
CONFIG_ANDROID_BINDER_DEVICES="binder,hwbinder,vndbinder"
CONFIG_ANDROID_BINDERFS=n

# KernelSU Requirements
CONFIG_KPROBES=y
CONFIG_HAVE_KPROBES=y
CONFIG_KPROBE_EVENTS=y
CONFIG_MODULES=y
CONFIG_MODULE_UNLOAD=y
CONFIG_MODULE_FORCE_UNLOAD=y

# Security features
CONFIG_SECURITY=y
CONFIG_SECURITY_SELINUX=y
CONFIG_SECURITY_NETWORK=y

# File systems
CONFIG_EXT4_FS=y
CONFIG_F2FS_FS=y
CONFIG_VFAT_FS=y
CONFIG_TMPFS=y
CONFIG_SDCARD_FS=y

# Network
CONFIG_NETFILTER=y
CONFIG_IP_NF_IPTABLES=y
CONFIG_IP_NF_FILTER=y
CONFIG_IP_NF_TARGET_REJECT=y
CONFIG_IP_NF_NAT=y
CONFIG_IP_NF_TARGET_MASQUERADE=y
CONFIG_IP_NF_MANGLE=y
CONFIG_IP_NF_RAW=y

# USB
CONFIG_USB=y
CONFIG_USB_GADGET=y
CONFIG_USB_CONFIGFS=y
CONFIG_USB_CONFIGFS_F_FS=y
CONFIG_USB_CONFIGFS_F_MTP=y
CONFIG_USB_CONFIGFS_F_PTP=y
CONFIG_USB_CONFIGFS_F_ACC=y
CONFIG_USB_CONFIGFS_F_AUDIO_SRC=y
CONFIG_USB_CONFIGFS_UEVENT=y

# Power Management
CONFIG_PM=y
CONFIG_PM_SLEEP=y
CONFIG_PM_WAKELOCKS=y
CONFIG_PM_WAKELOCKS_LIMIT=0
CONFIG_PM_WAKELOCKS_GC=y
CONFIG_SUSPEND=y
CONFIG_SUSPEND_FREEZER=y
CONFIG_WAKELOCK=y

# CPU Governors
CONFIG_CPU_FREQ=y
CONFIG_CPU_FREQ_DEFAULT_GOV_INTERACTIVE=y
CONFIG_CPU_FREQ_GOV_PERFORMANCE=y
CONFIG_CPU_FREQ_GOV_POWERSAVE=y
CONFIG_CPU_FREQ_GOV_USERSPACE=y
CONFIG_CPU_FREQ_GOV_ONDEMAND=y
CONFIG_CPU_FREQ_GOV_CONSERVATIVE=y

# I/O Schedulers
CONFIG_IOSCHED_NOOP=y
CONFIG_IOSCHED_DEADLINE=y
CONFIG_IOSCHED_CFQ=y
CONFIG_DEFAULT_CFQ=y

# Infinix X6512 specific
CONFIG_TOUCHSCREEN_MTK=y
CONFIG_MTK_FINGERPRINT_SUPPORT=y
CONFIG_MTK_SENSOR_SUPPORT=y
CONFIG_CUSTOM_KERNEL_ACCELEROMETER=y
CONFIG_CUSTOM_KERNEL_ALSPS=y
CONFIG_CUSTOM_KERNEL_MAGNETOMETER=y
EOF

# Merge with existing MediaTek defconfig if exists
if [ -f "arch/arm/configs/mt6761_defconfig" ]; then
    echo -e "${YELLOW}Merging with MT6761 base config...${NC}"
    cat arch/arm/configs/mt6761_defconfig >> arch/arm/configs/x6512_ksu_defconfig
    # Remove duplicates
    sort -u arch/arm/configs/x6512_ksu_defconfig > arch/arm/configs/x6512_ksu_defconfig.tmp
    mv arch/arm/configs/x6512_ksu_defconfig.tmp arch/arm/configs/x6512_ksu_defconfig
fi

# Step 4: Apply KernelSU Next
echo -e "${YELLOW}[4/7] Applying KernelSU Next...${NC}"
cd $KERNEL_DIR

# Download and apply KernelSU Next
curl -LSs "https://raw.githubusercontent.com/tiann/KernelSU/main/kernel/setup.sh" | bash -s next

# Additional patches for ARM32
if [ -d "KernelSU" ]; then
    echo "KernelSU Next integrated successfully"
    # Apply ARM32 specific patches if needed
    if [ -f "KernelSU/kernel/sucompat.c" ]; then
        sed -i 's/CONFIG_COMPAT/CONFIG_ARM/g' KernelSU/kernel/sucompat.c 2>/dev/null || true
    fi
fi

# Step 5: Build kernel
echo -e "${YELLOW}[5/7] Building kernel...${NC}"
cd $KERNEL_DIR

# Clean build
make clean && make mrproper

# Configure
make O=out ARCH=arm x6512_ksu_defconfig

# Build
make -j$(nproc --all) O=out \
    ARCH=arm \
    SUBARCH=arm \
    CC=clang \
    CROSS_COMPILE=arm-linux-androideabi- \
    CROSS_COMPILE_ARM32=arm-linux-androideabi- \
    CLANG_TRIPLE=arm-linux-gnueabi- \
    2>&1 | tee $OUT_DIR/build_kernel.log

# Check build result
if [ ! -f "out/arch/arm/boot/zImage" ]; then
    echo -e "${RED}Kernel build failed! Check build_kernel.log${NC}"
    exit 1
fi

echo -e "${GREEN}Kernel built successfully!${NC}"

# Step 6: Prepare DTB
echo -e "${YELLOW}[6/7] Preparing DTB...${NC}"
if [ -f "out/arch/arm/boot/dts/mediatek/mt6761.dtb" ]; then
    cp out/arch/arm/boot/dts/mediatek/mt6761.dtb $OUT_DIR/dtb
elif [ -f "$DEVICE_TREE/prebuilt/dtb.img" ]; then
    cp $DEVICE_TREE/prebuilt/dtb.img $OUT_DIR/dtb
elif [ -f "$OUT_DIR/boot_extracted/boot_stock.img-dtb" ]; then
    cp $OUT_DIR/boot_extracted/boot_stock.img-dtb $OUT_DIR/dtb
else
    echo -e "${YELLOW}No DTB found, appending to kernel...${NC}"
    cat out/arch/arm/boot/zImage out/arch/arm/boot/dts/mediatek/*.dtb > out/arch/arm/boot/zImage-dtb 2>/dev/null || true
fi

# Step 7: Create boot.img
echo -e "${YELLOW}[7/7] Creating boot.img...${NC}"
cd $MKBOOTIMG

# Copy kernel
if [ -f "$KERNEL_DIR/out/arch/arm/boot/zImage-dtb" ]; then
    KERNEL_IMAGE="$KERNEL_DIR/out/arch/arm/boot/zImage-dtb"
else
    KERNEL_IMAGE="$KERNEL_DIR/out/arch/arm/boot/zImage"
fi

# Prepare ramdisk
if [ -f "$OUT_DIR/boot_extracted/boot_stock.img-ramdisk.gz" ]; then
    RAMDISK="$OUT_DIR/boot_extracted/boot_stock.img-ramdisk.gz"
    echo "Using stock ramdisk"
else
    # Create minimal ramdisk
    echo -e "${YELLOW}Creating minimal ramdisk...${NC}"
    mkdir -p $OUT_DIR/ramdisk
    cd $OUT_DIR/ramdisk
    mkdir -p dev proc sys
    find . | cpio -o -H newc | gzip > $OUT_DIR/ramdisk.cpio.gz
    RAMDISK="$OUT_DIR/ramdisk.cpio.gz"
    cd $MKBOOTIMG
fi

# Build boot.img based on header version
BOOT_IMG_NAME="boot_ksu_${DATE}.img"

if [ "$BOARD_HEADER_VERSION" == "2" ]; then
    # Header version 2
    python3 mkbootimg.py \
        --kernel $KERNEL_IMAGE \
        --ramdisk $RAMDISK \
        --base $BOARD_KERNEL_BASE \
        --kernel_offset $BOARD_KERNEL_OFFSET \
        --ramdisk_offset $BOARD_RAMDISK_OFFSET \
        --tags_offset $BOARD_TAGS_OFFSET \
        --dtb_offset $BOARD_DTB_OFFSET \
        --pagesize $BOARD_KERNEL_PAGESIZE \
        --header_version $BOARD_HEADER_VERSION \
        --cmdline "$BOARD_KERNEL_CMDLINE" \
        --os_version "11.0.0" \
        --os_patch_level "2023-01" \
        --output $OUT_DIR/$BOOT_IMG_NAME
        
    # Add DTB if exists and not already appended
    if [ -f "$OUT_DIR/dtb" ] && [ ! -f "$KERNEL_DIR/out/arch/arm/boot/zImage-dtb" ]; then
        python3 mkbootimg.py \
            --kernel $KERNEL_IMAGE \
            --ramdisk $RAMDISK \
            --dtb $OUT_DIR/dtb \
            --base $BOARD_KERNEL_BASE \
            --kernel_offset $BOARD_KERNEL_OFFSET \
            --ramdisk_offset $BOARD_RAMDISK_OFFSET \
            --tags_offset $BOARD_TAGS_OFFSET \
            --dtb_offset $BOARD_DTB_OFFSET \
            --pagesize $BOARD_KERNEL_PAGESIZE \
            --header_version $BOARD_HEADER_VERSION \
            --cmdline "$BOARD_KERNEL_CMDLINE" \
            --os_version "11.0.0" \
            --os_patch_level "2023-01" \
            --output $OUT_DIR/${BOOT_IMG_NAME}
    fi
else
    # Header version 0 or 1
    python3 mkbootimg.py \
        --kernel $KERNEL_IMAGE \
        --ramdisk $RAMDISK \
        --base $BOARD_KERNEL_BASE \
        --kernel_offset $BOARD_KERNEL_OFFSET \
        --ramdisk_offset $BOARD_RAMDISK_OFFSET \
        --tags_offset $BOARD_TAGS_OFFSET \
        --pagesize $BOARD_KERNEL_PAGESIZE \
        --cmdline "$BOARD_KERNEL_CMDLINE" \
        --output $OUT_DIR/$BOOT_IMG_NAME
fi

# Verify boot.img
if [ -f "$OUT_DIR/$BOOT_IMG_NAME" ]; then
    echo -e "${GREEN}============================================${NC}"
    echo -e "${GREEN}Boot image created successfully!${NC}"
    echo -e "${GREEN}File: $BOOT_IMG_NAME${NC}"
    echo -e "${GREEN}Size: $(du -h $OUT_DIR/$BOOT_IMG_NAME | cut -f1)${NC}"
    echo -e "${GREEN}============================================${NC}"
    
    # Create info file
    cat > $OUT_DIR/build_info.txt << EOL
Build Information
=================
Device: Infinix X6512
Kernel Version: 4.19.127
Architecture: ARM32 + Binder64
KernelSU: Next
Build Date: $(date)
Boot Image: $BOOT_IMG_NAME

Board Configuration:
- Base: $BOARD_KERNEL_BASE
- Page Size: $BOARD_KERNEL_PAGESIZE
- Ramdisk Offset: $BOARD_RAMDISK_OFFSET
- Kernel Offset: $BOARD_KERNEL_OFFSET
- Tags Offset: $BOARD_TAGS_OFFSET
- DTB Offset: $BOARD_DTB_OFFSET
- Header Version: $BOARD_HEADER_VERSION

Flashing Instructions:
1. Boot to fastboot mode
2. Run: fastboot flash boot $BOOT_IMG_NAME
3. Run: fastboot reboot
EOL
    
    ls -lah $OUT_DIR/
else
    echo -e "${RED}Failed to create boot.img!${NC}"
    exit 1
fi

echo -e "${GREEN}Build completed successfully!${NC}"
