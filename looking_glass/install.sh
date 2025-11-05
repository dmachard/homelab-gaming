#!/bin/bash

set -euo pipefail

# Global variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOGFILE="/tmp/passthrough_setup.log"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

LOG_FILE="${LOG_FILE:-/tmp/passthrough_setup.log}"

log()     { echo -e "${2:-$NC}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}" | tee -a "$LOG_FILE"; }
error()   { log "ERROR:   $1" "$RED";   exit 1; }
warning() { log "WARNING: $1" "$YELLOW"; }
success() { log "SUCCESS: $1" "$GREEN"; }
info()    { log "INFO:    $1" "$BLUE";  }


install_dependencies() {
    info "Installing required packages..."
    
    local packages=(
        # Virtu
        "vim"
        "qemu-kvm"
        "virt-manager"
        "bridge-utils"
        "virt-viewer"
        "ovmf"

        # Compilation / build
        "linux-headers-$(uname -r)"
        "dkms"
        "build-essential"
        "gcc"
        "g++"
        "cmake"
        "binutils-dev"
        "pkg-config"

        # Polices
        "fonts-dejavu-core"
        "libfontconfig-dev"

        # OpenGL / EGL / GLES
        "libegl-dev"
        "libgl-dev"
        "libgles-dev"

        # Wayland & X11
        "libx11-dev"
        "libxcursor-dev"
        "libxi-dev"
        "libxinerama-dev"
        "libxpresent-dev"
        "libxss-dev"
        "libxkbcommon-dev"
        "libwayland-dev"
        "wayland-protocols"
        "libxcb-shm0-dev"
	    "libxcb-xfixes0-dev"

        # audio
        "libpipewire-0.3-dev"
        "libpulse-dev"
        "libsamplerate0-dev"

        # misc
        "libspice-protocol-dev"
        "nettle-dev"
    )
    
    for ((i=0; i<${#packages[@]}; i++)); do
        show_progress $((i+1)) ${#packages[@]}
        sudo apt-get install -y "${packages[$i]}" >> "$LOGFILE" 2>&1
    done
    echo # New line after progress bar
    
    success "All packages installed"
}

install_looking_glass() {
    info "Installing Looking Glass..."

    local lg_version="B7"
    local lg_url="https://looking-glass.io/artifact/$lg_version/source"
    local lg_dir="/tmp/looking-glass-$lg_version"

    # Download and extract
    cd /tmp
    if [[ ! -f "looking-glass-$lg_version.tar.gz" ]]; then
        wget -O "looking-glass-$lg_version.tar.gz" "$lg_url"
    fi

    if [[ -d "$lg_dir" ]]; then
        rm -rf "$lg_dir"
    fi

    tar -xzf "looking-glass-$lg_version.tar.gz"
    cd "$lg_dir"

    # Install kernel module
    info "Installing Looking Glass kernel module..."
    cd module

    # Extract version from dkms.conf
    kvmfr_ver=$(grep '^PACKAGE_VERSION' dkms.conf | cut -d'"' -f2)

    # Remove existing version (ignore errors)
    dkms remove -m kvmfr -v "$kvmfr_ver" --all 2>/dev/null || true

    dkms install .
    cd ..

    # Configure kvmfr
    echo "options kvmfr static_size_mb=128" | tee /etc/modprobe.d/kvmfr.conf
    echo "kvmfr" | tee /etc/modules-load.d/kvmfr.conf

    # Create udev rule
    echo "SUBSYSTEM==\"kvmfr\", OWNER=\"$SUDO_USER\", GROUP=\"kvm\", MODE=\"0660\"" | tee /etc/udev/rules.d/99-kvmfr.rules

    # Build client
    info "Building Looking Glass client..."
    mkdir -p client/build
    cd client/build

    info "Running CMake..."
    cmake .. >> "$LOGFILE" 2>&1 || error "CMake configuration failed. See $LOGFILE"

    info "Compiling..."
    make -j"$(nproc)" >> "$LOGFILE" 2>&1 || error "Build failed. See $LOGFILE"

    info "Installing..."
    sudo make install >> "$LOGFILE" 2>&1 || error "Installation failed. See $LOGFILE"

    success "Looking Glass installed"
}


verify_setup() {
    info "1. Check Looking Glass device node:"
    if [ -e /dev/kvmfr0 ]; then
        ls -l /dev/kvmfr0
        info "Looking Glass device /dev/kvmfr0 exists."
    else
        error "Looking Glass device /dev/kvmfr0 not found. Is the kvmfr module loaded?"
    fi

    info "2. Verify Looking Glass client installation:"
    if command -v looking-glass-client >/dev/null 2>&1; then
        info "Looking Glass client is installed."
    else
        error "Looking Glass client is not installed or not in PATH."
    fi
}

# Main setup function
main() {
    check_root
    install_dependencies
    install_looking_glass
    verify_setup
}

# Trap errors
trap 'error "Script failed at line $LINENO"' ERR

# Run main function
main "$@"