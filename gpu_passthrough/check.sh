#!/bin/bash

set -euo pipefail

STATE_FILE="/tmp/passthrough_setup.state"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()     { echo -e "${2:-$NC}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"; }
info()    { log "INFO:    $1" "$BLUE";  }
success() { log "SUCCESS: $1" "$GREEN"; }
warning() { log "WARNING: $1" "$YELLOW"; }
error()   { log "ERROR:   $1" "$RED"; exit 1; }

if [[ ! -f "$STATE_FILE" ]]; then
    error "State file not found: $STATE_FILE. Run the setup script first."
fi

source "$STATE_FILE"

info "1. Checking GPU passthrough..."
if [[ -n "${PASSTHROUGH_GPU_PCI:-}" ]]; then
    gpu_status=$(lspci -k -s "$PASSTHROUGH_GPU_PCI" | grep "Kernel driver in use")
    if [[ $gpu_status == *"vfio-pci"* ]]; then
        success "GPU $PASSTHROUGH_GPU_PCI is correctly bound to vfio-pci"
    else
        warning "GPU $PASSTHROUGH_GPU_PCI is NOT bound to vfio-pci: $gpu_status"
    fi
else
    warning "PASSTHROUGH_GPU_PCI not set in state file"
fi

info "2. Checking audio passthrough..."
if [[ -n "${PASSTHROUGH_AUDIO_PCI:-}" ]]; then
    audio_status=$(lspci -k -s "$PASSTHROUGH_AUDIO_PCI" | grep "Kernel driver in use")
    if [[ $audio_status == *"vfio-pci"* ]]; then
        success "Audio $PASSTHROUGH_AUDIO_PCI is correctly bound to vfio-pci"
    else
        warning "Audio $PASSTHROUGH_AUDIO_PCI is NOT bound to vfio-pci: $audio_status"
    fi
else
    warning "PASSTHROUGH_AUDIO_PCI not set in state file or skipped"
fi

info "3. Checking VFIO kernel modules..."
missing_modules=()
for mod in vfio vfio_pci vfio_iommu_type1; do
    if ! lsmod | grep -q "^$mod"; then
        missing_modules+=("$mod")
    fi
done

if [[ ${#missing_modules[@]} -eq 0 ]]; then
    success "All VFIO modules are loaded"
else
    warning "Missing VFIO modules: ${missing_modules[*]}"
fi

info "VFIO check complete."
