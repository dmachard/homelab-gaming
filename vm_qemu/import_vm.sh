#!/bin/bash

set -euo pipefail

LOGFILE="/var/log/import_vm.log"
VM_XML="${1:-vm_qemu_win10.xml}"

# --- colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# --- logging helpers ---
log()     { echo -e "${2:-$NC}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}" | tee -a "$LOGFILE"; }
info()    { log "INFO:    $1" "$BLUE"; }
success() { log "SUCCESS: $1" "$GREEN"; }
warning() { log "WARNING: $1" "$YELLOW"; }
error()   { log "ERROR:   $1" "$RED"; exit 1; }

# --- progress bar ---
show_progress() {
    local current=$1
    local total=$2
    local width=40
    local percent=$((current * 100 / total))
    local completed=$((current * width / total))
    
    printf "\r["
    printf "%0.s#" $(seq 1 $completed)
    printf "%0.s-" $(seq 1 $((width - completed)))
    printf "] %d%% (%d/%d)" "$percent" "$current" "$total"
}

# --- check for root privileges ---
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root. Try: sudo $0"
    fi
}

# --- install required virtualization dependencies ---
install_dependencies() {
    info "Installing required packages..."
    
    local packages=(
        vim
        qemu-kvm
        virt-manager
        bridge-utils
        virt-viewer
        ovmf
    )
    
    apt-get update -y >> "$LOGFILE" 2>&1
    
    for ((i=0; i<${#packages[@]}; i++)); do
        show_progress $((i+1)) ${#packages[@]}
        apt-get install -y "${packages[$i]}" >> "$LOGFILE" 2>&1
    done
    echo # new line after progress bar
    
    success "All required packages installed successfully."
}

# --- configure libvirt service and user access ---
configure_libvirt() {
    info "Configuring libvirt service..."

    systemctl enable libvirtd.service
    systemctl start libvirtd.service

    # Add the invoking user (SUDO_USER) to the libvirt group
    usermod -aG libvirt "$SUDO_USER" || warning "Failed to add user to libvirt group."

    success "Libvirt service configured and enabled."
}

check_libvirt() {
    if ! systemctl is-active --quiet libvirtd; then
        info "libvirtd service not running. Starting it..."
        systemctl start libvirtd
    fi
}

import_vm() {
    info "Importing VM from XML: $VM_XML"

    if [[ ! -f "$VM_XML" ]]; then
        error "File not found: $VM_XML"
    fi

    local vm_name
    vm_name=$(xmllint --xpath "string(//domain/name)" "$VM_XML" 2>/dev/null || true)

    if [[ -z "$vm_name" ]]; then
        error "Could not extract <name> from XML file."
    fi

    # If VM already exists, redefine it
    if virsh list --all | grep -qw "$vm_name"; then
        info "VM '$vm_name' already exists. Redefining..."
        virsh undefine "$vm_name" --nvram || true
    fi

    virsh define "$VM_XML"
    success "VM '$vm_name' imported successfully."
}

# --- main setup function ---
main() {
    check_root
    install_dependencies
    configure_libvirt
    check_libvirt
    import_vm
    success "Virtualization and VM setup completed. Please reboot your system."
}

# --- error trap ---
trap 'error "Script failed at line $LINENO"' ERR

# --- run main function ---
main "$@"

