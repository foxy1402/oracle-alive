#!/bin/bash
#
# Oracle Cloud Keep-Alive Installer
# One-command installation for Oracle Cloud free tier instances
#
# Usage:
#   Install:   sudo bash install.sh
#   Uninstall: sudo bash install.sh --uninstall
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Installation paths
INSTALL_DIR="/opt/oracle-keep-alive"
SERVICE_FILE="/etc/systemd/system/oracle-keep-alive.service"
CONFIG_FILE="/etc/default/oracle-keep-alive"

print_header() {
    echo -e "${BLUE}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║           Oracle Cloud Keep-Alive Installer                  ║"
    echo "║   Prevents free tier instances from being reclaimed          ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠ $1${NC}"; }
print_error() { echo -e "${RED}✗ $1${NC}"; }
print_info() { echo -e "${BLUE}ℹ $1${NC}"; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

uninstall() {
    print_header
    echo "Uninstalling Oracle Cloud Keep-Alive..."
    echo
    
    # Stop and disable service
    if systemctl is-active --quiet oracle-keep-alive 2>/dev/null; then
        print_info "Stopping service..."
        systemctl stop oracle-keep-alive
        print_success "Service stopped"
    fi
    
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
        rm -f "$CONFIG_FILE"
        print_success "Removed config file"
    fi
    
    # Reload systemd
    systemctl daemon-reload
    
    echo
    print_success "Uninstallation complete!"
    echo
    echo "Note: Log files at /var/log/oracle-keep-alive.log were not removed."
    echo "Remove manually if needed: sudo rm /var/log/oracle-keep-alive.log"
}

install() {
    print_header
    echo "Installing Oracle Cloud Keep-Alive..."
    echo
    
    # Get script directory
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    # Check if source files exist
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
    
    # Create default config file
    print_info "Creating default configuration..."
    cat > "$CONFIG_FILE" << 'EOF'
# Oracle Cloud Keep-Alive Configuration
# Modify these values to customize behavior

# How long to run stress operations (seconds)
STRESS_DURATION=30

# How long to sleep between stress cycles (seconds)
SLEEP_DURATION=60

# Target CPU percentage
TARGET_CPU_PERCENT=20

# Memory to allocate during stress (in MB)
MEMORY_STRESS_MB=100

# Enable/disable specific stress types (1=enabled, 0=disabled)
STRESS_CPU=1
STRESS_MEMORY=1
STRESS_NETWORK=1

# Log file location
LOG_FILE=/var/log/oracle-keep-alive.log

# Network stress targets (space-separated IP addresses)
NETWORK_TARGETS="8.8.8.8 1.1.1.1"
EOF
    print_success "Created config at $CONFIG_FILE"
    
    # Install logrotate config if logrotate is available
    if [[ -d "/etc/logrotate.d" ]]; then
        print_info "Installing logrotate configuration..."
        if [[ -f "$SCRIPT_DIR/oracle-keep-alive.logrotate" ]]; then
            cp "$SCRIPT_DIR/oracle-keep-alive.logrotate" /etc/logrotate.d/oracle-keep-alive
            print_success "Installed logrotate config (logs will rotate daily, keep 7 days)"
        else
            # Create inline if file not found
            cat > /etc/logrotate.d/oracle-keep-alive << 'LOGROTATE'
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
            print_success "Created logrotate config"
        fi
    fi
    
    # Reload systemd
    print_info "Reloading systemd..."
    systemctl daemon-reload
    print_success "Systemd reloaded"
    
    # Enable service
    print_info "Enabling service to start on boot..."
    systemctl enable oracle-keep-alive
    print_success "Service enabled"
    
    # Start service
    print_info "Starting service..."
    systemctl start oracle-keep-alive
    print_success "Service started"
    
    echo
    print_success "Installation complete!"
    echo
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  Oracle Cloud Keep-Alive is now running!                      ${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
    echo
    echo "Useful commands:"
    echo "  Check status:    sudo systemctl status oracle-keep-alive"
    echo "  View logs:       sudo tail -f /var/log/oracle-keep-alive.log"
    echo "  Stop service:    sudo systemctl stop oracle-keep-alive"
    echo "  Restart:         sudo systemctl restart oracle-keep-alive"
    echo "  Edit config:     sudo nano /etc/default/oracle-keep-alive"
    echo
    echo "To uninstall: sudo bash $SCRIPT_DIR/install.sh --uninstall"
}

# Main
check_root

case "${1:-}" in
    --uninstall|-u|uninstall)
        uninstall
        ;;
    --help|-h)
        echo "Usage: sudo bash install.sh [OPTIONS]"
        echo
        echo "Options:"
        echo "  (none)        Install Oracle Cloud Keep-Alive"
        echo "  --uninstall   Uninstall Oracle Cloud Keep-Alive"
        echo "  --help        Show this help message"
        ;;
    *)
        install
        ;;
esac
