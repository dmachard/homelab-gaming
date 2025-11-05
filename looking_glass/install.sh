#!/bin/bash

set -euo pipefail

# Global variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOGFILE="/var/log/looking_glass_setup.log"

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

check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root"
    fi
}

show_progress() {
    local current=$1
    local total=$2
    local width=50
    local percentage=$((current * 100 / total))
    local completed=$((current * width / total))
    
    printf "\r["
    printf "%*s" $completed | tr ' ' '='
    printf "%*s" $((width - completed)) | tr ' ' '-'
    printf "] %d%% (%d/%d)" $percentage $current $total
}


install_dependencies() {
    info "Installing required packages..."
    
    local packages=(
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
    dkms remove -m kvmfr -v "$kvmfr_ver" --all 2>/dev/null || true
    dkms install .
    cd ..

    # Configure kvmfr
    echo "options kvmfr static_size_mb=128" | tee /etc/modprobe.d/kvmfr.conf
    echo "kvmfr" | tee /etc/modules-load.d/kvmfr.conf

    # Create udev rule
    echo "SUBSYSTEM==\"kvmfr\", OWNER=\"$SUDO_USER\", GROUP=\"kvm\", MODE=\"0660\"" | tee /etc/udev/rules.d/99-kvmfr.rules
    sudo udevadm control --reload-rules
    sudo udevadm trigger

    # AppArmor
    mkdir -p /etc/apparmor.d/local/abstractions
    echo -e "# Looking Glass\n/dev/kvmfr0 rw," | tee /etc/apparmor.d/local/abstractions/libvirt-qemu
    systemctl reload apparmor

    # TODO cgroups
    #LIBVIRT_CONF="/etc/libvirt/qemu.conf"
    #if grep -q "cgroup_device_acl" "$LIBVIRT_CONF"; then
    #    sed -i '/cgroup_device_acl = \[/,/\]/ s|\]|    "/dev/kvmfr0"\n]|' "$LIBVIRT_CONF"
    #fi
    #systemctl restart libvirtd

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

    # ---------------------------
    # Create desktop entry
    # ---------------------------
	ICON_DIR="/home/$SUDO_USER/.local/share/icons"
	mkdir -p "$ICON_DIR"
	wget -O "$ICON_DIR/looking-glass.png" https://upload.wikimedia.org/wikipedia/commons/5/5e/Windows_10x_Icon.png

DESKTOP_DIR="/home/$SUDO_USER/.local/share/applications"
mkdir -p "$DESKTOP_DIR"
cat > "$DESKTOP_DIR/looking-glass-client.desktop" <<EOF
[Desktop Entry]
Name=Windows Gaming
Exec=looking-glass-client -F
Icon=$ICON_DIR/looking-glass.png
Type=Application
Categories=Utility;System;
Terminal=false
EOF

    success "Looking Glass installed and configured"

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
