#!/bin/bash

set -euo pipefail

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
    )
    
    for ((i=0; i<${#packages[@]}; i++)); do
        show_progress $((i+1)) ${#packages[@]}
        sudo apt-get install -y "${packages[$i]}" >> "$LOGFILE" 2>&1
    done
    echo # New line after progress bar
    
    success "All packages installed"
}


configure_libvirt() {
    info "Configuring libvirt..."
    
    systemctl enable libvirtd.service
    systemctl start libvirtd.service
    usermod -aG libvirt "$SUDO_USER"
    
    success "Libvirt configured."
}


# Main setup function
main() {
    check_root
    install_dependencies
    configure_libvirt
}

# Trap errors
trap 'error "Script failed at line $LINENO"' ERR

# Run main function
main "$@"
