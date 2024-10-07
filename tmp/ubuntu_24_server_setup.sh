#!/bin/bash

# Ubuntu 24.04 LTS NVIDIA Server Setup Script
# This script sets up a Ubuntu 24.04 LTS server with NVIDIA drivers, CUDA, Docker, and other essential tools.

set -euo pipefail
IFS=$'\n\t'

# Define variables
LOG_FILE="/var/log/server_setup.log"

# Function to log messages
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Check if script is run as root
if [[ $EUID -ne 0 ]]; then
   log_message "This script must be run as root"
   exit 1
fi

# Update and upgrade system
log_message "Updating and upgrading system..."
apt-get update && DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

# Install essential utilities
log_message "Installing essential utilities..."
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    curl wget git build-essential software-properties-common \
    apt-transport-https ca-certificates gnupg lsb-release \
    make sysstat p7zip-full bzip2 unzip tar gdebi \
    htop neofetch bpytop nala \
    qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils

# Install Python 3.10 and pip
log_message "Installing Python 3.10 and pip..."
add-apt-repository -y ppa:deadsnakes/ppa
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y python3.10 python3.10-venv python3.10-dev
curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py
python3.10 get-pip.py
rm get-pip.py

# Set up Python aliases
echo "alias python=python3.10" >> /etc/bash.bashrc
echo "alias pip='python3.10 -m pip'" >> /etc/bash.bashrc

# Install NVIDIA drivers and CUDA
log_message "Installing NVIDIA drivers and CUDA..."
add-apt-repository -y ppa:graphics-drivers/ppa
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y nvidia-driver-560 nvidia-utils-560

# Install CUDA
wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-ubuntu2204.pin
mv cuda-ubuntu2204.pin /etc/apt/preferences.d/cuda-repository-pin-600
wget https://developer.download.nvidia.com/compute/cuda/12.2.0/local_installers/cuda-repo-ubuntu2204-12-2-local_12.2.0-535.54.03-1_amd64.deb
dpkg -i cuda-repo-ubuntu2204-12-2-local_12.2.0-535.54.03-1_amd64.deb
cp /var/cuda-repo-ubuntu2204-12-2-local/cuda-*-keyring.gpg /usr/share/keyrings/
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y cuda

# Set up CUDA environment variables
echo 'export PATH=/usr/local/cuda/bin${PATH:+:${PATH}}' >> /etc/bash.bashrc
echo 'export LD_LIBRARY_PATH=/usr/local/cuda/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}' >> /etc/bash.bashrc

# Install Docker
log_message "Installing Docker..."
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Install NVIDIA Container Toolkit
log_message "Installing NVIDIA Container Toolkit..."
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
    sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y nvidia-container-toolkit
nvidia-ctk runtime configure --runtime=docker
systemctl restart docker

# Configure Git
log_message "Configuring Git..."
git config --global submodule.recurse true
git config --global credential.helper store
git config --global user.email "vesiassr@gmail.com"
git config --global user.name "Vesias"

# LVM Configuration
log_message "Configuring LVM..."
vg_name=$(lvs --noheadings -o vg_name /dev/mapper/ubuntu--vg-ubuntu--lv | tr -d ' ')
pv_device=$(pvs --noheadings -o pv_name | grep $(vgs --noheadings -o pv_name $vg_name | tr -d ' ') | tr -d ' ')
current_size=$(lvs --noheadings --units k -o lv_size /dev/mapper/ubuntu--vg-ubuntu--lv | tr -d ' K' | cut -d'.' -f1)
lvm_partition_size=$(lsblk -nlo SIZE -b $pv_device | awk '{print int($1/1024)}')
extend_size=$((lvm_partition_size - current_size - 4096))

if [ $extend_size -gt 0 ]; then
    log_message "Extending the logical volume by $((extend_size / 1024))MB..."
    lvextend -L +${extend_size}K /dev/mapper/ubuntu--vg-ubuntu--lv
    resize2fs /dev/mapper/ubuntu--vg-ubuntu--lv
else
    log_message "No significant space available for LVM extension."
fi

# Create update alias
echo "alias update='sudo apt update && sudo apt upgrade -y && sudo apt autoremove -y && sudo snap refresh'" >> /etc/bash.bashrc

# Optimize system for server use
log_message "Optimizing system for server use..."
echo "vm.swappiness=10" | tee -a /etc/sysctl.conf
systemctl enable fstrim.timer
systemctl disable bluetooth.service
systemctl disable cups.service
echo -e "* soft nofile 65535\n* hard nofile 65535" >> /etc/security/limits.conf

# Final system update and cleanup
log_message "Performing final system update and cleanup..."
apt-get update && DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
apt-get autoremove -y
apt-get autoclean

# Verify installations
log_message "Verifying installations..."
nvidia-smi
nvcc --version
docker --version
python3.10 --version

log_message "Installation completed successfully. Please reboot the system to complete the setup."

# Print system information
log_message "System Information:"
uname -a
df -h
lsblk

log_message "Setup script execution completed."
