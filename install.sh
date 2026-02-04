#!/bin/bash
#
# Oracle Cloud Keep-Alive Installer v2.0
# Enhanced version with gaming VPN optimization
#
# Usage:
#   Install:   sudo bash install.sh
#   Uninstall: sudo bash install.sh --uninstall
#

set -euo pipefail

VERSION="2.2.0"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Installation paths
INSTALL_DIR="/opt/oracle-keep-alive"
SERVICE_FILE="/etc/systemd/system/oracle-keep-alive.service"
CONFIG_FILE="/etc/default/oracle-keep-alive"
LOGROTATE_FILE="/etc/logrotate.d/oracle-keep-alive"

print_header() {
    echo -e "${BLUE}"
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║     Oracle Cloud Keep-Alive Installer v${VERSION}             ║"
    echo "║     Parallel Stress Edition                                    ║"
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
    
    # Map commands to package names (different across distros)
    declare -A pkg_map_apt=(
        ["curl"]="curl"
        ["ping"]="iputils-ping"
        ["free"]="procps"
        ["awk"]="gawk"
        ["ip"]="iproute2"
        ["nproc"]="coreutils"
    )
    
    declare -A pkg_map_yum=(
        ["curl"]="curl"
        ["ping"]="iputils"
        ["free"]="procps-ng"
        ["awk"]="gawk"
        ["ip"]="iproute"
        ["nproc"]="coreutils"
    )
    
    for cmd in bash curl ping free awk ip nproc; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
            
            # Add package name based on distro
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
        
        # Verify installation
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
    
    # Check for optional traffic shaping support
    if ! command -v tc &> /dev/null; then
        print_warning "tc (traffic control) not found - traffic shaping will be disabled"
        
        if [[ "$pkg_manager" == "apt" ]]; then
            print_info "Optional: sudo apt install iproute2 -y (for gaming optimization)"
        elif [[ "$pkg_manager" == "yum" ]]; then
            print_info "Optional: sudo yum install iproute -y (for gaming optimization)"
        fi
    else
        print_success "Traffic shaping support available"
    fi
    
    # Ubuntu-specific: Check if unattended-upgrades is running
    if [[ "$pkg_manager" == "apt" ]]; then
        if systemctl is-active --quiet unattended-upgrades 2>/dev/null; then
            print_info "Note: unattended-upgrades is active (may cause CPU spikes)"
        fi
    fi
    
    print_success "System check complete"
}

uninstall() {
    print_header
    echo "Uninstalling Oracle Cloud Keep-Alive..."
    echo
    
    # Stop service
    if systemctl is-active --quiet oracle-keep-alive 2>/dev/null; then
        print_info "Stopping service..."
        systemctl stop oracle-keep-alive
        print_success "Service stopped"
    fi
    
    # Disable service
    if systemctl is-enabled --quiet oracle-keep-alive 2>/dev/null; then
        print_info "Disabling service..."
        systemctl disable oracle-keep-alive
        print_success "Service disabled"
    fi
    
    # Remove files
    if [[ -f "$SERVICE_FILE" ]]; then
        rm -f "$SERVICE_FILE"
        print_success "Removed service file"
    fi
    
    if [[ -d "$INSTALL_DIR" ]]; then
        rm -rf "$INSTALL_DIR"
        print_success "Removed installation directory"
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
    print_info "Log files at /var/log/oracle-keep-alive.log were preserved"
    print_info "Remove manually: sudo rm /var/log/oracle-keep-alive.log*"
}

install() {
    print_header
    
    check_system
    
    echo
    echo "Installing Oracle Cloud Keep-Alive..."
    echo
    
    # Get script directory
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    # Check source files
    if [[ ! -f "$SCRIPT_DIR/keep-alive.sh" ]]; then
        print_error "keep-alive.sh not found in $SCRIPT_DIR"
        exit 1
    fi
    
    if [[ ! -f "$SCRIPT_DIR/oracle-keep-alive.service" ]]; then
        print_error "oracle-keep-alive.service not found in $SCRIPT_DIR"
        exit 1
    fi
    
    # Create installation directory
    print_info "Creating installation directory..."
    mkdir -p "$INSTALL_DIR"
    print_success "Created $INSTALL_DIR"
    
    # Copy script
    print_info "Installing keep-alive script..."
    cp "$SCRIPT_DIR/keep-alive.sh" "$INSTALL_DIR/"
    chmod +x "$INSTALL_DIR/keep-alive.sh"
    print_success "Installed keep-alive.sh"
    
    # Install systemd service
    print_info "Installing systemd service..."
    cp "$SCRIPT_DIR/oracle-keep-alive.service" "$SERVICE_FILE"
    print_success "Installed service file"
    
    # Create/update config file
    if [[ -f "$SCRIPT_DIR/config.env" ]]; then
        print_info "Installing configuration from config.env..."
        cp "$SCRIPT_DIR/config.env" "$CONFIG_FILE"
        print_success "Installed custom configuration"
    elif [[ ! -f "$CONFIG_FILE" ]]; then
        print_info "Creating default configuration..."
        cat > "$CONFIG_FILE" << 'EOF'
# Oracle Cloud Keep-Alive Configuration v2.2
# Parallel Stress Edition

# Target Metrics (40% = double Oracle's 20% minimum)
TARGET_CPU_PERCENT=40
TARGET_MEMORY_PERCENT=40
TARGET_NETWORK_PERCENT=40
SAFETY_MARGIN=5

# CPU Stress Configuration
STRESS_CPU=1
CPU_STRESS_PERCENT=50
CPU_STRESS_DURATION=64
CPU_SLEEP_DURATION=0
CPU_RECALIBRATION_CYCLES=12
CPU_STRESS_FLOOR=40
CPU_WORKERS=""

# Memory Stress Configuration
STRESS_MEMORY=1
MEMORY_STRESS_MB=500
MEMORY_NETWORK_DURATION=90

# Network Stress Configuration (Gaming Optimized)
STRESS_NETWORK=1
NETWORK_STRESS_MODE="smart"
NETWORK_BANDWIDTH_LIMIT_KBS=500
NETWORK_USE_DISTRIBUTED_TARGETS=1
NETWORK_PING_TARGETS="8.8.8.8 8.8.4.4 1.1.1.1 1.0.0.1 208.67.222.222 208.67.220.220"
NETWORK_HTTP_TARGETS="http://www.google.com/generate_204 http://detectportal.firefox.com/success.txt http://captive.apple.com/hotspot-detect.html https://www.cloudflare.com/cdn-cgi/trace"
NETWORK_ENABLE_DOWNLOAD_TEST=1
NETWORK_DOWNLOAD_TEST_URL="http://speedtest.ftp.otenet.gr/files/test100k.db"
NETWORK_USE_TRAFFIC_SHAPING=1
NETWORK_TRAFFIC_PRIORITY=7

# Monitoring
MONITORING_INTERVAL=300
BASELINE_DURATION=60

# Logging
LOG_FILE=/var/log/oracle-keep-alive.log
LOG_LEVEL=INFO
LOG_STATS_EVERY_N_CYCLES=6

# Advanced
PROCESS_NICE_LEVEL=19
IO_SCHEDULING_CLASS=idle
EOF
        print_success "Created default configuration"
    else
        print_warning "Existing config preserved at $CONFIG_FILE"
    fi
    
    # Install logrotate config
    if [[ -d "/etc/logrotate.d" ]]; then
        print_info "Installing logrotate configuration..."
        cat > "$LOGROTATE_FILE" << 'LOGROTATE'
/var/log/oracle-keep-alive.log {
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
        print_success "Installed logrotate config"
    fi
    
    # Reload systemd
    print_info "Reloading systemd..."
    systemctl daemon-reload
    print_success "Systemd reloaded"
    
    # Enable service
    print_info "Enabling service..."
    systemctl enable oracle-keep-alive
    print_success "Service enabled"
    
    # Start service
    print_info "Starting service..."
    systemctl start oracle-keep-alive
    
    # Wait a moment for service to start
    sleep 2
    
    # Check if started successfully
    if systemctl is-active --quiet oracle-keep-alive; then
        print_success "Service started successfully"
    else
        print_error "Service failed to start"
        print_info "Check logs: sudo journalctl -u oracle-keep-alive -n 50"
        exit 1
    fi
    
    echo
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  ✓ Installation Complete - Oracle Keep-Alive is Running!      ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo
    
    # Show configuration summary
    echo -e "${CYAN}Configuration Summary:${NC}"
    echo "  • Cycle Duration: 96s (64s CPU + 90s Memory/Network parallel)"
    echo "  • Target All Metrics: 45% (40% + 5% margin)"
    echo "  • CPU Recalibration: Every 12 cycles (~20 minutes)"
    echo "  • Network Mode: Smart (gaming-optimized)"
    echo "  • Bandwidth Limit: 500 KB/s"
    echo
    
    echo -e "${CYAN}Useful Commands:${NC}"
    echo "  Check status:    ${YELLOW}sudo systemctl status oracle-keep-alive${NC}"
    echo "  View logs:       ${YELLOW}sudo tail -f /var/log/oracle-keep-alive.log${NC}"
    echo "  Stop service:    ${YELLOW}sudo systemctl stop oracle-keep-alive${NC}"
    echo "  Restart:         ${YELLOW}sudo systemctl restart oracle-keep-alive${NC}"
    echo "  Edit config:     ${YELLOW}sudo nano /etc/default/oracle-keep-alive${NC}"
    echo
    
    echo -e "${CYAN}Next Steps:${NC}"
    echo "  1. Watch logs for 2-3 minutes to verify operation"
    echo "  2. Check Oracle Cloud metrics in console after 1 hour"
    echo "  3. Test your gaming VPN - expect <1ms latency impact"
    echo "  4. Monitor metrics weekly for first month"
    echo
    
    echo -e "${YELLOW}⚠  Important:${NC}"
    echo "  • At least ONE metric must stay above 20% to avoid reclaim"
    echo "  • Default settings target 40% (double minimum) on all metrics"
    echo "  • Gaming traffic is prioritized over keep-alive traffic"
    echo "  • See README.md for troubleshooting and optimization"
    echo
    
    echo "To uninstall: ${YELLOW}sudo bash $SCRIPT_DIR/install.sh --uninstall${NC}"
    echo
    
    print_info "Showing recent logs..."
    echo
    tail -n 20 /var/log/oracle-keep-alive.log 2>/dev/null || journalctl -u oracle-keep-alive -n 20 --no-pager
}

show_help() {
    print_header
    echo "Usage: sudo bash install.sh [OPTIONS]"
    echo
    echo "Options:"
    echo "  (none)         Install Oracle Cloud Keep-Alive"
    echo "  --uninstall    Uninstall Oracle Cloud Keep-Alive"
    echo "  --help         Show this help message"
    echo "  --version      Show version information"
    echo
    echo "Examples:"
    echo "  sudo bash install.sh              # Install with default settings"
    echo "  sudo bash install.sh --uninstall  # Remove installation"
    echo
    echo "After installation, customize settings at:"
    echo "  /etc/default/oracle-keep-alive"
    echo
    echo "Then restart: sudo systemctl restart oracle-keep-alive"
}

show_version() {
    echo "Oracle Cloud Keep-Alive Installer v${VERSION}"
    echo "Parallel Stress Edition"
    echo
    echo "Features:"
    echo "  • Parallel CPU/Memory/Network stress"
    echo "  • 96-second cycles (67% CPU duty, 94% memory/network duty)"
    echo "  • Matches Oracle's monitoring methodology exactly"
    echo "  • Dynamic CPU recalibration every 20 minutes"
    echo "  • Gaming-friendly (won't lag your VPN)"
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
