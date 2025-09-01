# ExpressVPN DNS Manager for Arch Linux

A simple and effective DNS management solution specifically designed for vanilla Arch Linux installations using ExpressVPN. This tool prevents DNS leaks by automatically managing systemd-resolved configuration when ExpressVPN connects or disconnects.

## Features

- **Automatic DNS Management**: Automatically switches DNS servers when ExpressVPN connects/disconnects
- **DNS Speed Testing**: Tests and selects the fastest DNS server for optimal performance
- **systemd-resolved Integration**: Simple and focused systemd-resolved configuration management
- **Router DNS Detection**: Automatically detects and uses router DNS when available
- **Multiple DNS Detection Methods**: Advanced ExpressVPN DNS server detection
- **IPv6 Support**: Handles both IPv4 and IPv6 DNS configurations
- **Simple Backup/Restore**: Backs up and restores systemd-resolved configuration

## Requirements

- Arch Linux (vanilla installation)
- ExpressVPN CLI installed and configured
- systemd-resolved (automatically enabled during installation)
- bind-tools package (for DNS testing - automatically installed)
- Root/sudo access

## Installation

1. Clone or download this repository
2. Run the installation script as root:

```bash
sudo ./install.sh
```

The installer will:
- Check for ExpressVPN installation
- Enable systemd-resolved if needed
- Install required dependencies (bind-tools)
- Set up the DNS manager service
- Create backup of current systemd-resolved configuration
- Start automatic monitoring

## DNS Servers

The tool supports and tests the following DNS servers:

**Google DNS:**
- IPv4: 8.8.8.8, 8.8.4.4
- IPv6: 2001:4860:4860::8888, 2001:4860:4860::8844

**Cloudflare DNS:**
- IPv4: 1.1.1.1, 1.0.0.1
- IPv6: 2606:4700:4700::1111, 2606:4700:4700::1001

**Router DNS:** Automatically detected from DHCP/gateway

## Usage

### Automatic Operation (Recommended)

The service runs automatically in the background:

```bash
# Check service status
sudo systemctl status expressvpn-dns-manager

# View logs
sudo journalctl -u expressvpn-dns-manager -f

# Stop/start service
sudo systemctl stop expressvpn-dns-manager
sudo systemctl start expressvpn-dns-manager
```

### Manual Commands

```bash
# Test DNS server speeds
sudo expressvpn-dns-manager.sh test-dns

# Find fastest DNS server
sudo expressvpn-dns-manager.sh find-fastest

# Manually configure VPN DNS
sudo expressvpn-dns-manager.sh connect

# Restore original DNS
sudo expressvpn-dns-manager.sh disconnect

# Check current status and configure accordingly
sudo expressvpn-dns-manager.sh check

# Run in monitor mode (continuous monitoring)
sudo expressvpn-dns-manager.sh monitor
```

## How It Works

1. **Monitoring**: The service continuously monitors ExpressVPN connection status
2. **DNS Detection**: When ExpressVPN connects, it detects the VPN DNS server using multiple methods:
   - Current resolv.conf analysis
   - ExpressVPN backup files
   - Status output parsing
   - Common VPN DNS server testing
3. **Configuration**: Updates systemd-resolved configuration with VPN DNS
4. **Restoration**: When ExpressVPN disconnects, it either:
   - Restores original backed-up configuration, or
   - Finds and configures the fastest available DNS server

## Configuration Files

### systemd-resolved
- Main config: `/etc/systemd/resolved.conf`
- Backup: `/etc/systemd/resolved.conf.backup-original`

### Logs
- Service logs: `journalctl -u expressvpn-dns-manager`
- Script logs: `/var/log/expressvpn-dns-manager.log`

## Troubleshooting

### Service Not Starting
```bash
# Check service status
sudo systemctl status expressvpn-dns-manager

# Check logs for errors
sudo journalctl -u expressvpn-dns-manager -n 50
```

### DNS Not Working
```bash
# Test DNS manually
sudo expressvpn-dns-manager.sh test-dns

# Check current DNS configuration
systemctl status systemd-resolved
resolvectl status
```

### ExpressVPN Not Detected
```bash
# Verify ExpressVPN installation
expressvpn status

# Check if service can detect ExpressVPN
sudo expressvpn-dns-manager.sh check
```

### Restore Original Configuration
```bash
# Restore all original settings
sudo expressvpn-dns-manager.sh restore

# Or uninstall completely
sudo ./install.sh uninstall
```

## Uninstallation

```bash
sudo ./install.sh uninstall
```

This will:
- Stop and disable the service
- Remove installed files
- Optionally restore original systemd-resolved configuration

## Advanced Configuration

### Custom DNS Servers

Edit the script variables at the top of `expressvpn-dns-manager.sh`:

```bash
GOOGLE_DNS_V4="8.8.8.8 8.8.4.4"
CLOUDFLARE_DNS_V4="1.1.1.1 1.0.0.1"
```

### systemd-resolved Configuration

The manager modifies `/etc/systemd/resolved.conf` with these settings:
- **DNS**: VPN DNS server or fastest detected DNS
- **FallbackDNS**: Cloudflare and Google DNS servers
- **Domains**: `~.` for global DNS resolution
- **DNSSEC**: Disabled for VPN compatibility
- **Cache**: Enabled for performance

## Security Considerations

- The service runs as root (required for DNS configuration)
- Original configurations are backed up before modification
- DNS queries use secure methods when possible
- No sensitive data is logged

## Contributing

Feel free to submit issues, feature requests, or pull requests to improve this tool.

## License

This project is provided as-is for educational and personal use.

## Changelog

### Latest Version
- Simplified to systemd-resolved only (no systemd-networkd complexity)
- Added DNS speed testing functionality
- Improved ExpressVPN DNS detection with multiple methods
- Enhanced router DNS detection
- Added IPv6 DNS support
- Streamlined backup and restore mechanisms
- Added comprehensive logging and error handling
- Automatic ExpressVPN disconnection during install/uninstall
