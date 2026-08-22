#!/usr/bin/env bash
# ==============================================================================
# Development Environment Setup: Python & Rootless Podman (Linux Mint 22.3)
# ==============================================================================
# Installs and configures:
#  1. Python Development Stack (python3-dev, python3-venv, pipx, uv, ruff, ipython)
#  2. Podman Container Suite (podman, podman-compose, podman-docker, buildah, skopeo, crun)
#  3. Rootless Podman Socket & Docker Compatibility (for Testcontainers, IDEs, Compose)
#  4. Developer Productivity Tools (direnv, git-delta, lazygit, distrobox)
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
# 1. System & Python Build Dependencies
# ------------------------------------------------------------------------------
log_section "1. Installing Python Build Dependencies & Core Tools"

log_info "Updating APT repositories..."
apt-get update -qq

log_info "Installing Python headers, venv, compilers, and library headers..."
apt-get install -y -qq \
    build-essential \
    python3-dev \
    python3-venv \
    python3-pip \
    pipx \
    libffi-dev \
    libssl-dev \
    zlib1g-dev \
    pkg-config \
    direnv \
    distrobox

# ------------------------------------------------------------------------------
# 2. Podman & Container Tools
# ------------------------------------------------------------------------------
log_section "2. Installing Podman & Container Ecosystem"

log_info "Installing Podman, Podman-Compose, Podman-Docker, Buildah, Skopeo, crun..."
apt-get install -y -qq \
    podman \
    podman-compose \
    podman-docker \
    buildah \
    skopeo \
    crun \
    slirp4netns \
    uidmap

log_success "Podman stack installed."

# ------------------------------------------------------------------------------
# 3. User-Level Tools (uv, pipx path, ruff, ipython)
# ------------------------------------------------------------------------------
log_section "3. Configuring Python Tooling for user '${TARGET_USER}'"

# Ensure pipx path
sudo -u "${TARGET_USER}" pipx ensurepath 2>/dev/null || true

# Install uv (Astral's blazing fast Python package manager)
log_info "Installing 'uv' (ultrafast package installer & Python manager)..."
if ! sudo -u "${TARGET_USER}" command -v uv >/dev/null 2>&1; then
    sudo -u "${TARGET_USER}" bash -c "curl -LsSf https://astral.sh/uv/install.sh | sh"
    log_success "Installed 'uv' to ${USER_HOME}/.local/bin/uv"
else
    log_info "'uv' is already installed."
fi

# Install modern Python developer CLI tools via pipx
log_info "Installing Ruff (fast linter/formatter), IPython, and Pre-commit via pipx..."
sudo -u "${TARGET_USER}" bash -c "
    export PATH=\"${USER_HOME}/.local/bin:\$PATH\"
    pipx install ruff --quiet 2>/dev/null || pipx upgrade ruff --quiet 2>/dev/null || true
    pipx install ipython --quiet 2>/dev/null || pipx upgrade ipython --quiet 2>/dev/null || true
    pipx install pre-commit --quiet 2>/dev/null || pipx upgrade pre-commit --quiet 2>/dev/null || true
"
log_success "Python CLI utilities installed in isolated environments."

# ------------------------------------------------------------------------------
# 4. Rootless Podman Socket & Docker Compatibility
# ------------------------------------------------------------------------------
log_section "4. Configuring Rootless Podman Socket & Environment"

# Enable user lingering so user services/containers run smoothly
loginctl enable-linger "${TARGET_USER}" 2>/dev/null || true

# Enable user podman socket
sudo -u "${TARGET_USER}" XDG_RUNTIME_DIR="/run/user/$(id -u "${TARGET_USER}")" systemctl --user enable --now podman.socket 2>/dev/null || true

# Add Podman Docker Host environment variable to .bashrc if not present
BASHRC="${USER_HOME}/.bashrc"
if ! grep -q "DOCKER_HOST" "${BASHRC}"; then
    cat >> "${BASHRC}" << 'EOF'

# Podman Docker Socket & Local Bin Path
export DOCKER_HOST="unix://$XDG_RUNTIME_DIR/podman/podman.sock"
export PATH="$HOME/.local/bin:$PATH"
eval "$(direnv hook bash 2>/dev/null || true)"
EOF
    chown "${TARGET_USER}:${TARGET_USER}" "${BASHRC}"
    log_success "Configured DOCKER_HOST and PATH in ${BASHRC}."
fi

# ------------------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}${GREEN}====================================================${NC}"
echo -e "${BOLD}${GREEN}  Python & Podman Dev Environment Ready!           ${NC}"
echo -e "${BOLD}${GREEN}====================================================${NC}"
echo -e "What was installed and configured:"
echo -e "  ✔ ${BOLD}Podman Stack:${NC} podman, podman-compose, podman-docker, buildah, skopeo"
echo -e "  ✔ ${BOLD}Rootless Docker Socket:${NC} active at unix://\$XDG_RUNTIME_DIR/podman/podman.sock"
echo -e "  ✔ ${BOLD}uv:${NC} 10-100x faster package manager & Python version manager (astral.sh/uv)"
echo -e "  ✔ ${BOLD}Python CLI Tools:${NC} ruff (linter/formatter), ipython, pre-commit, pipx"
echo -e "  ✔ ${BOLD}Containers & Distros:${NC} distrobox installed (run any Linux distro container)"
echo -e "  ✔ ${BOLD}Project Environment:${NC} direnv installed"
echo ""
log_info "To load the updated PATH and DOCKER_HOST in your current shell, run:"
echo -e "  ${BOLD}source ~/.bashrc${NC}\n"
