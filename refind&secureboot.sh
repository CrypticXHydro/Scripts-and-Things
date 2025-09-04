#!/bin/bash

# rEFInd Shim Installer for Arch Linux + Windows Dual Boot
# This script installs and configures rEFInd with Secure Boot support

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    print_error "This script must be run as root"
    exit 1
fi

# Check if we're on UEFI system
if [[ ! -d /sys/firmware/efi ]]; then
    print_error "This system does not appear to be using UEFI. Exiting."
    exit 1
fi

# Install required packages
print_status "Installing required packages..."
pacman -S --noconfirm refind shim-signed sbsigntools efibootmgr

# Backup existing rEFInd configuration if it exists
if [[ -f /boot/EFI/refind/refind.conf ]]; then
    print_status "Backing up existing refind.conf..."
    cp /boot/EFI/refind/refind.conf /boot/EFI/refind/refind.conf.backup
fi

# Copy shim and MokManager to rEFInd directory
print_status "Setting up Shim and MokManager..."
cp /usr/share/shim-signed/shimx64.efi /boot/EFI/refind/shimx64.efi
cp /usr/share/shim-signed/mmx64.efi /boot/EFI/refind/mmx64.efi

# Sign rEFInd with sbsign
print_status "Signing rEFInd binary..."
if [[ -f /boot/EFI/refind/refind_x64.efi ]]; then
    sbsign --key /etc/refind.d/keys/refind_local.key --cert /etc/refind.d/keys/refind_local.crt --output /boot/EFI/refind/refind_x64.efi /boot/EFI/refind/refind_x64.efi
else
    print_warning "rEFInd binary not found, skipping signing"
fi

# Create rEFInd configuration
print_status "Creating rEFInd configuration..."
cat > /boot/EFI/refind/refind.conf << 'EOF'
timeout 5
use_nvram false
use_graphics_for linux,windows
showtools shell, memtest, shutdown, reboot, exit
scanfor internal,external,optical,manual

# Main configuration
menuentry "Arch Linux" {
    icon /EFI/refind/icons/os_arch.png
    loader /vmlinuz-linux
    initrd /initramfs-linux.img
    options "root=PARTUUID=$(blkid -s PARTUUID -o value $(findmnt / -o SOURCE -n)) rw initrd=/initramfs-linux.img"
}

menuentry "Arch Linux (fallback)" {
    icon /EFI/refind/icons/os_arch.png
    loader /vmlinuz-linux
    initrd /initramfs-linux-fallback.img
    options "root=PARTUUID=$(blkid -s PARTUUID -o value $(findmnt / -o SOURCE -n)) rw initrd=/initramfs-linux-fallback.img"
}

menuentry "Windows Boot Manager" {
    icon /EFI/refind/icons/os_win.png
    loader /EFI/Microsoft/Boot/bootmgfw.efi
}

# Auto-detect other kernels
scan_driver_dirs drivers,drivers_x64
also_scan_dirs boot,EFI/boot,EFI/BOOT,EFI/Microsoft/Boot
extra_kernel_version_strings linux,linux-hardened,linux-lts,linux-zen
EOF

# Set up Secure Boot keys (optional - for custom signing)
print_status "Setting up Secure Boot keys directory..."
mkdir -p /etc/refind.d/keys
if [[ ! -f /etc/refind.d/keys/refind_local.key ]]; then
    print_status "Generating signing keys..."
    # You can generate keys with:
    # openssl req -newkey rsa:4096 -nodes -keyout /etc/refind.d/keys/refind_local.key -x509 -days 3650 -out /etc/refind.d/keys/refind_local.crt
    print_warning "No signing keys found. You may want to generate them for custom signing."
    print_warning "Run: openssl req -newkey rsa:4096 -nodes -keyout /etc/refind.d/keys/refind_local.key -x509 -days 3650 -out /etc/refind.d/keys/refind_local.crt"
fi

# Create NVRAM entry for shim
print_status "Creating UEFI boot entry for shim..."
efibootmgr -c -d /dev/$(lsblk -no pkname $(findmnt /boot -o SOURCE -n)) -p 1 -L "rEFInd Shim" -l \\EFI\\refind\\shimx64.efi

# Install rEFInd to EFI system partition
print_status "Installing rEFInd to EFI system partition..."
refind-install

# Copy icons
print_status "Copying icons..."
mkdir -p /boot/EFI/refind/icons
cp -r /usr/share/refind/icons/* /boot/EFI/refind/icons/ 2>/dev/null || true

# Set proper permissions
print_status "Setting permissions..."
chmod -R 755 /boot/EFI/refind/

print_status "Installation complete!"
echo ""
print_warning "IMPORTANT NEXT STEPS:"
echo "1. Reboot your system"
echo "2. Enter your UEFI/BIOS settings (usually by pressing F2, Del, or Esc during boot)"
echo "3. Add the shimx64.efi to your Secure Boot trusted signatures using MokManager"
echo "4. Set rEFInd as the first boot option"
echo "5. Save changes and exit"
echo ""
print_warning "For Secure Boot: You may need to enroll the MOK (Machine Owner Key) when prompted during boot"

# Show current boot entries
print_status "Current UEFI boot entries:"
efibootmgr -v
