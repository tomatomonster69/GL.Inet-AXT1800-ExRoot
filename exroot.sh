#!/bin/sh
#==============================================================================
# GL.iNet AXT1800 Extroot SD Card Setup Script
# Corrected version for already partitioned SD card
#==============================================================================

set -e

# Configuration
SWAP_SIZE_MB=1024
LOG_FILE="/tmp/extroot_setup.log"
BACKUP_DIR="/tmp/overlay_backup"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

#==============================================================================
# Logging function
#==============================================================================
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

log_warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

#==============================================================================
# Error handling
#==============================================================================
error_exit() {
    log_error "$1"
    log "Check log file: $LOG_FILE"
    exit 1
}

#==============================================================================
# STEP 0: Pre-flight checks
#==============================================================================
preflight_checks() {
    log "Starting pre-flight checks..."
    
    # Check if running as root
    if [ "$(id -u)" -ne 0 ]; then
        error_exit "This script must be run as root"
    fi
    
    # Check model
    MODEL_INFO=""
    if [ -f "/tmp/sysinfo/model" ]; then
        MODEL_INFO=$(cat /tmp/sysinfo/model)
    elif [ -f "/proc/cpuinfo" ]; then
        MODEL_INFO=$(grep "machine" /proc/cpuinfo | head -1)
    fi
    
    if echo "$MODEL_INFO" | grep -qi "axt1800\|slate"; then
        log "Detected model: $MODEL_INFO"
    else
        log_warn "Could not confirm GL-AXT1800 model. Detected: $MODEL_INFO. Proceeding anyway..."
    fi
    
    # Warn about hot-plug limitation [8]
    log_warn "IMPORTANT: Hot plug for MicroSD card is NOT supported on this router!" [8]
    log_warn "Make sure SD card was inserted BEFORE powering on the router." [8]
    
    log_success "Pre-flight checks completed"
}

#==============================================================================
# Detect SD Card Device (corrected logic)
#==============================================================================
detect_sd_device() {
    log "Detecting SD card device..."
    
    # Check if SD card is already partitioned
    if [ -b "/dev/mmcblk0" ] && ([ -b "/dev/mmcblk0p1" ] || [ -b "/dev/mmcblk0p2" ]); then
        log "Found existing SD card with partitions:"
        ls -la /dev/mmcblk0* 2>/dev/null || true
        SD_DEVICE="/dev/mmcblk0"
        export SD_DEVICE
        log_success "Using existing SD card device: $SD_DEVICE"
        return 0
    fi
    
    # If no partitions exist, check for unpartitioned device
    if [ -b "/dev/mmcblk0" ]; then
        SIZE_BYTES=$(blockdev --getsize64 "/dev/mmcblk0" 2>/dev/null || echo "0")
        SIZE_GB=$((SIZE_BYTES / 1024 / 1024 / 1024))
        
        if [ "$SIZE_GB" -ge 1 ]; then
            SD_DEVICE="/dev/mmcblk0"
            export SD_DEVICE
            log "Found unpartitioned SD card: $SD_DEVICE (${SIZE_GB}GB)"
            log_success "SD card device detected: $SD_DEVICE"
            return 0
        fi
    fi
    
    # Check other possible devices
    for device in /dev/mmcblk1 /dev/sda /dev/sdb; do
        if [ -b "$device" ]; then
            SIZE_BYTES=$(blockdev --getsize64 "$device" 2>/dev/null || echo "0")
            SIZE_GB=$((SIZE_BYTES / 1024 / 1024 / 1024))
            
            if [ "$SIZE_GB" -ge 1 ]; then
                SD_DEVICE="$device"
                export SD_DEVICE
                log "Found SD card: $SD_DEVICE (${SIZE_GB}GB)"
                log_success "SD card device detected: $SD_DEVICE"
                return 0
            fi
        fi
    done
    
    error_exit "No suitable SD card device found. Please ensure SD card is inserted BEFORE powering on router" [8]
}

#==============================================================================
# Identify partitions
#==============================================================================
identify_partitions() {
    log "Identifying partitions..."
    
    # Determine partition names
    if [ -b "${SD_DEVICE}p1" ]; then
        SWAP_PART="${SD_DEVICE}p1"
        ROOT_PART="${SD_DEVICE}p2"
    elif [ -b "${SD_DEVICE}1" ]; then
        SWAP_PART="${SD_DEVICE}1"
        ROOT_PART="${SD_DEVICE}2"
    else
        error_exit "No partitions found on $SD_DEVICE"
    fi
    
    export SWAP_PART ROOT_PART
    log "Identified partitions: $SWAP_PART (swap), $ROOT_PART (root)"
    log_success "Partitions identified"
}

#==============================================================================
# STEP 1: Uninstall GL.iNet tools that interfere with extroot
#==============================================================================
uninstall_glinet_storage_tools() {
    log "Removing GL.iNet SAMBA/NFS/WebDAV packages that interfere with extroot..." [23]
    
    # List of potentially interfering packages
    PACKAGES_TO_CHECK="
        gl-sdk4-network-storage
        gl-nas
        gl-samba
        gl-samba4
        samba4-server
        samba36-server
        kmod-fs-cifs
        cifsmount
        luci-app-samba
        luci-app-samba4
        gl-webdav
        gl-dlna
        minidlna
        luci-app-minidlna
        nfs-kernel-server
        nfs-utils
        gl-nfs
        gl-cloud
    "
    
    for pkg in $PACKAGES_TO_CHECK; do
        if opkg list-installed | grep -q "^$pkg "; then
            log "Removing package: $pkg"
            opkg remove "$pkg" --force-removal-of-dependent-packages 2>/dev/null || true
        fi
    done
    
    # Stop any related services
    for service in samba samba4 minidlna nfsd webdav; do
        if [ -f "/etc/init.d/$service" ]; then
            /etc/init.d/$service stop 2>/dev/null || true
            /etc/init.d/$service disable 2>/dev/null || true
        fi
    done
    
    log_success "GL.iNet storage tools processing completed"
}

#==============================================================================
# STEP 2: Install required packages
#==============================================================================
install_required_packages() {
    log "Installing required packages..."
    
    # Update package lists first
    opkg update >/dev/null 2>&1 || log_warn "Package update failed, continuing..."
    
    REQUIRED_PACKAGES="block-mount kmod-fs-ext4 e2fsprogs fdisk swap-utils kmod-mmc"
    
    for pkg in $REQUIRED_PACKAGES; do
        if ! opkg list-installed | grep -q "^$pkg "; then
            log "Installing: $pkg"
            opkg install "$pkg" || log_warn "Failed to install $pkg (may already be included)"
        else
            log "Package already installed: $pkg"
        fi
    done
    
    log_success "Required packages checked"
}

#==============================================================================
# STEP 3: Check partition validity
#==============================================================================
check_partitions() {
    log "Checking partition validity..."
    
    if [ ! -b "$SWAP_PART" ]; then
        error_exit "Swap partition not found: $SWAP_PART"
    fi
    
    if [ ! -b "$ROOT_PART" ]; then
        error_exit "Root partition not found: $ROOT_PART"
    fi
    
    log "Partitions verified: $SWAP_PART and $ROOT_PART exist"
    log_success "Partition check completed"
}

#==============================================================================
# STEP 4: Read block info and UUID
#==============================================================================
read_block_info() {
    log "Reading block device information..."
    
    # Get UUIDs with retries
    COUNTER=0
    while [ $COUNTER -lt 5 ]; do
        SWAP_UUID=$(blkid -s UUID -o value "$SWAP_PART" 2>/dev/null || echo "")
        ROOT_UUID=$(blkid -s UUID -o value "$ROOT_PART" 2>/dev/null || echo "")
        
        if [ -n "$SWAP_UUID" ] && [ -n "$ROOT_UUID" ]; then
            break
        fi
        
        log_warn "Waiting for UUID detection (attempt $((COUNTER + 1)))..."
        sleep 2
        COUNTER=$((COUNTER + 1))
    done
    
    if [ -z "$SWAP_UUID" ] || [ -z "$ROOT_UUID" ]; then
        log_warn "Could not read UUIDs, will generate new filesystems"
        # We'll format them in the next step
        return 0
    fi
    
    export SWAP_UUID ROOT_UUID
    
    log "Swap partition: $SWAP_PART (UUID: $SWAP_UUID)"
    log "Root partition: $ROOT_PART (UUID: $ROOT_UUID)"
    
    log_success "Block info retrieved"
}

#==============================================================================
# STEP 5: Format partitions (if needed)
#==============================================================================
format_partitions_if_needed() {
    log "Checking if partitions need formatting..."
    
    FORMAT_NEEDED=0
    
    # Check if we have valid UUIDs
    if [ -z "$ROOT_UUID" ] || [ -z "$SWAP_UUID" ]; then
        FORMAT_NEEDED=1
    else
        # Test if we can mount the root partition
        mkdir -p /mnt/test
        if ! mount "$ROOT_PART" /mnt/test 2>/dev/null; then
            FORMAT_NEEDED=1
            log "Root partition needs formatting"
        else
            umount /mnt/test
            log "Root partition appears to be valid"
        fi
    fi
    
    if [ $FORMAT_NEEDED -eq 1 ]; then
        log "Formatting partitions..."
        
        # Format swap partition
        log "Formatting swap partition: $SWAP_PART"
        mkswap "$SWAP_PART" || error_exit "Failed to create swap on $SWAP_PART"
        
        # Format ext4 partition for overlay
        log "Formatting ext4 partition: $ROOT_PART"
        mkfs.ext4 -F -L "extroot" "$ROOT_PART" || error_exit "Failed to format $ROOT_PART as ext4"
        
        sync
        sleep 2
        
        # Get new UUIDs
        SWAP_UUID=$(blkid -s UUID -o value "$SWAP_PART")
        ROOT_UUID=$(blkid -s UUID -o value "$ROOT_PART")
        
        export SWAP_UUID ROOT_UUID
        
        log "New Swap UUID: $SWAP_UUID"
        log "New Root UUID: $ROOT_UUID"
        
        log_success "Partitions formatted successfully"
    else
        log "Partitions already properly formatted, skipping"
    fi
}

#==============================================================================
# STEP 6: Backup current overlay
#==============================================================================
backup_overlay() {
    log "Backing up current overlay filesystem..."
    
    mkdir -p "$BACKUP_DIR"
    
    # Copy current overlay contents
    if [ -d "/overlay" ] && [ -n "$(ls -A /overlay)" ]; then
        tar -C /overlay -cf "$BACKUP_DIR/overlay_backup.tar" . 2>/dev/null || \
            log_warn "Overlay backup may be incomplete"
        log "Overlay backup created"
    else
        log_warn "No overlay data found to backup"
    fi
    
    log_success "Overlay backup processed"
}

#==============================================================================
# STEP 7: Configure fstab for extroot
#==============================================================================
configure_fstab() {
    log "Configuring fstab for extroot..."
    
    # Backup original fstab
    cp /etc/config/fstab /etc/config/fstab.backup."$(date +%s)" 2>/dev/null || true
    
    # Clear existing fstab mount and swap entries
    uci -q delete fstab.@mount[0]
    uci -q delete fstab.@swap[0]
    
    # Configure the extroot overlay partition
    uci add fstab mount
    uci set fstab.@mount[0].uuid="$ROOT_UUID"
    uci set fstab.@mount[0].target='/overlay'
    uci set fstab.@mount[0].enabled='1'
    uci set fstab.@mount[0].options='rw,sync'
    uci set fstab.@mount[0].fstype='ext4'
    
    # Configure swap partition
    uci add fstab swap
    uci set fstab.@swap[0].uuid="$SWAP_UUID"
    uci set fstab.@swap[0].enabled='1'
    
    # Ensure global settings exist
    if ! uci get fstab.@global[0] >/dev/null 2>&1; then
        uci add fstab global
    fi
    
    uci set fstab.@global[0].anon_mount='0'
    uci set fstab.@global[0].auto_mount='1'
    uci set fstab.@global[0].auto_swap='1'
    uci set fstab.@global[0].check_fs='1'
    uci set fstab.@global[0].delay_root='15'  # GL.iNet specific timing
    
    uci commit fstab
    
    log "Fstab configuration applied:"
    uci show fstab | tee -a "$LOG_FILE"
    
    log_success "Fstab configured"
}

#==============================================================================
# STEP 8: Copy overlay to new partition
#==============================================================================
copy_overlay() {
    log "Mounting new partition and copying overlay..."
    
    mkdir -p /mnt/extroot
    mount "$ROOT_PART" /mnt/extroot || error_exit "Failed to mount $ROOT_PART"
    
    # Copy overlay contents to new partition
    if [ -d "/overlay" ] && [ -n "$(ls -A /overlay)" ]; then
        log "Copying overlay data to extroot partition..."
        tar -C /overlay -cf - . | tar -C /mnt/extroot -xf - || \
            log_warn "Some files may not have copied correctly"
        log "Overlay data copied to extroot partition"
    else
        log_warn "No overlay data to copy"
    fi
    
    sync
    sleep 2
    umount /mnt/extroot
    
    log_success "Overlay copied to extroot partition"
}

#==============================================================================
# STEP 9: Verify configuration
#==============================================================================
verify_configuration() {
    log "Performing verification checks..."
    
    ERRORS=0
    
    # Check partitions exist
    if [ ! -b "$SWAP_PART" ]; then
        log_error "Swap partition not found: $SWAP_PART"
        ERRORS=$((ERRORS + 1))
    fi
    
    if [ ! -b "$ROOT_PART" ]; then
        log_error "Root partition not found: $ROOT_PART"
        ERRORS=$((ERRORS + 1))
    fi
    
    # Check fstab configuration
    if ! uci show fstab | grep -q "target='/overlay'"; then
        log_error "Overlay mount not configured in fstab"
        ERRORS=$((ERRORS + 1))
    fi
    
    # Test mount
    log "Testing mount of extroot partition..."
    mkdir -p /mnt/test_extroot
    if mount "$ROOT_PART" /mnt/test_extroot; then
        log_success "Extroot partition mounts correctly"
        umount /mnt/test_extroot
    else
        log_error "Failed to test mount extroot partition"
        ERRORS=$((ERRORS + 1))
    fi
    
    if [ $ERRORS -gt 0 ]; then
        error_exit "Verification failed with $ERRORS errors"
    fi
    
    log_success "All verification checks passed"
}

#==============================================================================
# STEP 10: Create post-reboot verification script
#==============================================================================
create_verification_script() {
    log "Creating post-reboot verification script..."
    
    cat > /root/verify_extroot.sh << 'VERIFY_EOF'
#!/bin/sh
# Post-reboot extroot verification script for GL.iNet AXT1800

echo "=========================================="
echo "GL.iNet AXT1800 Extroot Verification"
echo "=========================================="

echo ""
echo "Checking overlay mount..."
OVERLAY_MOUNT=$(mount | grep "on /overlay" | awk '{print $1}')
if [ -n "$OVERLAY_MOUNT" ] && echo "$OVERLAY_MOUNT" | grep -q "mmcblk"; then
    echo "[SUCCESS] Extroot is active!"
    echo "Overlay mounted from: $OVERLAY_MOUNT"
else
    echo "[INFO] Current overlay source: $OVERLAY_MOUNT"
    if [ -z "$OVERLAY_MOUNT" ]; then
        echo "[WARNING] No /overlay mount found"
    fi
fi

echo ""
echo "Storage information:"
df -h / /overlay 2>/dev/null

echo ""
echo "Swap information:"
free | grep -i swap
swapon -s

echo ""
echo "Block device information:"
block info

echo ""
echo "Fstab configuration:"
uci show fstab

echo ""
echo "=========================================="
echo "If everything looks good, extroot is working!"
echo "=========================================="
VERIFY_EOF
    
    chmod +x /root/verify_extroot.sh
    
    log_success "Verification script created at /root/verify_extroot.sh"
}

#==============================================================================
# STEP 11: Final summary and reboot
#==============================================================================
final_summary() {
    echo ""
    echo "=========================================="
    echo "        EXTROOT SETUP COMPLETE"
    echo "=========================================="
    echo ""
    log "Configuration Summary:"
    log "  SD Card Device: $SD_DEVICE"
    log "  Swap Partition: $SWAP_PART (UUID: $SWAP_UUID)"
    log "  Root Partition: $ROOT_PART (UUID: $ROOT_UUID)"
    log "  Delay Root: 15 seconds"
    echo ""
    log_warn "IMPORTANT NOTES FOR GL.iNet AXT1800:" [8]
    log_warn "1. Do NOT remove the SD card while router is powered" [26]
    log_warn "2. If boot fails, remove SD card and router will boot from internal storage"
    log_warn "3. Run /root/verify_extroot.sh after reboot to confirm setup"
    echo ""
    log "Log file saved to: $LOG_FILE"
    echo ""
    
    # Ask for reboot
    echo "The router needs to reboot to activate extroot."
    echo "After reboot, run: /root/verify_extroot.sh"
    echo ""
    read -p "Reboot now? (y/N): " REBOOT_CONFIRM
    
    if [ "$REBOOT_CONFIRM" = "y" ] || [ "$REBOOT_CONFIRM" = "Y" ]; then
        log "Rebooting system..."
        sync
        reboot
    else
        log "Reboot skipped. Please reboot manually when ready."
        echo "Run 'reboot' to restart the router."
    fi
}

#==============================================================================
# MAIN EXECUTION
#==============================================================================
main() {
    echo "=========================================="
    echo "GL.iNet AXT1800 Extroot Setup Script"
    echo "=========================================="
    echo ""
    
    # Initialize log
    echo "" > "$LOG_FILE"
    log "Script started at $(date)"
    
    # Execute all steps in order
    preflight_checks
    detect_sd_device
    identify_partitions
    uninstall_glinet_storage_tools
    install_required_packages
    check_partitions
    read_block_info
    format_partitions_if_needed
    backup_overlay
    configure_fstab
    copy_overlay
    verify_configuration
    create_verification_script
    final_summary
}

# Run main function
main "$@"
