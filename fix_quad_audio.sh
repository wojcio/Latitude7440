#!/usr/bin/env bash
# ==============================================================================
# Dell Latitude 7440 Quad-Speaker & Subwoofer / Woofer Audio Fix
# ==============================================================================
# Hardware: Realtek ALC289 (Vendor: 0x10ec0289, Subsystem: 0x10280c0c)
# Issue: Dell BIOS sets Node 0x14 (Woofers/Subwoofers) to disconnected (0x411111f0),
#        causing Linux ALSA to only drive Node 0x17 (Tweeters), leading to thin/tinny sound.
# Fix:
#  1. Overrides Pin 0x14 to 0x90170112 via an ALSA firmware patch (/lib/firmware/).
#  2. Configures snd-hda-intel to load the patch on startup (/etc/modprobe.d/).
#  3. Configures PipeWire to automatically upmix stereo (2.0) across all 4 speakers
#     with low-frequency enhancement (LFE / bass).
#  4. Installs alsa-tools-gui (hdajackretask) for optional manual GUI fine-tuning.
# ==============================================================================

set -e

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

if [[ $EUID -ne 0 ]]; then
    log_err "This script must be run with sudo privileges."
    echo "Usage: sudo ./$(basename "$0")"
    exit 1
fi

TARGET_USER="${SUDO_USER:-$USER}"
USER_HOME=$(eval echo "~${TARGET_USER}")

# ------------------------------------------------------------------------------
# 1. Create ALSA HDA Firmware Pin Override Patch
# ------------------------------------------------------------------------------
log_section "1. Creating ALSA Firmware Pin Override"

FW_FILE="/lib/firmware/hda-dell-quad-speakers.fw"
log_info "Writing HDA pin retask firmware patch to ${FW_FILE}..."

cat > "${FW_FILE}" << 'EOF'
[codec]
0x10ec0289 0x10280c0c 0

[pincfg]
0x14 0x90170112
0x17 0x90170110
EOF

log_success "Firmware patch created (enabled Pin 0x14 internal speaker alongside Pin 0x17)."

# ------------------------------------------------------------------------------
# 2. Configure Kernel Module to Load the Firmware Patch
# ------------------------------------------------------------------------------
log_section "2. Configuring Kernel Module (snd-hda-intel)"

MODPROBE_CONF="/etc/modprobe.d/dell-quad-speakers.conf"
log_info "Writing modprobe rule to ${MODPROBE_CONF}..."

cat > "${MODPROBE_CONF}" << 'EOF'
# Load ALSA firmware patch for Dell Latitude 7440 ALC289 quad speakers
options snd-hda-intel patch=hda-dell-quad-speakers.fw
EOF

log_success "Kernel module configured to load patch on startup."

# ------------------------------------------------------------------------------
# 3. Configure PipeWire Stereo Upmixing & Bass Redirection
# ------------------------------------------------------------------------------
log_section "3. Configuring PipeWire Quad-Speaker Upmixing & LFE"

PIPEWIRE_SYSTEM_DIR="/etc/pipewire/pipewire.conf.d"
mkdir -p "${PIPEWIRE_SYSTEM_DIR}"

cat > "${PIPEWIRE_SYSTEM_DIR}/50-quad-upmix.conf" << 'EOF'
stream.properties = {
    channelmix.upmix = true
    channelmix.upmix-method = psd
    channelmix.lfe-cutoff = 150
}
EOF

# Also create user pipewire directory if needed
PIPEWIRE_USER_DIR="${USER_HOME}/.config/pipewire/pipewire.conf.d"
mkdir -p "${PIPEWIRE_USER_DIR}"
cp "${PIPEWIRE_SYSTEM_DIR}/50-quad-upmix.conf" "${PIPEWIRE_USER_DIR}/50-quad-upmix.conf"
chown -R "${TARGET_USER}:${TARGET_USER}" "${USER_HOME}/.config/pipewire"

log_success "PipeWire configured for stereo-to-quad upmixing and 150Hz LFE bass crossover."

# ------------------------------------------------------------------------------
# 4. Install alsa-tools-gui (hdajackretask)
# ------------------------------------------------------------------------------
log_section "4. Installing Helper Utilities"

log_info "Installing alsa-tools-gui (hdajackretask)..."
apt-get install -y -qq alsa-tools-gui

log_success "alsa-tools-gui installed."

# ------------------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}${GREEN}====================================================${NC}"
echo -e "${BOLD}${GREEN}     Dell Latitude 7440 Audio Fix Installed!        ${NC}"
echo -e "${BOLD}${GREEN}====================================================${NC}"
echo -e "Changes configured:"
echo -e "  ✔ ALSA firmware patch installed at ${FW_FILE}"
echo -e "  ✔ Kernel module configured at ${MODPROBE_CONF}"
echo -e "  ✔ PipeWire 4-channel upmixing and bass crossover active"
echo -e "  ✔ alsa-tools-gui installed for HDA jack retasking"
echo ""
log_warn "Please REBOOT your laptop to load the new ALSA pin configuration:"
echo -e "  ${BOLD}sudo reboot${NC}\n"
