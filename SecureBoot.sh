#!/bin/bash

# Configuration
SECURE_BOOT=true
INSTALL_REFIND=true
INSTALL_DRIVERS=true
INSTALL_UTILITIES=true
INSTALL_APPS=true

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print section headers
print_section() {
    echo -e "\n${BLUE}=== $1 ===${NC}"
}

# Function to print status messages
print_status() {
    echo -e "${GREEN}[+]${NC} $1"
}

# Function to print warnings
print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

# Function to print errors
print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "Please run as root"
        exit 1
    fi
}

# Function to check if UEFI is available
check_uefi() {
    if [ ! -d /sys/firmware/efi ]; then
        print_error "This system does not appear to be using UEFI"
        print_error "Secure Boot requires UEFI firmware"
        exit 1
    fi
}

# Function to check if secure boot is enabled
check_secure_boot() {
    if [ -d /sys/firmware/efi ] && [ -f /sys/firmware/efi/vars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c/data ]; then
        local secure_boot_status=$(od -An -t u1 /sys/firmware/efi/vars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c/data)
        if [ "$secure_boot_status" -eq 1 ]; then
            print_status "Secure Boot is enabled"
            return 0
        else
            print_warning "Secure Boot is disabled"
            return 1
        fi
    else
        print_warning "Not running on UEFI system or cannot determine Secure Boot status"
        return 2
    fi
}

# Function to install secure boot dependencies
install_secure_boot_deps() {
    print_section "Installing Secure Boot Dependencies"
    
    # Check if we're on Arch Linux or Debian/Ubuntu
    if command -v pacman &> /dev/null; then
        # Arch Linux
        pacman -S --needed --noconfirm shim-signed sbsigntools efibootmgr mokutil
    elif command -v apt-get &> /dev/null; then
        # Debian/Ubuntu
        apt-get update
        apt-get install -y shim-signed sbsigntools efibootmgr mokutil
    else
        print_error "Unsupported distribution for automatic Secure Boot setup"
        return 1
    fi
    
    return 0
}

# Function to setup shim and MOK
setup_shim_and_mok() {
    print_section "Setting up Shim and Machine Owner Key (MOK)"
    
    local esp_mount="/boot/efi"
    local refind_dir="$esp_mount/EFI/refind"
    
    # Copy shim to ESP
    if [ -f "/usr/share/shim-signed/shimx64.efi" ]; then
        cp "/usr/share/shim-signed/shimx64.efi" "$esp_mount/EFI/BOOT/BOOTX64.EFI"
        cp "/usr/share/shim-signed/shimx64.efi" "$refind_dir/shimx64.efi"
        print_status "Shim copied to ESP"
    fi
    
    # Copy MokManager
    if [ -f "/usr/share/shim-signed/mmx64.efi" ]; then
        cp "/usr/share/shim-signed/mmx64.efi" "$esp_mount/EFI/BOOT/"
        cp "/usr/share/shim-signed/mmx64.efi" "$refind_dir/"
        print_status "MokManager copied to ESP"
    fi
    
    # Sign rEFInd with your key (if you have one) or use shim's built-in validation
    if command -v sbsign &> /dev/null; then
        # This assumes you have a key - for initial setup, shim will handle this
        if [ -f "$refind_dir/refind_x64.efi" ]; then
            print_warning "Note: For full Secure Boot, you should sign rEFInd with your own keys"
            print_warning "See: https://www.rodsbooks.com/refind/secureboot.html"
        fi
    fi
    
    # Create shim configuration
    local shim_config="$refind_dir/shim.conf"
    tee "$shim_config" > /dev/null << EOF
# Shim configuration for rEFInd
default_efi=EFI/refind/refind_x64.efi
timeout=5
verbose
EOF
    print_status "Shim configuration created"

    # Update refind.conf to work with shim
    local refind_conf="$refind_dir/refind.conf"
    if [ -f "$refind_conf" ]; then
        # Backup original config
        cp "$refind_conf" "$refind_conf.backup.$(date +%Y%m%d)"
        
        # Ensure no duplicate entries
        sed -i '/use_nvram/d' "$refind_conf"
        sed -i '/use_graphics_for/d' "$refind_conf"
        
        # Add secure boot compatible settings
        echo "use_nvram false" | tee -a "$refind_conf" > /dev/null
        echo "use_graphics_for linux,android" | tee -a "$refind_conf" > /dev/null
        print_status "rEFInd configuration updated for Secure Boot"
    fi
    
    return 0
}

# Function to enroll MOK
enroll_mok() {
    print_section "Machine Owner Key Enrollment"
    
    # This would typically be done manually after reboot
    print_warning "After reboot, you will need to:"
    print_warning "1. Enter UEFI setup and enable Secure Boot"
    print_warning "2. On first boot with Secure Boot, MokManager will appear"
    print_warning "3. Follow prompts to enroll your keys"
    print_warning "4. Select 'Enroll key from disk' and choose your key"
    
    # Create a reminder script for post-install
    local reminder_script="/tmp/secure_boot_reminder.sh"
    cat > "$reminder_script" << EOF
#!/bin/bash
echo "Secure Boot Setup Instructions:"
echo "1. Reboot and enter UEFI/BIOS setup (usually F2, Del, or F10)"
echo "2. Enable Secure Boot mode"
echo "3. Save changes and exit"
echo "4. On boot, MokManager should appear - follow prompts to enroll keys"
echo "5. For rEFInd, you may need to enroll the rEFInd key if not using shim"
EOF
    
    chmod +x "$reminder_script"
    print_status "Secure Boot setup instructions saved to: $reminder_script"
}

# Function to setup secure boot
setup_secure_boot() {
    if [ "$SECURE_BOOT" = true ]; then
        print_section "Setting Up Secure Boot"
        
        check_secure_boot
        local secure_boot_status=$?
        
        if [ $secure_boot_status -eq 0 ]; then
            print_status "Secure Boot is already enabled"
        else
            print_warning "Setting up Secure Boot components..."
            
            install_secure_boot_deps
            if [ $? -eq 0 ]; then
                setup_shim_and_mok
                enroll_mok
                
                print_status "Secure Boot components installed successfully"
                print_warning "Remember to enable Secure Boot in your UEFI settings after reboot"
            else
                print_error "Failed to install Secure Boot dependencies"
            fi
        fi
    else
        print_warning "Secure Boot setup skipped (SECURE_BOOT=false)"
    fi
}

# Function to install rEFInd
install_refind() {
    if [ "$INSTALL_REFIND" = true ]; then
        print_section "Installing rEFInd Boot Manager"
        
        # Check if we're on Arch Linux or Debian/Ubuntu
        if command -v pacman &> /dev/null; then
            # Arch Linux
            pacman -S --needed --noconfirm refind
            refind-install
        elif command -v apt-get &> /dev/null; then
            # Debian/Ubuntu
            apt-get install -y refind
            refind-install
        else
            print_error "Unsupported distribution for automatic rEFInd setup"
            return 1
        fi
        
        # Configure rEFInd for dual boot
        local esp_mount="/boot/efi"
        local refind_dir="$esp_mount/EFI/refind"
        local refind_conf="$refind_dir/refind.conf"
        
        if [ -f "$refind_conf" ]; then
            # Backup original config
            cp "$refind_conf" "$refind_conf.backup.$(date +%Y%m%d)"
            
            # Enable graphical mode and add Windows entry
            sed -i 's/#use_graphics_for/usegraphics_for/' "$refind_conf"
            sed -i 's/#scanfor/scanfor/' "$refind_conf"
            
            # Add Windows boot entry if not already present
            if ! grep -q "Windows" "$refind_conf"; then
                cat >> "$refind_conf" << EOF

# Windows boot manager
menuentry "Windows" {
    icon /EFI/refind/icons/os_win.png
    loader /EFI/Microsoft/Boot/bootmgfw.efi
}

EOF
            fi
            print_status "rEFInd configured for dual boot"
        fi
        
        print_status "rEFInd installed successfully"
    else
        print_warning "rEFInd installation skipped (INSTALL_REFIND=false)"
    fi
}

# Function to install drivers
install_drivers() {
    if [ "$INSTALL_DRIVERS" = true ]; then
        print_section "Installing Drivers"
        
        # Check if we're on Arch Linux or Debian/Ubuntu
        if command -v pacman &> /dev/null; then
            # Arch Linux - install common drivers
            pacman -S --needed --noconfirm \
                mesa \
                vulkan-radeon \
                libva-mesa-driver \
                mesa-vdpau \
                networkmanager \
                wireless_tools \
                wpa_supplicant
        elif command -v apt-get &> /dev/null; then
            # Debian/Ubuntu - install common drivers
            apt-get install -y \
                mesa-vulkan-drivers \
                libva-mesa-driver \
                mesa-vdpau-drivers \
                network-manager \
                wireless-tools \
                wpasupplicant
        fi
        
        print_status "Drivers installed successfully"
    else
        print_warning "Driver installation skipped (INSTALL_DRIVERS=false)"
    fi
}

# Function to install utilities
install_utilities() {
    if [ "$INSTALL_UTILITIES" = true ]; then
        print_section "Installing Utilities"
        
        # Check if we're on Arch Linux or Debian/Ubuntu
        if command -v pacman &> /dev/null; then
            # Arch Linux - install useful utilities
            pacman -S --needed --noconfirm \
                base-devel \
                git \
                vim \
                htop \
                curl \
                wget \
                rsync \
                unzip \
                ntfs-3g \
                exfat-utils \
                dosfstools
        elif command -v apt-get &> /dev/null; then
            # Debian/Ubuntu - install useful utilities
            apt-get install -y \
                build-essential \
                git \
                vim \
                htop \
                curl \
                wget \
                rsync \
                unzip \
                ntfs-3g \
                exfat-fuse \
                exfat-utils \
                dosfstools
        fi
        
        print_status "Utilities installed successfully"
    else
        print_warning "Utilities installation skipped (INSTALL_UTILITIES=false)"
    fi
}

# Function to install applications
install_apps() {
    if [ "$INSTALL_APPS" = true ]; then
        print_section "Installing Applications"
        
        # Check if we're on Arch Linux or Debian/Ubuntu
        if command -v pacman &> /dev/null; then
            # Arch Linux - install common applications
            pacman -S --needed --noconfirm \
                firefox \
                thunderbird \
                gparted \
                gimp \
                vlc \
                libreoffice-fresh
        elif command -v apt-get &> /dev/null; then
            # Debian/Ubuntu - install common applications
            apt-get install -y \
                firefox \
                thunderbird \
                gparted \
                gimp \
                vlc \
                libreoffice
        fi
        
        print_status "Applications installed successfully"
    else
        print_warning "Applications installation skipped (INSTALL_APPS=false)"
    fi
}

# Main execution function
main() {
    print_section "Starting System Installation and Configuration"
    
    # Check prerequisites
    check_root
    check_uefi
    
    # Install components
    install_refind
    install_drivers
    install_utilities
    install_apps
    
    # Setup secure boot
    setup_secure_boot
    
    print_section "Installation Completed"
    print_status "All components installed successfully"
    print_warning "Please reboot and complete the Secure Boot enrollment process if enabled"
}

# Run main function
main "$@"
