#!/bin/bash

# Secure Boot Configuration
SECURE_BOOT=true
SHIM_VERSION="0.9"
MOKUTIL_VERSION="0.3.0"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to check if secure boot is enabled
check_secure_boot() {
    if [ -d /sys/firmware/efi ] && [ -f /sys/firmware/efi/vars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c/data ]; then
        local secure_boot_status=$(od -An -t u1 /sys/firmware/efi/vars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c/data)
        if [ "$secure_boot_status" -eq 1 ]; then
            echo -e "${GREEN}Secure Boot is enabled${NC}"
            return 0
        else
            echo -e "${YELLOW}Secure Boot is disabled${NC}"
            return 1
        fi
    else
        echo -e "${YELLOW}Not running on UEFI system or cannot determine Secure Boot status${NC}"
        return 2
    fi
}

# Function to install secure boot dependencies
install_secure_boot_deps() {
    echo -e "${BLUE}Installing Secure Boot dependencies...${NC}"
    
    # Check if we're on Arch Linux or Debian/Ubuntu
    if command -v pacman &> /dev/null; then
        # Arch Linux
        sudo pacman -S --needed --noconfirm shim-signed sbsigntools efibootmgr mokutil
    elif command -v apt-get &> /dev/null; then
        # Debian/Ubuntu
        sudo apt-get update
        sudo apt-get install -y shim-signed sbsigntools efibootmgr mokutil
    else
        echo -e "${RED}Unsupported distribution for automatic Secure Boot setup${NC}"
        return 1
    fi
    
    return 0
}

# Function to setup shim and MOK
setup_shim_and_mok() {
    echo -e "${BLUE}Setting up Shim and Machine Owner Key (MOK)...${NC}"
    
    local esp_mount="/boot/efi"
    local refind_dir="$esp_mount/EFI/refind"
    
    # Copy shim to ESP
    if [ -f "/usr/share/shim-signed/shimx64.efi" ]; then
        sudo cp "/usr/share/shim-signed/shimx64.efi" "$esp_mount/EFI/BOOT/BOOTX64.EFI"
        sudo cp "/usr/share/shim-signed/shimx64.efi" "$refind_dir/shimx64.efi"
    fi
    
    # Copy MokManager
    if [ -f "/usr/share/shim-signed/mmx64.efi" ]; then
        sudo cp "/usr/share/shim-signed/mmx64.efi" "$esp_mount/EFI/BOOT/"
        sudo cp "/usr/share/shim-signed/mmx64.efi" "$refind_dir/"
    fi
    
    # Sign rEFInd with your key (if you have one) or use shim's built-in validation
    if command -v sbsign &> /dev/null; then
        # This assumes you have a key - for initial setup, shim will handle this
        if [ -f "$refind_dir/refind_x64.efi" ]; then
            echo -e "${YELLOW}Note: For full Secure Boot, you should sign rEFInd with your own keys${NC}"
            echo -e "${YELLOW}See: https://www.rodsbooks.com/refind/secureboot.html${NC}"
        fi
    fi
    
    # Create shim configuration
    local shim_config="$refind_dir/shim.conf"
    sudo tee "$shim_config" > /dev/null << EOF
# Shim configuration for rEFInd
default_efi=EFI/refind/refind_x64.efi
timeout=5
verbose
EOF

    # Update refind.conf to work with shim
    local refind_conf="$refind_dir/refind.conf"
    if [ -f "$refind_conf" ]; then
        # Backup original config
        sudo cp "$refind_conf" "$refind_conf.backup.$(date +%Y%m%d)"
        
        # Ensure no duplicate entries
        sudo sed -i '/use_nvram/d' "$refind_conf"
        sudo sed -i '/use_graphics_for/d' "$refind_conf"
        
        # Add secure boot compatible settings
        echo "use_nvram false" | sudo tee -a "$refind_conf" > /dev/null
        echo "use_graphics_for linux,android" | sudo tee -a "$refind_conf" > /dev/null
    fi
    
    return 0
}

# Function to enroll MOK
enroll_mok() {
    echo -e "${BLUE}Setting up Machine Owner Key enrollment...${NC}"
    
    # This would typically be done manually after reboot
    echo -e "${YELLOW}After reboot, you will need to:${NC}"
    echo -e "${YELLOW}1. Enter UEFI setup and enable Secure Boot${NC}"
    echo -e "${YELLOW}2. On first boot with Secure Boot, MokManager will appear${NC}"
    echo -e "${YELLOW}3. Follow prompts to enroll your keys${NC}"
    echo -e "${YELLOW}4. Select 'Enroll key from disk' and choose your key${NC}"
    
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
    echo -e "${GREEN}Secure Boot setup instructions saved to: $reminder_script${NC}"
}

# Function to check and setup secure boot
setup_secure_boot() {
    if [ "$SECURE_BOOT" = true ]; then
        echo -e "${BLUE}Checking Secure Boot status...${NC}"
        
        check_secure_boot
        local secure_boot_status=$?
        
        if [ $secure_boot_status -eq 0 ]; then
            echo -e "${GREEN}Secure Boot is already enabled${NC}"
        else
            echo -e "${YELLOW}Setting up Secure Boot components...${NC}"
            
            install_secure_boot_deps
            if [ $? -eq 0 ]; then
                setup_shim_and_mok
                enroll_mok
                
                echo -e "${GREEN}Secure Boot components installed successfully${NC}"
                echo -e "${YELLOW}Remember to enable Secure Boot in your UEFI settings after reboot${NC}"
            else
                echo -e "${RED}Failed to install Secure Boot dependencies${NC}"
            fi
        fi
    else
        echo -e "${YELLOW}Secure Boot setup skipped (SECURE_BOOT=false)${NC}"
    fi
}

# Main execution
main() {
    echo -e "${BLUE}Starting Secure Boot setup...${NC}"
    
    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}Please run as root${NC}"
        exit 1
    fi
    
    # Check if UEFI
    if [ ! -d /sys/firmware/efi ]; then
        echo -e "${RED}This system does not appear to be using UEFI${NC}"
        echo -e "${RED}Secure Boot requires UEFI firmware${NC}"
        exit 1
    fi
    
    # Setup secure boot
    setup_secure_boot
    
    echo -e "${GREEN}Secure Boot setup completed${NC}"
    echo -e "${YELLOW}Please reboot and complete the MOK enrollment process${NC}"
}

# Run main function
main "$@"
