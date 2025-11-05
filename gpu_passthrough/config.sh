#!/bin/bash

set -euo pipefail

# Global variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_FILE="/tmp/passthrough_setup.state"
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

# Progress bar function
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

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script should be run as root. Use sudo."
    fi
}

# Hardware detection functions
detect_cpu_vendor() {
    local vendor=$(lscpu | awk -F: '/Vendor ID/ {gsub(/ /,"",$2); print $2; exit}')
    case $vendor in
        "GenuineIntel")
            echo "intel"
            ;;
        "AuthenticAMD")
            echo "amd"
            ;;
        *)
            error "Unknown CPU vendor: $vendor"
            ;;
    esac
}

check_virtualization() {
    info "Checking virtualization support..."

    if ! lscpu | grep -E -iq "Virtualization|Virtualisation"; then
        error "Virtualization not enabled in BIOS. Please enable VT-x/VT-d (Intel) or AMD-V/AMD-Vi (AMD)"
    fi

    local virt_type=$(lscpu | grep -E -i "Virtualization|Virtualisation" | awk '{print $2}')
    success "Virtualization enabled: $virt_type"
}

check_iommu() {
    info "Checking IOMMU support..."

    if [ -d /sys/kernel/iommu_groups ] || \
       dmesg | grep -Eiq 'iommu|dmar|amd-vi|ivrs'; then
        success "IOMMU is enabled and active"
    else
        info "IOMMU may not be enabled. It will be configured in GRUB."
    fi
}

detect_gpus() {
    info "Detecting GPUs..."

    local gpu_count=0
    declare -g -A GPUS

    while IFS= read -r line; do
        if [[ $line =~ ([0-9a-f]{2}:[0-9a-f]{2}\.[0-9]).*\[([0-9a-f]{4}):([0-9a-f]{4})\] ]]; then
            local pci_addr="${BASH_REMATCH[1]}"
            local vendor_id="${BASH_REMATCH[2]}"
            local device_id="${BASH_REMATCH[3]}"
            local description=$(echo "$line" | cut -d':' -f3- | sed 's/^ *//')

            GPUS["$gpu_count,pci"]="$pci_addr"
            GPUS["$gpu_count,vendor"]="$vendor_id"
            GPUS["$gpu_count,device"]="$device_id"
            GPUS["$gpu_count,desc"]="$description"

            info "GPU $gpu_count: $pci_addr - $description [$vendor_id:$device_id]"
            gpu_count=$((gpu_count + 1))
        fi
    done < <(lspci -nn | grep -i vga)

    if [[ $gpu_count -lt 2 ]]; then
        error "At least 2 GPUs required for passthrough. Found: $gpu_count"
    fi

    success "Found $gpu_count GPUs"
    declare -g GPU_COUNT=$gpu_count
}

detect_audio_controllers() {
    info "Detecting audio controllers..."

    local audio_count=0
    declare -g -A AUDIO_DEVICES

    while IFS= read -r line; do
        if [[ $line =~ ([0-9a-f]{2}:[0-9a-f]{2}\.[0-9]).*\[([0-9a-f]{4}):([0-9a-f]{4})\] ]]; then
            local pci_addr="${BASH_REMATCH[1]}"
            local vendor_id="${BASH_REMATCH[2]}"
            local device_id="${BASH_REMATCH[3]}"
            local description=$(echo "$line" | cut -d':' -f3- | sed 's/^ *//')

            AUDIO_DEVICES["$audio_count,pci"]="$pci_addr"
            AUDIO_DEVICES["$audio_count,vendor"]="$vendor_id"
            AUDIO_DEVICES["$audio_count,device"]="$device_id"
            AUDIO_DEVICES["$audio_count,desc"]="$description"

            info "Audio $audio_count: $pci_addr - $description [$vendor_id:$device_id]"
            audio_count=$((audio_count + 1))
        fi
    done < <(lspci -nn | grep -i audio)

    declare -g AUDIO_COUNT=$audio_count
    success "Found $audio_count audio controllers"
}

# User selection functions
select_passthrough_gpu() {
    info "Select GPU for passthrough to VM:"

    for ((i=0; i<GPU_COUNT; i++)); do
        echo "  $i) ${GPUS[$i,desc]} [${GPUS[$i,vendor]}:${GPUS[$i,device]}]"
    done

    while true; do
        read -p "Enter GPU number for passthrough: " gpu_choice
        if [[ $gpu_choice =~ ^[0-9]+$ ]] && [[ $gpu_choice -lt $GPU_COUNT ]]; then
            declare -g PASSTHROUGH_GPU=$gpu_choice
            success "Selected GPU: ${GPUS[$gpu_choice,desc]}"
            break
        else
            warning "Invalid selection. Please enter a number between 0 and $((GPU_COUNT-1))"
        fi
    done
}

select_passthrough_audio() {
    if [[ $AUDIO_COUNT -eq 0 ]]; then
        warning "No audio controllers found"
        return
    fi

    info "Select audio controller for passthrough (or skip):"

    for ((i=0; i<AUDIO_COUNT; i++)); do
        echo "  $i) ${AUDIO_DEVICES[$i,desc]} [${AUDIO_DEVICES[$i,vendor]}:${AUDIO_DEVICES[$i,device]}]"
    done

    while true; do
        read -p "Enter audio controller number: " audio_choice
        if [[ $audio_choice =~ ^[0-9]+$ ]] && [[ $audio_choice -lt $AUDIO_COUNT ]]; then
            declare -g PASSTHROUGH_AUDIO=$audio_choice
            success "Selected Audio: ${AUDIO_DEVICES[$audio_choice,desc]}"
            break
        else
            warning "Invalid selection. Please enter a number between 0 and $((AUDIO_COUNT-1)) or 's'"
        fi
    done
}


configure_grub() {
    info "Configuring GRUB for IOMMU and VFIO..."

    # Backup current GRUB config
    sudo cp /etc/default/grub "/etc/default/grub.backup"

    local cpu_vendor=$(detect_cpu_vendor) || exit 1
    local iommu_param

    if [[ $cpu_vendor == "intel" ]]; then
        iommu_param="intel_iommu=on"
    else
        iommu_param="amd_iommu=on"
    fi

    # Build device IDs string
    local device_ids="${GPUS[$PASSTHROUGH_GPU,vendor]}:${GPUS[$PASSTHROUGH_GPU,device]}"
    if [[ -n $PASSTHROUGH_AUDIO ]]; then
        device_ids+=",${AUDIO_DEVICES[$PASSTHROUGH_AUDIO,vendor]}:${AUDIO_DEVICES[$PASSTHROUGH_AUDIO,device]}"
    fi

    # Update GRUB configuration
    local grub_cmdline="quiet splash $iommu_param iommu=pt vfio-pci.ids=$device_ids"

    sudo sed -i.bak "s/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT=\"$grub_cmdline\"/" /etc/default/grub

    sudo grub-mkconfig -o /boot/grub/grub.cfg

    success "GRUB configured with: $grub_cmdline"
}

configure_vfio() {
    info "Configuring VFIO..."
    
    # VFIO configuration
    local device_ids="${GPUS[$PASSTHROUGH_GPU,vendor]}:${GPUS[$PASSTHROUGH_GPU,device]}"
    if [[ -n $PASSTHROUGH_AUDIO ]]; then
        device_ids+=",${AUDIO_DEVICES[$PASSTHROUGH_AUDIO,vendor]}:${AUDIO_DEVICES[$PASSTHROUGH_AUDIO,device]}"
    fi
    
    echo "options vfio-pci ids=$device_ids" | sudo tee /etc/modprobe.d/vfio.conf
    
    sudo tee /etc/modules-load.d/vfio.conf > /dev/null <<EOF
vfio
vfio_pci
vfio_iommu_type1
EOF

    sudo update-initramfs -c -k "$(uname -r)"
    success "VFIO configured for devices: $device_ids"
}

# Main setup function
main() {
    check_root
    sudo rm -f "$STATE_FILE"

    check_virtualization
    check_iommu
    detect_gpus
    detect_audio_controllers

    info "Please select hardware for passthrough:"
    select_passthrough_gpu
    select_passthrough_audio

    info "Setup will configure:"
    info "  - GPU: ${GPUS[$PASSTHROUGH_GPU,desc]}"
    info "  - Audio: ${AUDIO_DEVICES[$PASSTHROUGH_AUDIO,desc]}"

    info "Starting installation..."
    configure_grub
    configure_vfio

    echo "PASSTHROUGH_GPU=${GPUS[$PASSTHROUGH_GPU,desc]}" > "$STATE_FILE"
    echo "PASSTHROUGH_AUDIO=${AUDIO_DEVICES[$PASSTHROUGH_AUDIO,desc]}" >> "$STATE_FILE"

    info "Initial setup complete. A system reboot is required to apply GRUB and VFIO changes."
    echo -e "\n${YELLOW}Please reboot your system now. After reboot, re-run this script for next steps.${NC}"
}

# Trap errors
trap 'error "Script failed at line $LINENO"' ERR

# Run main function
main "$@"
