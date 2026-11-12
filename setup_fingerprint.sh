#!/usr/bin/env bash
# ==============================================================================
# Dell Latitude 7440 Broadcom ControlVault 3 Fingerprint Reader Setup
# ==============================================================================
# Hardware: Broadcom Corp. 58200 / BCM58200 ControlVault 3 (USB ID: 0a5c:5843)
# OS: Linux Mint 22.x (Cinnamon / Ubuntu 24.04 Noble LTS Base)
#
# Background:
#  Upstream open-source libfprint does not support Broadcom ControlVault 3
#  because of Broadcom's proprietary security protocol.
#  Canonical develops the Touch OEM Driver (TOD) module 'libfprint-2-tod1-broadcom'
#  specifically for Dell laptops.
#  This script installs the Noble (24.04) driver package, configures PAM,
#  and prepares the system for fingerprint authentication.
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
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_FILE="${SCRIPT_DIR}/packages/libfprint-2-tod1-broadcom_5.15.377-5.15.021.0-0ubuntu1~24.04.1~oem1_amd64.deb"

log_info "Configuring fingerprint reader for user: ${BOLD}${TARGET_USER}${NC}"

# ------------------------------------------------------------------------------
# 1. Hardware Detection Check
# ------------------------------------------------------------------------------
log_section "1. Hardware Detection Check"

if lsusb | grep -q "0a5c:5843"; then
    log_success "Detected Broadcom 58200 ControlVault 3 reader (0a5c:5843)."
else
    log_warn "USB ID 0a5c:5843 not detected directly in lsusb."
    log_warn "If your fingerprint reader is not responding, ensure it is enabled in BIOS:"
    log_warn "  BIOS Setup -> Security / System Configuration -> Fingerprint Reader [Enabled]"
fi

# ------------------------------------------------------------------------------
# 2. Install Required Base Packages
# ------------------------------------------------------------------------------
log_section "2. Installing Base Biometric Packages"

log_info "Ensuring fprintd, libfprint-2-tod1, and dependencies are installed..."
apt-get update -qq
apt-get install -y --no-install-recommends \
    fprintd \
    libpam-fprintd \
    libfprint-2-tod1 \
    libssl3t64 \
    libusb-1.0-0 \
    python3 \
    python3-gi

log_success "Base biometric packages are up to date."

# ------------------------------------------------------------------------------
# 3. Install Broadcom TOD Driver Package (Noble 24.04 build)
# ------------------------------------------------------------------------------
log_section "3. Installing Broadcom TOD Driver"

if [[ ! -f "${PACKAGE_FILE}" ]]; then
    log_err "Driver package not found at: ${PACKAGE_FILE}"
    exit 1
fi

log_info "Installing ${PACKAGE_FILE}..."
dpkg -i "${PACKAGE_FILE}" || apt-get install -f -y

# Pin package to prevent unwanted repository overwrites
apt-mark hold libfprint-2-tod1-broadcom >/dev/null 2>&1 || true
log_success "Broadcom TOD driver installed and version pinned."

# ------------------------------------------------------------------------------
# 4. Reload Udev Rules and Restart fprintd
# ------------------------------------------------------------------------------
log_section "4. Reloading Hardware Services"

log_info "Reloading udev subsystem rules..."
udevadm control --reload-rules
udevadm trigger

log_info "Restarting fprintd daemon..."
systemctl restart fprintd.service
sleep 1
log_success "fprintd service is active and listening."

# ------------------------------------------------------------------------------
# 5. Configure PAM Authentication
# ------------------------------------------------------------------------------
log_section "5. Enabling PAM Fingerprint Authentication"

log_info "Enabling fingerprint authentication in PAM..."
pam-auth-update --enable fprintd

log_success "PAM configuration updated successfully."

# ------------------------------------------------------------------------------
# 6. Verification and Enrollment Instructions
# ------------------------------------------------------------------------------
log_section "6. Setup Complete!"

echo -e "\n${GREEN}${BOLD}Fingerprint reader setup is finished!${NC}\n"
echo -e "Next steps to register your fingerprint:"
echo -e "  1. Run this command in your terminal as ${BOLD}${TARGET_USER}${NC} (do NOT use sudo):"
echo -e "     ${BOLD}fprintd-enroll${NC}"
echo -e "     (or for a specific finger: ${BOLD}fprintd-enroll -f right-index-finger${NC})"
echo -e "  2. When prompted, swipe or rest your finger on the power button / sensor multiple times until it completes."
echo -e "  3. Verify your fingerprint with:"
echo -e "     ${BOLD}fprintd-verify${NC}"
echo -e "  4. Test ${BOLD}sudo${NC} or lock your screen (Super + L) to test unlocking!\n"
