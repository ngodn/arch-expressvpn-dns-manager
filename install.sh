#!/bin/bash

# ExpressVPN DNS Manager Installation Script
# Installs the DNS manager service for systemd-resolved DNS leak prevention

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="/usr/local/bin"
SERVICE_DIR="/etc/systemd/system"
SERVICE_NAME="expressvpn-dns-manager"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Detect ExpressVPN CLI command (v3.x uses 'expressvpn', v4.x uses 'expressvpnctl')
detect_expressvpn_command() {
    if command -v expressvpnctl &> /dev/null; then
        echo "expressvpnctl"
    elif command -v expressvpn &> /dev/null; then
        echo "expressvpn"
    else
        echo ""
    fi
}

# Check if ExpressVPN is installed and handle connection
check_expressvpn() {
    local EXPRESSVPN_CMD=$(detect_expressvpn_command)

    if [[ -z "$EXPRESSVPN_CMD" ]]; then
        log_error "ExpressVPN CLI not found. Please install ExpressVPN first."
        log_error "Looking for either 'expressvpn' (v3.x) or 'expressvpnctl' (v4.x)"
        exit 1
    fi
    log_info "ExpressVPN CLI found: $EXPRESSVPN_CMD"

    # Check if ExpressVPN is currently connected
    if $EXPRESSVPN_CMD status | grep -q "Connected"; then
        log_warn "ExpressVPN is currently connected"
        read -p "Disconnect ExpressVPN to proceed with installation? (Y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            log_info "Disconnecting ExpressVPN..."
            $EXPRESSVPN_CMD disconnect
            sleep 2
            if $EXPRESSVPN_CMD status | grep -q "Connected"; then
                log_error "Failed to disconnect ExpressVPN. Please disconnect manually and try again."
                exit 1
            else
                log_info "ExpressVPN disconnected successfully"
            fi
        else
            log_error "Installation cancelled. Please disconnect ExpressVPN manually and try again."
            exit 1
        fi
    else
        log_info "ExpressVPN is not connected"
    fi
}

# Check if systemd-resolved is available
check_systemd_resolved() {
    if ! systemctl is-active --quiet systemd-resolved; then
        log_warn "systemd-resolved is not running. The DNS manager requires systemd-resolved."
        read -p "Do you want to enable systemd-resolved? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            systemctl enable systemd-resolved
            systemctl start systemd-resolved
            log_info "systemd-resolved enabled and started"
        else
            log_error "systemd-resolved is required for this tool to work"
            exit 1
        fi
    fi
    log_info "systemd-resolved is active"
}



# Create backups of existing configurations
create_config_backups() {
    log_info "Creating backups of current configurations"
    
    # Backup systemd-resolved configuration
    if [[ -f "/etc/systemd/resolved.conf" ]]; then
        # Always backup current config, warn if overwriting previous backup
        if [[ -f "/etc/systemd/resolved.conf.backup-original" ]]; then
            log_warn "Overwriting existing systemd-resolved backup with current configuration"
        fi
        cp "/etc/systemd/resolved.conf" "/etc/systemd/resolved.conf.backup-original"
        log_info "Backed up current systemd-resolved configuration"
    fi
}

# Setup DNS management
setup_dns_management() {
    log_info "Preparing DNS management"
    
    # Create backups before any modifications
    create_config_backups
    
    # The DNS manager will handle systemd-resolved configuration
    log_info "DNS manager will manage systemd-resolved configuration only"
}

# Install the main script
install_script() {
    log_info "Installing DNS manager script to $INSTALL_DIR"
    cp "$SCRIPT_DIR/expressvpn-dns-manager.sh" "$INSTALL_DIR/"
    chmod +x "$INSTALL_DIR/expressvpn-dns-manager.sh"
    log_info "Script installed successfully"
}

# Install the systemd service
install_service() {
    log_info "Installing systemd service to $SERVICE_DIR"
    cp "$SCRIPT_DIR/expressvpn-dns-manager.service" "$SERVICE_DIR/"
    systemctl daemon-reload
    log_info "Service installed successfully"
}

# Create log directory
setup_logging() {
    log_info "Setting up logging"
    touch /var/log/expressvpn-dns-manager.log
    chmod 644 /var/log/expressvpn-dns-manager.log
}

# Enable and start service
enable_service() {
    log_info "Enabling and starting $SERVICE_NAME service"
    systemctl enable $SERVICE_NAME.service
    systemctl start $SERVICE_NAME.service
    
    # Check if service started successfully
    sleep 2
    if systemctl is-active --quiet $SERVICE_NAME.service; then
        log_info "Service started successfully"
    else
        log_error "Service failed to start. Check logs with: journalctl -u $SERVICE_NAME.service"
        exit 1
    fi
}

# Show installation summary
show_summary() {
    echo
    log_info "Installation completed successfully!"
    echo
    echo "Service Management:"
    echo "  Check service status: sudo systemctl status $SERVICE_NAME.service"
    echo "  View logs:           sudo journalctl -u $SERVICE_NAME.service -f"
    echo "  Stop service:        sudo systemctl stop $SERVICE_NAME.service"
    echo "  Disable service:     sudo systemctl disable $SERVICE_NAME.service"
    echo
    echo "Manual DNS Management:"
    echo "  Monitor mode:        sudo $INSTALL_DIR/expressvpn-dns-manager.sh monitor"
    echo "  Connect VPN DNS:     sudo $INSTALL_DIR/expressvpn-dns-manager.sh connect"
    echo "  Disconnect/Restore:  sudo $INSTALL_DIR/expressvpn-dns-manager.sh disconnect"
    echo "  Check status:        sudo $INSTALL_DIR/expressvpn-dns-manager.sh check"
    echo
    echo "DNS Testing & Optimization:"
    echo "  Test DNS speeds:     sudo $INSTALL_DIR/expressvpn-dns-manager.sh test-dns"
    echo "  Find fastest DNS:    sudo $INSTALL_DIR/expressvpn-dns-manager.sh find-fastest"
    echo
    echo "The service will automatically start monitoring ExpressVPN connections."
    echo "DNS configurations will be managed automatically when you connect/disconnect."
    echo
    echo "Configuration Backups Created:"
    if [[ -f "/etc/systemd/resolved.conf.backup-original" ]]; then
        echo "  - systemd-resolved: /etc/systemd/resolved.conf.backup-original"
    fi
    echo "  (Use 'sudo ./install.sh uninstall' to restore original configurations)"
    echo
}

# Check for required dependencies
check_dependencies() {
    log_info "Checking system dependencies"
    
    # Check for dig command (needed for DNS testing)
    if ! command -v dig &> /dev/null; then
        log_warn "dig command not found. Installing bind-tools for DNS testing..."
        if command -v pacman &> /dev/null; then
            pacman -S --noconfirm bind-tools
        else
            log_error "dig command required for DNS testing. Please install bind-tools package."
            exit 1
        fi
    fi
    
    log_info "All dependencies satisfied"
}

# Main installation process
main() {
    log_info "Starting ExpressVPN DNS Manager installation for vanilla Arch Linux"
    
    check_root
    check_expressvpn
    check_systemd_resolved
    check_dependencies
    
    # Check if files exist
    if [[ ! -f "$SCRIPT_DIR/expressvpn-dns-manager.sh" ]]; then
        log_error "expressvpn-dns-manager.sh not found in $SCRIPT_DIR"
        exit 1
    fi
    
    if [[ ! -f "$SCRIPT_DIR/expressvpn-dns-manager.service" ]]; then
        log_error "expressvpn-dns-manager.service not found in $SCRIPT_DIR"
        exit 1
    fi
    
    # Confirm installation
    echo "This will install ExpressVPN DNS Manager to prevent DNS leaks."
    echo "The service will automatically manage DNS settings when ExpressVPN connects/disconnects."
    echo "Features:"
    echo "  - Automatic DNS switching for ExpressVPN connections"
    echo "  - DNS speed testing and optimal server selection"
    echo "  - systemd-resolved integration"
    echo "  - Router DNS detection and fallback"
    echo
    read -p "Do you want to proceed with installation? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Installation cancelled"
        exit 0
    fi
    
    # Stop existing service if running
    if systemctl is-active --quiet $SERVICE_NAME.service; then
        log_info "Stopping existing service"
        systemctl stop $SERVICE_NAME.service
    fi
    
    install_script
    install_service
    setup_dns_management
    setup_logging
    enable_service
    show_summary
}

# Check ExpressVPN connection for uninstall
check_expressvpn_for_uninstall() {
    local EXPRESSVPN_CMD=$(detect_expressvpn_command)

    if [[ -n "$EXPRESSVPN_CMD" ]]; then
        log_info "ExpressVPN CLI found: $EXPRESSVPN_CMD"
        # Check if ExpressVPN is currently connected
        if $EXPRESSVPN_CMD status | grep -q "Connected"; then
            log_warn "ExpressVPN is currently connected"
            read -p "Disconnect ExpressVPN to proceed with clean uninstallation? (Y/n): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Nn]$ ]]; then
                log_info "Disconnecting ExpressVPN..."
                $EXPRESSVPN_CMD disconnect
                sleep 2
                if $EXPRESSVPN_CMD status | grep -q "Connected"; then
                    log_warn "Failed to disconnect ExpressVPN. Proceeding with uninstallation anyway."
                else
                    log_info "ExpressVPN disconnected successfully"
                fi
            else
                log_warn "Proceeding with uninstallation while ExpressVPN is connected"
                log_warn "DNS configuration may not be properly restored"
            fi
        else
            log_info "ExpressVPN is not connected"
        fi
    else
        log_info "ExpressVPN CLI not found (may have been uninstalled already)"
    fi
}

# Handle uninstallation
uninstall() {
    log_info "Starting ExpressVPN DNS Manager uninstallation"
    
    # Check ExpressVPN connection status
    check_expressvpn_for_uninstall
    
    # Stop and disable service
    if systemctl is-enabled --quiet $SERVICE_NAME.service 2>/dev/null; then
        log_info "Stopping and disabling service"
        systemctl stop $SERVICE_NAME.service
        systemctl disable $SERVICE_NAME.service
    fi
    
    # Remove service file
    if [[ -f "$SERVICE_DIR/$SERVICE_NAME.service" ]]; then
        rm "$SERVICE_DIR/$SERVICE_NAME.service"
        systemctl daemon-reload
        log_info "Service file removed"
    fi
    
    # Remove script
    if [[ -f "$INSTALL_DIR/expressvpn-dns-manager.sh" ]]; then
        rm "$INSTALL_DIR/expressvpn-dns-manager.sh"
        log_info "Script removed"
    fi
    
    # Remove log file
    if [[ -f "/var/log/expressvpn-dns-manager.log" ]]; then
        rm "/var/log/expressvpn-dns-manager.log"
        log_info "Log file removed"
    fi
    
    # Comprehensive configuration restoration
    echo
    log_info "Configuration restoration options:"
    
    # 1. Restore systemd-resolved configuration
    if [[ -f "/etc/systemd/resolved.conf.backup-original" ]]; then
        read -p "Restore original systemd-resolved configuration? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            cp "/etc/systemd/resolved.conf.backup-original" "/etc/systemd/resolved.conf"
            rm "/etc/systemd/resolved.conf.backup-original"
            log_info "Original systemd-resolved configuration restored and backup removed"
        else
            log_info "systemd-resolved backup kept at /etc/systemd/resolved.conf.backup-original"
        fi
    fi
    
    # 2. Restart DNS services
    read -p "Restart DNS services to apply changes? (Y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        systemctl restart systemd-resolved
        log_info "systemd-resolved restarted"
    fi
    
    echo
    log_info "Uninstallation completed successfully!"
    echo
    echo "Summary of what was removed:"
    echo "  - ExpressVPN DNS Manager service and script"
    echo "  - Log files"
    echo "  - DNS configurations (if selected)"
    echo
    echo "Your system should now be restored to its pre-installation state."
    echo
}

# Parse command line arguments
case "${1:-install}" in
    "install")
        main
        ;;
    "uninstall")
        check_root
        uninstall
        ;;
    *)
        echo "Usage: $0 {install|uninstall}"
        echo "  install   - Install ExpressVPN DNS Manager (default)"
        echo "  uninstall - Remove ExpressVPN DNS Manager"
        exit 1
        ;;
esac