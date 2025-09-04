#!/bin/bash

# rEFInd Shim Installer for Arch Linux + Windows Dual Boot
# This script installs and configures rEFInd with Secure Boot support
# Includes MOK enrollment guidance

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

# Function to check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        exit 1
    fi
}

# Function to check UEFI system
check_uefi() {
    if [[ ! -d /sys/firmware/efi ]]; then
        print_error "This system does not appear to be using UEFI. Exiting."
        exit 1
    fi
}

# Function to install packages
install_packages() {
    print_status "Installing required packages..."
    pacman -S --noconfirm refind shim-signed sbsigntools efibootmgr
}

# Function to setup rEFInd with Shim
setup_refind() {
    print_header "Setting up rEFInd with Shim and MokManager"
    
    # Backup existing rEFInd configuration if it exists
    if [[ -f /boot/EFI/refind/refind.conf ]]; then
        print_status "Backing up existing refind.conf..."
        cp /boot/EFI/refind/refind.conf /boot/EFI/refind/refind.conf.backup
    fi

    # Copy shim and MokManager to rEFInd directory
    print_status "Setting up Shim and MokManager..."
    cp /usr/share/shim-signed/shimx64.efi /boot/EFI/refind/shimx64.efi
    cp /usr/share/shim-signed/mmx64.efi /boot/EFI/refind/mmx64.efi

    # Sign rEFInd with sbsign if keys exist
    if [[ -f /etc/refind.d/keys/refind_local.key && -f /etc/refind.d/keys/refind_local.crt ]]; then
        print_status "Signing rEFInd binary with custom keys..."
        sbsign --key /etc/refind.d/keys/refind_local.key --cert /etc/refind.d/keys/refind_local.crt --output /boot/EFI/refind/refind_x64.efi /boot/EFI/refind/refind_x64.efi
    else
        print_warning "No custom signing keys found, using pre-signed binaries"
    fi

    # Create rEFInd configuration
    print_status "Creating rEFInd configuration..."
    
    # Get root partition UUID
    ROOT_PARTUUID=$(blkid -s PARTUUID -o value $(findmnt / -o SOURCE -n))
    
    cat > /boot/EFI/refind/refind.conf << EOF
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
    options "root=PARTUUID=$ROOT_PARTUUID rw initrd=/initramfs-linux.img"
}

menuentry "Arch Linux (fallback)" {
    icon /EFI/refind/icons/os_arch.png
    loader /vmlinuz-linux
    initrd /initramfs-linux-fallback.img
    options "root=PARTUUID=$ROOT_PARTUUID rw initrd=/initramfs-linux-fallback.img"
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

    # Set up Secure Boot keys directory
    print_status "Setting up Secure Boot keys directory..."
    mkdir -p /etc/refind.d/keys
    
    # Create NVRAM entry for shim
    print_status "Creating UEFI boot entry for shim..."
    ESP_DEVICE=$(findmnt /boot -o SOURCE -n | sed 's/[0-9]*$//')
    ESP_PARTITION=$(findmnt /boot -o SOURCE -n)
    PART_NUMBER=$(echo $ESP_PARTITION | grep -o '[0-9]*$')
    
    efibootmgr -c -d $ESP_DEVICE -p $PART_NUMBER -L "rEFInd Shim" -l \\EFI\\refind\\shimx64.efi

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
}

# Function to provide MOK enrollment guidance
mok_guidance() {
    print_header "MOK Enrollment Guidance"
    
    if [[ -f /etc/refind.d/keys/refind_local.crt ]]; then
        print_status "Found signing certificate, you can enroll this with MokManager:"
        echo "Certificate: /etc/refind.d/keys/refind_local.crt"
        echo ""
        print_warning "To enroll:"
        echo "1. Copy the certificate to a FAT32 USB drive"
        echo "2. Reboot and select MokManager from rEFInd"
        echo "3. Choose 'Enroll MOK' and follow prompts"
        echo "4. Select the certificate file from your USB drive"
    else
        print_warning "No custom certificate found. You'll need to enroll the shim certificate."
        echo "During boot, MokManager should prompt you to enroll the key."
    fi
    
    echo ""
    print_warning "Alternative: If you have issues with Secure Boot, you can:"
    echo "1. Temporarily disable Secure Boot in BIOS/UEFI settings"
    echo "2. Boot into your system"
    echo "3. Generate keys with:"
    echo "   openssl req -newkey rsa:4096 -nodes -keyout /etc/refind.d/keys/refind_local.key -x509 -days 3650 -out /etc/refind.d/keys/refind_local.crt"
    echo "4. Re-sign rEFInd: sbsign --key /etc/refind.d/keys/refind_local.key --cert /etc/refind.d/keys/refind_local.crt --output /boot/EFI/refind/refind_x64.efi /boot/EFI/refind/refind_x64.efi"
    echo "5. Re-enable Secure Boot and enroll the new key"
}

# Function to generate signing keys
generate_keys() {
    print_header "Generating Secure Boot Signing Keys"
    
    read -p "Do you want to generate signing keys now? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_status "Generating signing keys..."
        mkdir -p /etc/refind.d/keys
        openssl req -newkey rsa:4096 -nodes -keyout /etc/refind.d/keys/refind_local.key \
                  -x509 -days 3650 -out /etc/refind.d/keys/refind_local.crt
        print_status "Keys generated successfully!"
        
        # Sign rEFInd with the new keys
        print_status "Signing rEFInd with new keys..."
        sbsign --key /etc/refind.d/keys/refind_local.key \
               --cert /etc/refind.d/keys/refind_local.crt \
               --output /boot/EFI/refind/refind_x64.efi \
               /boot/EFI/refind/refind_x64.efi
    else
        print_warning "Skipping key generation. You can generate keys later with:"
        echo "openssl req -newkey rsa:4096 -nodes -keyout /etc/refind.d/keys/refind_local.key -x509 -days 3650 -out /etc/refind.d/keys/refind_local.crt"
    fi
}

# Function to show final instructions
final_instructions() {
    print_header "Installation Complete - Next Steps"
    
    print_status "1. Reboot your system"
    print_status "2. Enter your UEFI/BIOS settings (usually by pressing F2, Del, or Esc during boot)"
    print_status "3. Ensure 'rEFInd Shim' is set as the first boot option"
    
    print_warning "4. For Secure Boot:"
    echo "   - You may need to enroll the MOK (Machine Owner Key) when prompted during boot"
    echo "   - Or temporarily disable Secure Boot if you encounter issues"
    
    print_status "5. Save changes and exit BIOS/UEFI"
    
    echo ""
    print_warning "Current UEFI boot entries:"
    efibootmgr -v
}

# Main execution
main() {
    print_header "rEFInd with Shim Installer for Arch Linux + Windows"
    
    # Check prerequisites
    check_root
    check_uefi
    
    # Install packages
    install_packages
    
    # Setup rEFInd
    setup_refind
    
    # Offer to generate keys
    generate_keys
    
    # Provide MOK guidance
    mok_guidance
    
    # Show final instructions
    final_instructions
}

# Run main function
main "$@"
