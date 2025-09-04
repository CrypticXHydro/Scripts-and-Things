#!/usr/bin/env bash

# Improved Linux Software Installation Script
# Features: Better error handling, logging, dependency checking, and user options

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging
LOG_FILE="/tmp/install_script_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

# Distribution detection
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO=$ID
        DISTRO_VERSION=$VERSION_ID
    else
        echo -e "${RED}Failed to detect distribution. Exiting.${NC}"
        exit 1
    fi
}

# Package manager functions
update_packages() {
    echo -e "${BLUE}Updating package lists...${NC}"
    case $DISTRO in
        ubuntu|debian|pop)
            sudo apt-get update
            ;;
        fedora)
            sudo dnf check-update || true  # dnf returns exit code 100 when updates available
            ;;
        arch|manjaro)
            sudo pacman -Syy
            ;;
        *)
            echo -e "${YELLOW}Unsupported distribution for auto-update.${NC}"
            ;;
    esac
}

install_package() {
    local package=$1
    echo -e "${BLUE}Installing $package...${NC}"
    case $DISTRO in
        ubuntu|debian|pop)
            sudo apt-get install -y "$package"
            ;;
        fedora)
            sudo dnf install -y "$package"
            ;;
        arch|manjaro)
            sudo pacman -S --noconfirm "$package"
            ;;
        *)
            echo -e "${YELLOW}Cannot install $package on unknown distribution.${NC}"
            return 1
            ;;
    esac
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to install with error handling
safe_install() {
    local package=$1
    if ! install_package "$package"; then
        echo -e "${YELLOW}Failed to install $package. Continuing...${NC}"
        return 1
    fi
    return 0
}

# Function to install Snap packages
install_snap() {
    if command_exists snap; then
        local package=$1
        echo -e "${BLUE}Installing $package via Snap...${NC}"
        sudo snap install "$package" --classic
    else
        echo -e "${YELLOW}Snap not available. Skipping $package.${NC}"
        return 1
    fi
}

# Function to install Flatpak packages
install_flatpak() {
    if command_exists flatpak; then
        local package=$1
        echo -e "${BLUE}Installing $package via Flatpak...${NC}"
        flatpak install -y "$package"
    else
        echo -e "${YELLOW}Flatpak not available. Skipping $package.${NC}"
        return 1
    fi
}

# Function to install from custom repositories
add_repository_and_install() {
    local repo_info=$1
    local package=$2
    
    case $DISTRO in
        ubuntu|debian|pop)
            # For Debian-based systems, add PPAs or external repos
            case $package in
                "brave-browser")
                    echo -e "${BLUE}Adding Brave browser repository...${NC}"
                    sudo apt install -y curl
                    sudo curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg \
                        https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg
                    echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg] \
                        https://brave-browser-apt-release.s3.brave.com/ stable main" | \
                        sudo tee /etc/apt/sources.list.d/brave-browser-release.list
                    sudo apt update
                    safe_install "brave-browser"
                    ;;
                *)
                    echo -e "${YELLOW}Unknown repository package: $package${NC}"
                    ;;
            esac
            ;;
        *)
            echo -e "${YELLOW}Custom repositories not configured for $DISTRO. Skipping $package.${NC}"
            ;;
    esac
}

# Function to install using package type detection
install_by_type() {
    local package=$1
    local install_type=$2
    
    case $install_type in
        "standard")
            safe_install "$package"
            ;;
        "snap")
            install_snap "$package"
            ;;
        "flatpak")
            install_flatpak "$package"
            ;;
        "repo")
            add_repository_and_install "" "$package"
            ;;
        "deb")
            if [[ $DISTRO == "ubuntu" || $DISTRO == "debian" || $DISTRO == "pop" ]]; then
                echo -e "${BLUE}Installing .deb package: $package${NC}"
                wget -O /tmp/"$package".deb "$package"
                sudo dpkg -i /tmp/"$package".deb
                sudo apt-get install -f -y
                rm /tmp/"$package".deb
            else
                echo -e "${YELLOW}DEB packages not supported on $DISTRO. Skipping.${NC}"
            fi
            ;;
        *)
            safe_install "$package"
            ;;
    esac
}

# Main installation function
main_install() {
    echo -e "${GREEN}Starting installation process on $DISTRO...${NC}"
    
    # Update package lists
    update_packages
    
    # Essential tools (always install these)
    local essentials=("curl" "wget" "git" "htop" "vim" "tmux" "zip" "unzip")
    for package in "${essentials[@]}"; do
        safe_install "$package"
    done
    
    # Define packages with their installation methods
    declare -A packages=(
        # Development tools
        ["code"]="snap"               # Visual Studio Code
        ["node"]="snap"               # Node.js
        ["python3"]="standard"        # Python 3
        ["python3-pip"]="standard"    # Pip for Python 3
        ["default-jdk"]="standard"    # Java Development Kit
        ["docker.io"]="standard"      # Docker
        ["docker-compose"]="standard" # Docker Compose
        
        # Browsers
        ["brave-browser"]="repo"      # Brave browser
        ["firefox"]="standard"        # Firefox
        
        # Communication
        ["discord"]="snap"            # Discord
        ["slack"]="snap"              # Slack
        
        # Utilities
        ["vlc"]="standard"            # VLC Media Player
        ["gimp"]="standard"           # GIMP Image Editor
        ["inkscape"]="flatpak"        # Inkscape
    )
    
    # Install all defined packages
    for package in "${!packages[@]}"; do
        install_by_type "$package" "${packages[$package]}"
    done
    
    # Special cases
    echo -e "${BLUE}Installing Chrome...${NC}"
    if [[ $DISTRO == "ubuntu" || $DISTRO == "debian" || $DISTRO == "pop" ]]; then
        wget -O /tmp/google-chrome-stable_current_amd64.deb \
            https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
        sudo dpkg -i /tmp/google-chrome-stable_current_amd64.deb
        sudo apt-get install -f -y
        rm /tmp/google-chrome-stable_current_amd64.deb
    else
        echo -e "${YELLOW}Chrome installation not configured for $DISTRO.${NC}"
    fi
    
    # Install Spotify
    echo -e "${BLUE}Installing Spotify...${NC}"
    if command_exists snap; then
        install_snap "spotify"
    else
        echo -e "${YELLOW}Snap not available. Cannot install Spotify.${NC}"
    fi
    
    # Install Zoom
    echo -e "${BLUE}Installing Zoom...${NC}"
    if [[ $DISTRO == "ubuntu" || $DISTRO == "debian" || $DISTRO == "pop" ]]; then
        wget -O /tmp/zoom_amd64.deb https://zoom.us/client/latest/zoom_amd64.deb
        sudo dpkg -i /tmp/zoom_amd64.deb
        sudo apt-get install -f -y
        rm /tmp/zoom_amd64.deb
    else
        echo -e "${YELLOW}Zoom installation not configured for $DISTRO.${NC}"
    fi
    
    echo -e "${GREEN}Installation complete!${NC}"
    echo -e "${BLUE}Log file: $LOG_FILE${NC}"
}

# Display usage information
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  -h, --help      Show this help message"
    echo "  -l, --list      List available packages"
    echo "  -s, --skip      Skip essential packages installation"
    echo "  -u, --update    Update system only (no package installation)"
}

# Parse command line arguments
SKIP_ESSENTIALS=false
UPDATE_ONLY=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -l|--list)
            echo "Available packages:"
            for package in "${!packages[@]}"; do
                echo "  - $package (${packages[$package]})"
            done
            exit 0
            ;;
        -s|--skip)
            SKIP_ESSENTIALS=true
            shift
            ;;
        -u|--update)
            UPDATE_ONLY=true
            shift
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            usage
            exit 1
            ;;
    esac
done

# Main execution
detect_distro

if [ "$UPDATE_ONLY" = true ]; then
    update_packages
    exit 0
fi

main_install
