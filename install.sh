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

VERSION="2.1.0"

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
    echo "║     Intelligent Multi-Metric Edition                          ║"
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
    
    # Check if systemd is available
    if ! command -v systemctl &> /dev/null; then
        print_error "systemd not found. This installer requires systemd."
        exit 1
    fi
    
    # Check for required commands
    local missing_deps=()
    
    for cmd in bash ping curl free; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        print_warning "Missing dependencies: ${missing_deps[*]}"
        print_info "Installing dependencies..."
        
        if command -v apt-get &> /dev/null; then
            apt-get update -qq
            apt-get install -y -qq "${missing_deps[@]}" 2>/dev/null || true
        elif command -v yum &> /dev/null; then
            yum install -y -q "${missing_deps[@]}" 2>/dev/null || true
        fi
    fi
    
    # Check for optional traffic shaping support
    if ! command -v tc &> /dev/null; then
        print_warning "tc (traffic control) not found - traffic shaping will be disabled"
        print_info "For gaming optimization, install: apt install iproute2 (Ubuntu) or yum install iproute (Oracle Linux)"
    else
        print_success "Traffic shaping support available"
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
# Oracle Cloud Keep-Alive Configuration v2.0
# Gaming VPN Optimized Settings

# Timing
STRESS_DURATION=45
SLEEP_DURATION=480

# CPU
STRESS_CPU=1
TARGET_CPU_PERCENT=95
CPU_WORKERS=""

# Memory
STRESS_MEMORY=1
MEMORY_STRESS_MB=150
MEMORY_HOLD_DURATION=10

# Network (Gaming Optimized)
STRESS_NETWORK=1
NETWORK_STRESS_MODE="smart"
NETWORK_BANDWIDTH_LIMIT_KBS=100
NETWORK_USE_DISTRIBUTED_TARGETS=1
NETWORK_PING_TARGETS="8.8.8.8 8.8.4.4 1.1.1.1 1.0.0.1 208.67.222.222 208.67.220.220"
NETWORK_PINGS_PER_TARGET=5
NETWORK_PING_INTERVAL=0.3
NETWORK_HTTP_TARGETS="http://www.google.com/generate_204 http://detectportal.firefox.com/success.txt http://captive.apple.com/hotspot-detect.html https://www.cloudflare.com/cdn-cgi/trace"
NETWORK_HTTP_REQUESTS=10
NETWORK_HTTP_TIMEOUT=3
NETWORK_ENABLE_DOWNLOAD_TEST=1
NETWORK_DOWNLOAD_TEST_URL="http://speedtest.ftp.otenet.gr/files/test100k.db"
NETWORK_USE_TRAFFIC_SHAPING=1
NETWORK_TRAFFIC_PRIORITY=7

# Logging
LOG_FILE=/var/log/oracle-keep-alive.log
LOG_LEVEL=INFO
LOG_STATS_EVERY_N_CYCLES=12

# Advanced
PROCESS_NICE_LEVEL=19
IO_SCHEDULING_CLASS=idle
AUTO_ADJUST_INTENSITY=1
METRIC_CHECK_INTERVAL=15
ENABLE_FAILSAFE_MODE=1
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
    echo "  • Stress Duration: 45s (active)"
    echo "  • Sleep Duration: 480s (8 minutes)"
    echo "  • Expected Avg CPU: ~8%"
    echo "  • Network Mode: Smart (gaming-optimized)"
    echo "  • Bandwidth Limit: 100 KB/s"
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
    echo "Intelligent Multi-Metric Edition"
    echo
    echo "Features:"
    echo "  • Automatic baseline detection"
    echo "  • Smart gap calculation"
    echo "  • Dynamic stress adjustment"
    echo "  • Triple protection (CPU/Memory/Network)"
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
