#!/bin/bash
#
# Oracle Cloud Fixed-Mode Keep-Alive Installer v1.0
# Installs the fixed-mode keep-alive service
#
# Usage:
#   Install:   sudo bash install-fixed.sh
#   Uninstall: sudo bash install-fixed.sh --uninstall
#

set -euo pipefail

VERSION="1.0.0"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Installation paths
INSTALL_DIR="/opt/oracle-keep-alive"
SERVICE_FILE="/etc/systemd/system/oracle-fixed-mode.service"
CONFIG_FILE="/etc/default/oracle-fixed-mode"
LOGROTATE_FILE="/etc/logrotate.d/oracle-fixed-mode"

print_header() {
    echo -e "${BLUE}"
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║     Oracle Cloud Fixed-Mode Installer v${VERSION}              ║"
    echo "║     Continuous Monitoring Edition                              ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠ $1${NC}"; }
print_error() { echo -e "${RED}✗ $1${NC}"; }
print_info() { echo -e "${CYAN}ℹ $1${NC}"; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

check_system() {
    print_info "Checking system compatibility..."
    
    # Detect OS
    local os_name="Unknown"
    local os_version="Unknown"
    local pkg_manager="unknown"
    
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        os_name="$NAME"
        os_version="$VERSION_ID"
    fi
    
    print_info "Detected OS: $os_name $os_version"
    
    # Determine package manager
    if command -v apt-get &> /dev/null; then
        pkg_manager="apt"
        print_success "Package manager: apt (Ubuntu/Debian)"
    elif command -v yum &> /dev/null; then
        pkg_manager="yum"
        print_success "Package manager: yum (Oracle Linux/RHEL)"
    elif command -v dnf &> /dev/null; then
        pkg_manager="dnf"
        print_success "Package manager: dnf (Fedora/RHEL 8+)"
    else
        print_warning "No supported package manager found (apt/yum/dnf)"
    fi
    
    # Check if systemd is available
    if ! command -v systemctl &> /dev/null; then
        print_error "systemd not found. This installer requires systemd."
        exit 1
    fi
    
    # Check for required commands
    local missing_deps=()
    local missing_packages=()
    
    declare -A pkg_map_apt=(
        ["free"]="procps"
        ["awk"]="gawk"
        ["ip"]="iproute2"
        ["nproc"]="coreutils"
        ["dd"]="coreutils"
    )
    
    declare -A pkg_map_yum=(
        ["free"]="procps-ng"
        ["awk"]="gawk"
        ["ip"]="iproute"
        ["nproc"]="coreutils"
        ["dd"]="coreutils"
    )
    
    for cmd in bash free awk ip nproc dd; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
            
            if [[ "$pkg_manager" == "apt" ]]; then
                missing_packages+=("${pkg_map_apt[$cmd]}")
            else
                missing_packages+=("${pkg_map_yum[$cmd]}")
            fi
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        print_warning "Missing commands: ${missing_deps[*]}"
        print_info "Installing packages: ${missing_packages[*]}"
        
        if [[ "$pkg_manager" == "apt" ]]; then
            print_info "Updating package lists..."
            apt-get update -qq || print_warning "apt-get update failed"
            apt-get install -y -qq "${missing_packages[@]}" 2>&1 | grep -v "^Reading" || true
        elif [[ "$pkg_manager" == "yum" ]]; then
            yum install -y -q "${missing_packages[@]}" 2>/dev/null || true
        elif [[ "$pkg_manager" == "dnf" ]]; then
            dnf install -y -q "${missing_packages[@]}" 2>/dev/null || true
        fi
        
        local still_missing=()
        for cmd in "${missing_deps[@]}"; do
            if ! command -v "$cmd" &> /dev/null; then
                still_missing+=("$cmd")
            fi
        done
        
        if [[ ${#still_missing[@]} -gt 0 ]]; then
            print_error "Failed to install: ${still_missing[*]}"
            print_info "Please install manually and re-run installer"
            exit 1
        else
            print_success "All dependencies installed"
        fi
    else
        print_success "All required dependencies present"
    fi
    
    # Check for optional stress-ng
    if ! command -v stress-ng &> /dev/null; then
        print_warning "stress-ng not found - using fallback CPU stress method"
        
        if [[ "$pkg_manager" == "apt" ]]; then
            print_info "Optional: sudo apt install stress-ng -y (for better CPU control)"
        elif [[ "$pkg_manager" == "yum" ]] || [[ "$pkg_manager" == "dnf" ]]; then
            print_info "Optional: sudo yum install stress-ng -y (for better CPU control)"
        fi
    else
        print_success "stress-ng available (optimal CPU control)"
    fi
    
    # Warn about ping: required only if ENABLE_NETWORK=true is added to config later
    if ! command -v ping &> /dev/null; then
        print_warning "ping not found - network stress will not work if ENABLE_NETWORK=true is set"
        if [[ "$pkg_manager" == "apt" ]]; then
            print_info "To enable network stress later: sudo apt install iputils-ping -y"
        else
            print_info "To enable network stress later: sudo yum install iputils -y"
        fi
    fi
    
    print_success "System check complete"
}

uninstall() {
    print_header
    echo "Uninstalling Oracle Cloud Fixed-Mode Keep-Alive..."
    echo
    
    # Stop service
    if systemctl is-active --quiet oracle-fixed-mode 2>/dev/null; then
        print_info "Stopping service..."
        systemctl stop oracle-fixed-mode
        print_success "Service stopped"
    fi
    
    # Disable service
    if systemctl is-enabled --quiet oracle-fixed-mode 2>/dev/null; then
        print_info "Disabling service..."
        systemctl disable oracle-fixed-mode
        print_success "Service disabled"
    fi
    
    # Remove files
    if [[ -f "$SERVICE_FILE" ]]; then
        rm -f "$SERVICE_FILE"
        print_success "Removed service file"
    fi
    
    if [[ -f "$INSTALL_DIR/fixedmode.sh" ]]; then
        rm -f "$INSTALL_DIR/fixedmode.sh"
        print_success "Removed script"
    fi
    
    if [[ -f "$CONFIG_FILE" ]]; then
        print_warning "Config file preserved at: $CONFIG_FILE"
        print_info "Remove manually if needed: sudo rm $CONFIG_FILE"
    fi
    
    if [[ -f "$LOGROTATE_FILE" ]]; then
        rm -f "$LOGROTATE_FILE"
        print_success "Removed logrotate config"
    fi
    
    # Reload systemd
    systemctl daemon-reload
    
    echo
    print_success "Uninstallation complete!"
    echo
    print_info "Log files at /var/log/oracle-fixed-mode.log were preserved"
    print_info "Remove manually: sudo rm /var/log/oracle-fixed-mode.log*"
}

install() {
    print_header
    
    check_system
    
    echo
    echo "Installing Oracle Cloud Fixed-Mode Keep-Alive..."
    echo
    
    # Get script directory
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    # Check source files
    if [[ ! -f "$SCRIPT_DIR/fixedmode.sh" ]]; then
        print_error "fixedmode.sh not found in $SCRIPT_DIR"
        exit 1
    fi
    
    if [[ ! -f "$SCRIPT_DIR/oracle-fixed-mode.service" ]]; then
        print_error "oracle-fixed-mode.service not found in $SCRIPT_DIR"
        exit 1
    fi
    
    # Create installation directory
    print_info "Creating installation directory..."
    mkdir -p "$INSTALL_DIR"
    print_success "Created $INSTALL_DIR"
    
    # Copy script
    print_info "Installing fixedmode script..."
    cp "$SCRIPT_DIR/fixedmode.sh" "$INSTALL_DIR/"
    chmod +x "$INSTALL_DIR/fixedmode.sh"
    print_success "Installed fixedmode.sh"
    
    # Install systemd service
    print_info "Installing systemd service..."
    cp "$SCRIPT_DIR/oracle-fixed-mode.service" "$SERVICE_FILE"
    print_success "Installed service file"
    
    # Create/update config file
    if [[ -f "$SCRIPT_DIR/config-fixed.env" ]]; then
        if [[ ! -f "$CONFIG_FILE" ]]; then
            print_info "Installing default configuration..."
            cp "$SCRIPT_DIR/config-fixed.env" "$CONFIG_FILE"
            print_success "Installed configuration"
        else
            print_warning "Existing config preserved at $CONFIG_FILE"
        fi
    fi
    
    # Install logrotate config
    if [[ -d "/etc/logrotate.d" ]]; then
        print_info "Installing logrotate configuration..."
        if [[ -f "$SCRIPT_DIR/oracle-fixed-mode.logrotate" ]]; then
            cp "$SCRIPT_DIR/oracle-fixed-mode.logrotate" "$LOGROTATE_FILE"
        else
            cat > "$LOGROTATE_FILE" << 'LOGROTATE'
/var/log/oracle-fixed-mode.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
    copytruncate
}
LOGROTATE
        fi
        print_success "Installed logrotate config"
    fi
    
    # Reload systemd
    print_info "Reloading systemd..."
    systemctl daemon-reload
    print_success "Systemd reloaded"
    
    # Enable service
    print_info "Enabling service..."
    systemctl enable oracle-fixed-mode
    print_success "Service enabled"
    
    # Start service
    print_info "Starting service..."
    systemctl start oracle-fixed-mode
    
    # Wait a moment for service to start
    sleep 2
    
    # Check if started successfully
    if systemctl is-active --quiet oracle-fixed-mode; then
        print_success "Service started successfully"
    else
        print_error "Service failed to start"
        print_info "Check logs: sudo journalctl -u oracle-fixed-mode -n 50"
        exit 1
    fi
    
    echo
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  ✓ Installation Complete - Fixed-Mode is Running!             ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo
    
    # Show configuration summary
    echo -e "${CYAN}Configuration Summary:${NC}"
    echo "  • Mode: Continuous monitoring (no sleep cycles)"
    echo "  • Default Targets: CPU 25%, Memory 30%"
    echo "  • Network Stress: disabled by default"
    echo "  • Check Interval: 3 seconds"
    echo "  • Dashboard: Stable horizontal lines"
    echo
    
    echo -e "${CYAN}Useful Commands:${NC}"
    echo "  Check status:    ${YELLOW}sudo systemctl status oracle-fixed-mode${NC}"
    echo "  View logs:       ${YELLOW}sudo tail -f /var/log/oracle-fixed-mode.log${NC}"
    echo "  Stop service:    ${YELLOW}sudo systemctl stop oracle-fixed-mode${NC}"
    echo "  Restart:         ${YELLOW}sudo systemctl restart oracle-fixed-mode${NC}"
    echo "  Edit targets:    ${YELLOW}sudo nano /etc/default/oracle-fixed-mode${NC}"
    echo
    
    echo -e "${CYAN}Customizing Your Targets:${NC}"
    echo "  1. Edit: ${YELLOW}sudo nano /etc/default/oracle-fixed-mode${NC}"
    echo "  2. Set TARGET_CPU_PERCENT and TARGET_MEMORY_PERCENT"
    echo "  3. Save and restart: ${YELLOW}sudo systemctl restart oracle-fixed-mode${NC}"
    echo "  4. Watch Oracle Cloud Console metrics (updates every ~5 minutes)"
    echo
    
    echo -e "${YELLOW}⚠  Single-CPU Optimization:${NC}"
    echo "  • CPU stress is automatically capped at 95%"
    echo "  • Proportional control prevents overshoot"
    echo "  • Safe to set TARGET_CPU_PERCENT=25 on 1-CPU systems"
    echo
    
    echo -e "${YELLOW}⚠  Oracle Reclaim Prevention:${NC}"
    echo "  • Oracle reclaims instances if ALL metrics < 20% for 7 days"
    echo "  • This script maintains CPU and Memory targets 24/7 (no gaps)"
    echo "  • Check Oracle Console after 1 hour to verify"
    echo "  • CPU and Memory graphs should show stable horizontal lines"
    echo
    
    echo "To uninstall: ${YELLOW}sudo bash $SCRIPT_DIR/install-fixed.sh --uninstall${NC}"
    echo
    
    print_info "Showing recent logs..."
    echo
    tail -n 20 /var/log/oracle-fixed-mode.log 2>/dev/null || journalctl -u oracle-fixed-mode -n 20 --no-pager
}

show_help() {
    print_header
    echo "Usage: sudo bash install-fixed.sh [OPTIONS]"
    echo
    echo "Options:"
    echo "  (none)         Install Oracle Cloud Fixed-Mode Keep-Alive"
    echo "  --uninstall    Uninstall Oracle Cloud Fixed-Mode Keep-Alive"
    echo "  --help         Show this help message"
    echo "  --version      Show version information"
    echo
    echo "Examples:"
    echo "  sudo bash install-fixed.sh              # Install with defaults"
    echo "  sudo bash install-fixed.sh --uninstall  # Remove installation"
    echo
    echo "After installation, set your targets at:"
    echo "  /etc/default/oracle-fixed-mode"
    echo
    echo "Then restart: sudo systemctl restart oracle-fixed-mode"
}

show_version() {
    echo "Oracle Cloud Fixed-Mode Installer v${VERSION}"
    echo "Continuous Monitoring Edition"
    echo
    echo "Features:"
    echo "  • Manual target setting (CPU and RAM)"
    echo "  • Network stress disabled by default (enable via ENABLE_NETWORK=true)"
    echo "  • No sleep cycles - continuous 3s monitoring loop"
    echo "  • Proportional control prevents overshoot"
    echo "  • Self-healing: auto-restarts failed processes"
    echo "  • Single-CPU optimized (prevents 100% lockup)"
    echo "  • Creates stable dashboard lines"
    echo
}

# Main
check_root

case "${1:-}" in
    --uninstall|-u|uninstall)
        uninstall
        ;;
    --help|-h|help)
        show_help
        ;;
    --version|-v|version)
        show_version
        ;;
    *)
        install
        ;;
esac
