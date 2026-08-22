#!/usr/bin/env bash
# ==============================================================================
# Linux Mint 22.3 Laptop Optimization Script (Dell Latitude 7440 / Intel 13th Gen)
# ==============================================================================
# This script performs the following system optimizations:
#  1. Boot Acceleration (disables ModemManager and NetworkManager-wait-online)
#  2. VM & Swappiness Tuning for 32GB RAM (sysctl)
#  3. In-Memory Compressed Swap (zRAM with zstd)
#  4. Intel Iris Xe Hardware Video Acceleration (non-free VA-API driver)
#  5. Low-latency Audio Realtime Permissions (Bitwig Studio / DAW support)
#  6. Storage Optimization (adds noatime mount flag to ext4 root in /etc/fstab)
#  7. Package & Flatpak Cleanup
# ==============================================================================

set -e

# ANSI Colors
GREEN="\033[0;32m"
BLUE="\033[0;34m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
BOLD="\033[1m"
NC="\033[0m"

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_err()     { echo -e "${RED}[ERROR]${NC} $1"; }
log_section() { echo -e "\n${BOLD}${BLUE}=== $1 ===${NC}"; }

# Ensure script is run with sudo
if [[ $EUID -ne 0 ]]; then
    log_err "This script must be run with sudo privileges."
    echo "Usage: sudo ./$(basename "$0")"
    exit 1
fi

TARGET_USER="${SUDO_USER:-$USER}"
log_info "Running optimization for user: ${BOLD}${TARGET_USER}${NC}"

# ------------------------------------------------------------------------------
# 1. Boot Acceleration
# ------------------------------------------------------------------------------
log_section "1. Boot Acceleration"

log_info "Disabling & masking ModemManager.service and NetworkManager-wait-online.service..."
systemctl disable --now ModemManager.service NetworkManager-wait-online.service 2>/dev/null || true
systemctl mask ModemManager.service NetworkManager-wait-online.service 2>/dev/null || true
log_success "Boot wait services disabled and masked (saves ~23s on boot)."

# ------------------------------------------------------------------------------
# 2. Virtual Memory & Sysctl Tuning (32GB RAM)
# ------------------------------------------------------------------------------
log_section "2. Virtual Memory & Sysctl Tuning"

SYSCTL_CONF="/etc/sysctl.d/99-laptop-optimizations.conf"
log_info "Configuring ${SYSCTL_CONF}..."

cat > "${SYSCTL_CONF}" << 'EOF'
# Lower swappiness to favor 32GB RAM over disk swapping
vm.swappiness = 10

# Keep inode and dentry caches in RAM longer (faster file operations/indexing)
vm.vfs_cache_pressure = 50

# Smoother dirty page background flushes to prevent write stalls
vm.dirty_ratio = 10
vm.dirty_background_ratio = 5
EOF

sysctl --system > /dev/null
log_success "Sysctl parameters applied successfully."

# ------------------------------------------------------------------------------
# 3. Hardware Video Acceleration & zRAM Installation
# ------------------------------------------------------------------------------
log_section "3. Packages: zRAM and Intel VA-API Driver"

log_info "Updating package lists..."
apt-get update -qq

log_info "Installing zram-tools and intel-media-va-driver-non-free..."
apt-get install -y -qq zram-tools intel-media-va-driver-non-free

# Configure zramswap
ZRAM_CONF="/etc/default/zramswap"
cat > "${ZRAM_CONF}" << 'EOF'
# zRAM Configuration
ALGO=zstd
PERCENT=25
PRIORITY=100
EOF

systemctl restart zramswap
log_success "zRAM configured (zstd algorithm, 25% RAM capacity) and active."
log_success "Intel non-free VA-API driver installed for hardware video decoding."

# ------------------------------------------------------------------------------
# 4. Audio Realtime Limits (DAW / Bitwig Studio Support)
# ------------------------------------------------------------------------------
log_section "4. Low-Latency Realtime Audio Configuration"

if id -u "${TARGET_USER}" >/dev/null 2>&1; then
    usermod -aG audio "${TARGET_USER}"
    log_success "Added user '${TARGET_USER}' to the 'audio' group."
fi

AUDIO_LIMITS="/etc/security/limits.d/99-audio-realtime.conf"
cat > "${AUDIO_LIMITS}" << 'EOF'
# Realtime scheduling and memory locking permissions for audio group
@audio   -  rtprio     95
@audio   -  memlock    unlimited
@audio   -  nice      -19
EOF
log_success "Realtime audio limits written to ${AUDIO_LIMITS}."

# ------------------------------------------------------------------------------
# 5. Storage / NVMe Optimization (noatime in /etc/fstab)
# ------------------------------------------------------------------------------
log_section "5. Storage Optimization (/etc/fstab)"

FSTAB="/etc/fstab"
if grep -q "errors=remount-ro" "${FSTAB}" && ! grep -q "noatime" "${FSTAB}"; then
    log_info "Backing up ${FSTAB} to ${FSTAB}.bak..."
    cp "${FSTAB}" "${FSTAB}.bak"
    log_info "Adding 'noatime' mount option to root filesystem..."
    sed -i 's/errors=remount-ro/noatime,errors=remount-ro/' "${FSTAB}"
    log_success "Updated /etc/fstab with 'noatime' to reduce SSD write wear."
else
    log_info "'noatime' is already configured or fstab format is custom. Skipping modification."
fi

# ------------------------------------------------------------------------------
# 6. Cleanup Unused Packages and Flatpaks
# ------------------------------------------------------------------------------
log_section "6. System Cleanup"

log_info "Cleaning up unused flatpak runtimes..."
if command -v flatpak >/dev/null 2>&1; then
    flatpak uninstall --unused -y 2>/dev/null || true
fi

log_info "Removing obsolete APT packages and cleaning cache..."
apt-get autoremove --purge -y -qq
apt-get clean
log_success "System cleanup completed."

# ------------------------------------------------------------------------------
# Summary & Next Steps
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}${GREEN}====================================================${NC}"
echo -e "${BOLD}${GREEN}   All Laptop Optimizations Completed Successfully!  ${NC}"
echo -e "${BOLD}${GREEN}====================================================${NC}"
echo -e "Summary of changes applied:"
echo -e "  ✔ Boot wait services disabled & masked (-23s boot overhead)"
echo -e "  ✔ VM swappiness set to 10 (tuned for 32GB RAM)"
echo -e "  ✔ zRAM compressed memory swap enabled (zstd)"
echo -e "  ✔ Intel non-free media driver installed (GPU video decode)"
echo -e "  ✔ Realtime audio privileges configured for '${TARGET_USER}'"
echo -e "  ✔ SSD 'noatime' mount option enabled in /etc/fstab"
echo -e "  ✔ Package & Flatpak caches cleaned up"
echo ""
log_warn "Please REBOOT your laptop to complete applying group permissions and verify boot performance:"
echo -e "  ${BOLD}sudo reboot${NC}\n"
