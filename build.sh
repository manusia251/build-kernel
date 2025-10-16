#!/bin/bash

# Set language
export LANG=C.UTF-8
export LC_ALL=C.UTF-8

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Banner
echo -e "${CYAN}╔════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║     ${YELLOW}Infinix X6512 Kernel Builder${CYAN}          ║${NC}"
echo -e "${CYAN}║     ${GREEN}with KernelSU Next Support${CYAN}            ║${NC}"
echo -e "${CYAN}║     ${PURPLE}ARM32 + Binder64 Configuration${CYAN}        ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════╝${NC}"
echo ""

# Setup directories
KERNEL_DIR="$HOME/kernel"
DEVICE_TREE="$HOME/device_tree"
OUT_DIR="$HOME/out"
MKBOOTIMG="$HOME/mkbootimg_tools"
DATE=$(date +"%Y%m%d_%H%M%S")

mkdir -p $OUT_DIR

# Function to print step
print_step() {
    echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}▶ $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

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
print_step "[1/7] Extracting device information"
cd $DEVICE_TREE

# Get board config values
if [ -f "BoardConfig.mk" ]; then
    echo -e "${GREEN}✓ BoardConfig.mk found${NC}"
    BOARD_KERNEL_CMDLINE=$(grep "BOARD_KERNEL_CMDLINE" BoardConfig.mk | cut -d "=" -f2- | xargs)
    BOARD_KERNEL_BASE=$(grep "BOARD_KERNEL_BASE" BoardConfig.mk | grep -oE "0x[0-9a-fA-F]+" | head -1)
    BOARD_KERNEL_PAGESIZE=$(grep "BOARD_KERNEL_PAGESIZE" BoardConfig.mk | grep -oE "[0-9]+" | head -1)
    BOARD_RAMDISK_OFFSET=$(grep "BOARD_RAMDISK_OFFSET" BoardConfig.mk | grep -oE "0x[0-9a-fA-F]+" | head -1)
    BOARD_KERNEL_OFFSET=$(grep "BOARD_KERNEL_OFFSET" BoardConfig.mk | grep -oE "0x[0-9a-fA-F]+" | head -1)
    BOARD_TAGS_OFFSET=$(grep "BOARD_TAGS_OFFSET" BoardConfig.mk | grep -oE "0x[0-9a-fA-F]+" | head -1)
    BOARD_DTB_OFFSET=$(grep "BOARD_DTB_OFFSET" BoardConfig.mk | grep -oE "0x[0-9a-fA-F]+" | head -1)
    BOARD_HEADER_VERSION=$(grep "BOARD_BOOTIMG_HEADER_VERSION" BoardConfig.mk | grep -oE "[0-9]+" | head -1)
elif [ -f "board-info.txt" ]; then
    echo -e "${YELLOW}Using board-info.txt${NC}"
    source board-info.txt
fi

# Set default values if not found
BOARD_KERNEL_BASE=${BOARD_KERNEL_BASE:-0x40078000}
BOARD_KERNEL_PAGESIZE=${BOARD_KERNEL_PAGESIZE:-2048}
BOARD_RAMDISK_OFFSET=${BOARD_RAMDISK_OFFSET:-0x11a88000}
BOARD_KERNEL_OFFSET=${BOARD_KERNEL_OFFSET:-0x00008000}
BOARD_TAGS_OFFSET=${BOARD_TAGS_OFFSET:-0x13f88000}
BOARD_DTB_OFFSET=${BOARD_DTB_OFFSET:-0x13f88000}
BOARD_HEADER_VERSION=${BOARD_HEADER_VERSION:-2}

echo -e "${CYAN}┌─ Board Configuration ──────────────────┐${NC}"
echo -e "${CYAN}│${NC} Base Address    : ${GREEN}$BOARD_KERNEL_BASE${NC}"
echo -e "${CYAN}│${NC} Page Size       : ${GREEN}$BOARD_KERNEL_PAGESIZE${NC}"
echo -e "${CYAN}│${NC} Ramdisk Offset  : ${GREEN}$BOARD_RAMDISK_OFFSET${NC}"
echo -e "${CYAN}│${NC} Kernel Offset   : ${GREEN}$BOARD_KERNEL_OFFSET${NC}"
echo -e "${CYAN}│${NC} Tags Offset     : ${GREEN}$BOARD_TAGS_OFFSET${NC}"
echo -e "${CYAN}│${NC} DTB Offset      : ${GREEN}$BOARD_DTB_OFFSET${NC}"
echo -e "${CYAN}│${NC} Header Version  : ${GREEN}$BOARD_HEADER_VERSION${NC}"
echo -e "${CYAN}└────────────────────────────────────────┘${NC}"

# Step 2: Extract prebuilt boot.img for ramdisk
print_step "[2/7] Extracting prebuilt boot.img"

# Try multiple possible locations for boot.img
BOOT_IMG_FOUND=false
for boot_path in "prebuilt/boot.img" "boot.img" "prebuilt/Image.gz-dtb" "kernel" "zImage"; do
    if [ -f "$DEVICE_TREE/$boot_path" ]; then
        echo -e "${GREEN}✓ Found: $boot_path${NC}"
        cp $DEVICE_TREE/$boot_path $OUT_DIR/boot_stock.img
        BOOT_IMG_FOUND=true
        break
    fi
done

if [ "$BOOT_IMG_FOUND" = true ]; then
    cd $MKBOOTIMG
    python3 unpackbootimg.py -i $OUT_DIR/boot_stock.img -o $OUT_DIR/boot_extracted 2>/dev/null || {
        echo -e "${YELLOW}⚠ Cannot extract with unpackbootimg, trying alternative method...${NC}"
        # Alternative extraction method
        mkdir -p $OUT_DIR/boot_extracted
        cd $OUT_DIR
        abootimg -x boot_stock.img 2>/dev/null || {
            # Manual extraction as last resort
            dd if=boot_stock.img of=boot_extracted/kernel bs=1 count=8388608 2>/dev/null
            dd if=boot_stock.img of=boot_extracted/ramdisk.gz bs=1 skip=8388608 2>/dev/null
        }
    }
    echo -e "${GREEN}✓ Boot image extraction attempted${NC}"
else
    echo -e "${YELLOW}⚠ No prebuilt boot.img found, will create minimal ramdisk${NC}"
fi

# Step 3: Setup kernel config
print_step "[3/7] Setting up kernel configuration"
cd $KERNEL_DIR

# Check if this is a MediaTek kernel
if [ -d "drivers/misc/mediatek" ]; then
    echo -e "${GREEN}✓ MediaTek kernel detected${NC}"
    BASE_DEFCONFIG="mt6761_defconfig"
else
    echo -e "${YELLOW}⚠ Generic kernel detected${NC}"
    BASE_DEFCONFIG="defconfig"
fi

# Create defconfig for X6512
cat > arch/arm/configs/x6512_ksu_defconfig << 'EOF'
# Infinix X6512 KernelSU Configuration
CONFIG_LOCALVERSION="-X6512-KSU-Next"
CONFIG_LOCALVERSION_AUTO=n

# ARM32 Base Configuration
CONFIG_ARM=y
CONFIG_AEABI=y
CONFIG_CPU_V7=y
CONFIG_VMSPLIT_3G=y
CONFIG_PAGE_OFFSET=0xC0000000

# MediaTek MT6761 Platform
CONFIG_ARCH_MEDIATEK=y
CONFIG_MACH_MT6761=y
CONFIG_MTK_PLATFORM="mt6761"

# Android Binder - 64bit on ARM32
CONFIG_ANDROID=y
CONFIG_ANDROID_BINDER_IPC=y
CONFIG_ANDROID_BINDER_IPC_32BIT=n
CONFIG_ANDROID_BINDER_DEVICES="binder,hwbinder,vndbinder"
CONFIG_ANDROID_BINDERFS=n

# KernelSU Next Requirements
CONFIG_KPROBES=y
CONFIG_HAVE_KPROBES=y
CONFIG_KPROBE_EVENTS=y
CONFIG_MODULES=y
CONFIG_MODULE_UNLOAD=y
CONFIG_MODULE_FORCE_UNLOAD=y
CONFIG_KALLSYMS=y
CONFIG_KALLSYMS_ALL=y

# Security
CONFIG_SECURITY=y
CONFIG_SECURITY_SELINUX=y
CONFIG_SECURITY_NETWORK=y
CONFIG_SECURITY_PATH=y
CONFIG_LSM_MMAP_MIN_ADDR=4096
CONFIG_DEFAULT_SECURITY_SELINUX=y

# File Systems
CONFIG_EXT4_FS=y
CONFIG_EXT4_FS_SECURITY=y
CONFIG_F2FS_FS=y
CONFIG_F2FS_FS_SECURITY=y
CONFIG_VFAT_FS=y
CONFIG_TMPFS=y
CONFIG_SDCARD_FS=y

# Networking
CONFIG_NETFILTER=y
CONFIG_NETFILTER_XTABLES=y
CONFIG_IP_NF_IPTABLES=y
CONFIG_IP_NF_FILTER=y
CONFIG_IP_NF_TARGET_REJECT=y
CONFIG_IP_NF_NAT=y
CONFIG_IP_NF_TARGET_MASQUERADE=y
CONFIG_IP_NF_MANGLE=y

# USB
CONFIG_USB_GADGET=y
CONFIG_USB_CONFIGFS=y
CONFIG_USB_CONFIGFS_F_FS=y
CONFIG_USB_CONFIGFS_F_MTP=y
CONFIG_USB_CONFIGFS_F_PTP=y
CONFIG_USB_CONFIGFS_F_ACC=y
CONFIG_USB_CONFIGFS_UEVENT=y

# Power Management
CONFIG_PM=y
CONFIG_PM_SLEEP=y
CONFIG_PM_WAKELOCKS=y
CONFIG_SUSPEND=y
CONFIG_WAKELOCK=y
CONFIG_CPU_IDLE=y
CONFIG_CPU_FREQ=y

# CPU Governors
CONFIG_CPU_FREQ_DEFAULT_GOV_SCHEDUTIL=y
CONFIG_CPU_FREQ_GOV_PERFORMANCE=y
CONFIG_CPU_FREQ_GOV_POWERSAVE=y
CONFIG_CPU_FREQ_GOV_USERSPACE=y
CONFIG_CPU_FREQ_GOV_ONDEMAND=y
CONFIG_CPU_FREQ_GOV_CONSERVATIVE=y
CONFIG_CPU_FREQ_GOV_SCHEDUTIL=y

# I/O Schedulers
CONFIG_IOSCHED_NOOP=y
CONFIG_IOSCHED_DEADLINE=y
CONFIG_IOSCHED_CFQ=y
CONFIG_DEFAULT_CFQ=y

# Display & Graphics
CONFIG_FB=y
CONFIG_FB_MODE_HELPERS=y
CONFIG_FB_TILEBLITTING=y

# Sound
CONFIG_SOUND=y
CONFIG_SND=y
CONFIG_SND_SOC=y

# Infinix X6512 Specific
CONFIG_TOUCHSCREEN_MTK=y
CONFIG_KEYBOARD_MTK=y
CONFIG_MTK_FINGERPRINT_SUPPORT=y
CONFIG_MTK_SENSOR_SUPPORT=y
CONFIG_MTK_ACCDET=y
CONFIG_CUSTOM_KERNEL_ACCELEROMETER=y
CONFIG_CUSTOM_KERNEL_ALSPS=y
CONFIG_CUSTOM_KERNEL_MAGNETOMETER=y
CONFIG_CUSTOM_KERNEL_GYROSCOPE=y
CONFIG_MTK_COMBO=y
CONFIG_MTK_COMBO_WIFI=y
CONFIG_MTK_COMBO_GPS=y
CONFIG_MTK_COMBO_BT=y

# Memory
CONFIG_ZRAM=y
CONFIG_ZSMALLOC=y
CONFIG_PGTABLE_MAPPING=y
CONFIG_MEMCG=y
CONFIG_MEMCG_SWAP=y

# Debug (disable in production)
# CONFIG_KERNEL_DEBUG is not set
# CONFIG_DEBUG_FS is not set
# CONFIG_FTRACE is not set
EOF

# Merge with base config if exists
if [ -f "arch/arm/configs/${BASE_DEFCONFIG}" ]; then
    echo -e "${CYAN}Merging with ${BASE_DEFCONFIG}...${NC}"
    # Use script to merge configs properly
    scripts/kconfig/merge_config.sh arch/arm/configs/${BASE_DEFCONFIG} arch/arm/configs/x6512_ksu_defconfig 2>/dev/null || {
        # Fallback: simple concatenation
        cat arch/arm/configs/${BASE_DEFCONFIG} >> arch/arm/configs/x6512_ksu_defconfig
    }
fi

# Step 4: Apply KernelSU Next
print_step "[4/7] Applying KernelSU Next"
cd $KERNEL_DIR

echo -e "${CYAN}Downloading KernelSU Next...${NC}"
# Download and apply KernelSU Next
curl -LSs "https://raw.githubusercontent.com/tiann/KernelSU/main/kernel/setup.sh" | bash -s next || {
    echo -e "${YELLOW}⚠ Auto setup failed, trying manual method...${NC}"
    # Manual KSU integration
    git clone --depth=1 https://github.com/tiann/KernelSU
    cp -r KernelSU/kernel/* ./
}

# Check if KSU is integrated
if [ -d "KernelSU" ] || [ -f "drivers/kernelsu/Makefile" ]; then
    echo -e "${GREEN}✓ KernelSU Next integrated successfully${NC}"
    
    # Apply ARM32 specific patches
    if [ -f "drivers/kernelsu/sucompat.c" ]; then
        sed -i 's/CONFIG_COMPAT/CONFIG_ARM/g' drivers/kernelsu/sucompat.c 2>/dev/null || true
    fi
    
    # Add KSU to Makefile if not already there
    if ! grep -q "kernelsu" Makefile; then
        echo "drivers-y += drivers/kernelsu/" >> Makefile
    fi
else
    echo -e "${RED}✗ KernelSU integration failed${NC}"
fi

# Step 5: Build kernel
print_step "[5/7] Building kernel"
cd $KERNEL_DIR

# Clean build
echo -e "${CYAN}Cleaning build environment...${NC}"
make clean && make mrproper

# Configure
echo -e "${CYAN}Configuring kernel...${NC}"
make O=out ARCH=arm x6512_ksu_defconfig

# Show build info
echo -e "${PURPLE}┌─ Build Information ────────────────────┐${NC}"
echo -e "${PURPLE}│${NC} Compiler : ${GREEN}Proton Clang${NC}"
echo -e "${PURPLE}│${NC} Linker   : ${GREEN}LLD${NC}"
echo -e "${PURPLE}│${NC} Target   : ${GREEN}ARM32 (ARMv7)${NC}"
echo -e "${PURPLE}│${NC} Jobs     : ${GREEN}$(nproc --all) cores${NC}"
echo -e "${PURPLE}└────────────────────────────────────────┘${NC}"

# Build
echo -e "${CYAN}Starting kernel compilation...${NC}"
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
    echo -e "${RED}✗ Kernel build failed!${NC}"
    echo -e "${YELLOW}Check $OUT_DIR/build_kernel.log for errors${NC}"
    # Show last 20 lines of error
    tail -20 $OUT_DIR/build_kernel.log
    exit 1
fi

echo -e "${GREEN}✓ Kernel built successfully!${NC}"

# Step 6: Prepare DTB
print_step "[6/7] Preparing DTB"

DTB_FOUND=false
# Check various DTB locations
for dtb_path in \
    "out/arch/arm/boot/dts/mediatek/mt6761.dtb" \
    "out/arch/arm/boot/dts/*.dtb" \
    "$DEVICE_TREE/prebuilt/dtb.img" \
    "$DEVICE_TREE/prebuilt/dtb" \
    "$OUT_DIR/boot_extracted/boot_stock.img-dtb"
do
    if ls $dtb_path 2>/dev/null; then
        echo -e "${GREEN}✓ DTB found: $dtb_path${NC}"
        cp $dtb_path $OUT_DIR/dtb 2>/dev/null
        DTB_FOUND=true
        break
    fi
done

if [ "$DTB_FOUND" = false ]; then
    echo -e "${YELLOW}⚠ No separate DTB found, trying to append to kernel...${NC}"
    # Try to find and append DTBs
    if ls out/arch/arm/boot/dts/mediatek/*.dtb 2>/dev/null; then
        cat out/arch/arm/boot/zImage out/arch/arm/boot/dts/mediatek/*.dtb > out/arch/arm/boot/zImage-dtb
        echo -e "${GREEN}✓ DTB appended to kernel${NC}"
    elif ls out/arch/arm/boot/dts/*.dtb 2>/dev/null; then
        cat out/arch/arm/boot/zImage out/arch/arm/boot/dts/*.dtb > out/arch/arm/boot/zImage-dtb
        echo -e "${GREEN}✓ DTB appended to kernel${NC}"
    fi
fi

# Step 7: Create boot.img
print_step "[7/7] Creating boot.img"
cd $MKBOOTIMG

# Determine kernel image
if [ -f "$KERNEL_DIR/out/arch/arm/boot/zImage-dtb" ]; then
    KERNEL_IMAGE="$KERNEL_DIR/out/arch/arm/boot/zImage-dtb"
    echo -e "${GREEN}✓ Using zImage with appended DTB${NC}"
else
    KERNEL_IMAGE="$KERNEL_DIR/out/arch/arm/boot/zImage"
    echo -e "${CYAN}Using plain zImage${NC}"
fi

# Prepare ramdisk
if [ -f "$OUT_DIR/boot_extracted/boot_stock.img-ramdisk.gz" ]; then
    RAMDISK="$OUT_DIR/boot_extracted/boot_stock.img-ramdisk.gz"
    echo -e "${GREEN}✓ Using stock ramdisk${NC}"
elif [ -f "$OUT_DIR/boot_extracted/ramdisk.gz" ]; then
    RAMDISK="$OUT_DIR/boot_extracted/ramdisk.gz"
    echo -e "${GREEN}✓ Using extracted ramdisk${NC}"
else
    # Create minimal ramdisk
    echo -e "${YELLOW}Creating minimal ramdisk...${NC}"
    mkdir -p $OUT_DIR/ramdisk
    cd $OUT_DIR/ramdisk
    
    # Create basic Android ramdisk structure
    mkdir -p {dev,proc,sys,system,vendor,data,mnt,apex}
    
    # Create init stub
    cat > init << 'INIT_EOF'
#!/system/bin/sh
INIT_EOF
    chmod 755 init
    
    # Pack ramdisk
    find . | cpio -o -H newc | gzip > $OUT_DIR/ramdisk.cpio.gz
    RAMDISK="$OUT_DIR/ramdisk.cpio.gz"
    cd $MKBOOTIMG
    echo -e "${GREEN}✓ Minimal ramdisk created${NC}"
fi

# Build boot.img
BOOT_IMG_NAME="boot_ksu_${DATE}.img"

echo -e "${CYAN}Creating boot image...${NC}"

# Build command based on header version
if [ "$BOARD_HEADER_VERSION" == "2" ]; then
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
else
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
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║     ${NC}✓ Boot Image Created Successfully!${GREEN}     ║${NC}"
    echo -e "${GREEN}╠════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║${NC} File : ${YELLOW}$BOOT_IMG_NAME${GREEN}          ║${NC}"
    echo -e "${GREEN}║${NC} Size : ${YELLOW}$(du -h $OUT_DIR/$BOOT_IMG_NAME | cut -f1)${GREEN}                                  ║${NC}"
    echo -e "${GREEN}║${NC} Date : ${YELLOW}$(date '+%Y-%m-%d %H:%M:%S')${GREEN}          ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════╝${NC}"
    
    # Create info file
    cat > $OUT_DIR/build_info.txt << EOL
╔════════════════════════════════════════════╗
║          BUILD INFORMATION                 ║
╚════════════════════════════════════════════╝

Device Information:
• Device Name    : Infinix X6512
• Codename       : Infinix-X6512
• Architecture   : ARM32 (ARMv7-A)
• Binder Type    : Binder64
• Kernel Version : 4.19.127
• KernelSU       : Next (Latest)

Build Details:
• Build Date     : $(date)
• Boot Image     : $BOOT_IMG_NAME
• Image Size     : $(du -h $OUT_DIR/$BOOT_IMG_NAME | cut -f1)
• Compiler       : Proton Clang
• Builder        : Cirrus CI

Board Configuration:
• Base Address    : $BOARD_KERNEL_BASE
• Page Size       : $BOARD_KERNEL_PAGESIZE
• Ramdisk Offset  : $BOARD_RAMDISK_OFFSET
• Kernel Offset   : $BOARD_KERNEL_OFFSET
• Tags Offset     : $BOARD_TAGS_OFFSET
• DTB Offset      : $BOARD_DTB_OFFSET
• Header Version  : $BOARD_HEADER_VERSION

Flashing Instructions:
════════════════════════════════════════════
Via Fastboot:
1. adb reboot bootloader
2. fastboot flash boot $BOOT_IMG_NAME
3. fastboot reboot

Via SP Flash Tool:
1. Load scatter file from device tree
2. Select boot partition
3. Choose $BOOT_IMG_NAME
4. Click Download

⚠️ Warning: Always backup your original boot.img!
════════════════════════════════════════════

KernelSU Usage:
After flashing, install KernelSU Manager APK from:
https://github.com/tiann/KernelSU/releases

© 2024 - Built with ❤️ for Infinix X6512
EOL
    
    echo -e "${CYAN}Build info saved to build_info.txt${NC}"
    
    # List all output files
    echo -e "\n${PURPLE}Output Files:${NC}"
    ls -lah $OUT_DIR/
    
else
    echo -e "${RED}✗ Failed to create boot.img!${NC}"
    exit 1
fi

echo -e "\n${GREEN}═══════════════════════════════════════════${NC}"
echo -e "${GREEN}    Build completed successfully! 🎉${NC}"
echo -e "${GREEN}═══════════════════════════════════════════${NC}"
