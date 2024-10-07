#!/bin/bash

# Ubuntu 24.04 LTS Server Setup - Optimized
# This script performs a comprehensive setup of Ubuntu 24.04 LTS for server use,
# including system updates, NVIDIA drivers, Docker, and server optimizations.

set -euo pipefail

# Color codes for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Logging functions
log_message() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}" | tee -a "/var/log/ubuntu_server_setup.log"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}" >&2 | tee -a "/var/log/ubuntu_server_setup.log"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}" | tee -a "/var/log/ubuntu_server_setup.log"
}

# Check if script is run as root
if [[ $EUID -ne 0 ]]; then
   error "This script must be run as root" 
   exit 1
fi

# Function to handle errors
handle_error() {
    error "An error occurred on line $1. Exiting..."
    exit 1
}

# Set up error handling
trap 'handle_error $LINENO' ERR

# Update and upgrade system
update_system() {
    log_message "Updating and upgrading system..."
    apt update && apt upgrade -y && apt autoremove -y
}

# Install essential utilities
install_essentials() {
    log_message "Installing essential utilities..."
    apt install -y \
        curl wget git build-essential software-properties-common \
        apt-transport-https ca-certificates gnupg lsb-release \
        make sysstat p7zip bzip2 unzip tar gdebi \
        htop neofetch bpytop nala
}

# Install NVIDIA drivers and CUDA
install_nvidia_cuda() {
    if lspci | grep -i nvidia > /dev/null; then
        log_message "NVIDIA GPU detected. Installing NVIDIA drivers and CUDA..."
        apt install -y linux-headers-$(uname -r)
        
        # Add NVIDIA repository
        add-apt-repository ppa:graphics-drivers/ppa -y
        apt update

        # Install the recommended NVIDIA driver
        ubuntu-drivers devices
        RECOMMENDED_DRIVER=$(ubuntu-drivers devices | grep "recommended" | awk '{print $3}')
        if [ -n "$RECOMMENDED_DRIVER" ]; then
            apt install -y $RECOMMENDED_DRIVER
        else
            warning "No recommended NVIDIA driver found. Please install manually."
        fi

        # Install CUDA
        wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-ubuntu2204.pin
        mv cuda-ubuntu2204.pin /etc/apt/preferences.d/cuda-repository-pin-600
        wget https://developer.download.nvidia.com/compute/cuda/12.2.0/local_installers/cuda-repo-ubuntu2204-12-2-local_12.2.0-535.54.03-1_amd64.deb
        dpkg -i cuda-repo-ubuntu2204-12-2-local_12.2.0-535.54.03-1_amd64.deb
        cp /var/cuda-repo-ubuntu2204-12-2-local/cuda-*-keyring.gpg /usr/share/keyrings/
        apt update
        apt install -y cuda

        log_message "NVIDIA drivers and CUDA installation completed."
    else
        log_message "No NVIDIA GPU detected. Skipping NVIDIA drivers and CUDA installation."
    fi
}

# Install Docker and NVIDIA Container Toolkit
install_docker() {
    log_message "Installing Docker..."
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt update
    apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

    if lspci | grep -i nvidia > /dev/null; then
        log_message "Installing NVIDIA Container Toolkit..."
        curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
        curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
            sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
            tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
        apt update
        apt install -y nvidia-container-toolkit
        nvidia-ctk runtime configure --runtime=docker
        systemctl restart docker
    fi
}

# Configure Git
configure_git() {
    log_message "Configuring Git..."
    git config --global submodule.recurse true
    git config --global credential.helper store
    git config --global user.email "vesiassr@gmail.com"
    git config --global user.name "Vesias"
}

# Configure LVM
configure_lvm() {
    log_message "Configuring LVM..."
    vg_name=$(lvs --noheadings -o vg_name /dev/mapper/ubuntu--vg-ubuntu--lv | tr -d ' ')
    pv_device=$(pvs --noheadings -o pv_name | grep $(vgs --noheadings -o pv_name $vg_name | tr -d ' ') | tr -d ' ')
    
    root_lv="/dev/mapper/ubuntu--vg-ubuntu--lv"
    current_size=$(lvs --noheadings --units k -o lv_size $root_lv | tr -d ' K' | cut -d'.' -f1)
    lvm_partition_size=$(lsblk -nlo SIZE -b $pv_device | awk '{print int($1/1024)}')
    extend_size=$((lvm_partition_size - current_size - 4096))

    if [ $extend_size -gt 0 ]; then
        log_message "Extending the logical volume by $((extend_size / 1024))MB..."
        lvextend -L +${extend_size}K $root_lv
        resize2fs $root_lv
    else
        log_message "No significant space available for LVM extension."
    fi
}

# Install Node.js and Yarn
install_nodejs_yarn() {
    log_message "Installing Node.js and Yarn..."
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
    apt install -y nodejs
    npm install --global yarn
}

# Install Cockpit
install_cockpit() {
    log_message "Installing Cockpit..."
    apt install -y cockpit
    systemctl enable --now cockpit.socket
}

# Create aliases
create_aliases() {
    log_message "Creating aliases..."
    echo "alias update='sudo apt update && sudo apt upgrade -y && sudo apt autoremove -y'" >> /etc/bash.bashrc
}

# Optimize system for server use
optimize_system() {
    log_message "Optimizing system for server use..."
    # Adjust swappiness
    echo "vm.swappiness=10" | tee -a /etc/sysctl.conf
    # Enable trim for SSDs
    systemctl enable fstrim.timer
    # Disable unnecessary services
    systemctl disable bluetooth.service
    systemctl disable cups.service
    # Increase file descriptor limit
    echo "* soft nofile 65535" | tee -a /etc/security/limits.conf
    echo "* hard nofile 65535" | tee -a /etc/security/limits.conf
}

# Main function
main() {
    log_message "Starting Ubuntu 24.04 LTS server setup..."

    update_system
    install_essentials
    install_nvidia_cuda
    install_docker
    configure_git
    configure_lvm
    install_nodejs_yarn
    install_cockpit
    create_aliases
    optimize_system

    log_message "Setup completed successfully."
    warning "A system reboot is recommended to complete the installation."
}

# Run main function
main

log_message "Script execution completed. Please consider rebooting your system to finalize the installation."

# Print system information
log_message "System Information:"
uname -a
if command -v nvidia-smi &> /dev/null; then
    nvidia-smi
fi
if command -v docker &> /dev/null; then
    docker --version
fi
if command -v node &> /dev/null; then
    node --version
fi
if command -v yarn &> /dev/null; then
    yarn --version
fi
log_message "Disk Usage:"
df -h
lsblk
