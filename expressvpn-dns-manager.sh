#!/bin/bash

# ExpressVPN DNS Manager - Automatic DNS switching for systemd-resolved
# This script automatically configures DNS when ExpressVPN connects/disconnects
# Optimized for vanilla Arch Linux

RESOLVED_CONF="/etc/systemd/resolved.conf"
BACKUP_CONF="/etc/systemd/resolved.conf.backup-original"
LOG_FILE="/var/log/expressvpn-dns-manager.log"

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

EXPRESSVPN_CMD=$(detect_expressvpn_command)

# DNS servers for testing and fallback
GOOGLE_DNS_V4="8.8.8.8 8.8.4.4"
GOOGLE_DNS_V6="2001:4860:4860::8888 2001:4860:4860::8844"
CLOUDFLARE_DNS_V4="1.1.1.1 1.0.0.1"
CLOUDFLARE_DNS_V6="2606:4700:4700::1111 2606:4700:4700::1001"

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Test DNS server speed by measuring query time
test_dns_speed() {
    local dns_server="$1"
    local test_domain="${2:-google.com}"
    local timeout="${3:-3}"
    
    if [[ -z "$dns_server" ]]; then
        echo "999999"
        return 1
    fi
    
    # Use dig to test DNS response time
    local start_time=$(date +%s%N)
    if timeout "$timeout" dig @"$dns_server" "$test_domain" +short &>/dev/null; then
        local end_time=$(date +%s%N)
        local duration_ns=$((end_time - start_time))
        local duration_ms=$((duration_ns / 1000000))
        echo "$duration_ms"
        return 0
    else
        echo "999999"
        return 1
    fi
}

# Get router/gateway DNS server
get_router_dns() {
    # Try to get DNS from DHCP lease files or current resolv.conf
    local router_dns=""
    
    # Method 1: Check current resolv.conf for router IP
    local gateway=$(ip route | grep default | awk '{print $3}' | head -1)
    if [[ -n "$gateway" ]]; then
        # Test if gateway responds to DNS queries
        if test_dns_speed "$gateway" "google.com" 2 >/dev/null | grep -qv "999999"; then
            router_dns="$gateway"
        fi
    fi
    
    # Method 2: Check DHCP lease files for DNS servers
    if [[ -z "$router_dns" ]]; then
        for lease_file in /var/lib/dhcp/dhclient.*.leases /var/lib/dhcpcd5/dhcpcd.leases; do
            if [[ -f "$lease_file" ]]; then
                router_dns=$(grep -E "domain-name-servers|name_servers" "$lease_file" | tail -1 | sed -E 's/.*[=:] *([0-9.]+).*/\1/')
                if [[ -n "$router_dns" ]]; then
                    break
                fi
            fi
        done
    fi
    
    echo "$router_dns"
}

# Find fastest DNS server from available options
find_fastest_dns() {
    local test_servers=""
    local router_dns=$(get_router_dns)
    
    # Add router DNS if available
    if [[ -n "$router_dns" ]]; then
        test_servers="$router_dns"
    fi
    
    # Add public DNS servers
    test_servers="$test_servers $GOOGLE_DNS_V4 $CLOUDFLARE_DNS_V4"
    
    local fastest_dns=""
    local fastest_time=999999
    
    log "Testing DNS server speeds..."
    
    for dns in $test_servers; do
        local speed=$(test_dns_speed "$dns" "google.com" 3)
        log "DNS $dns: ${speed}ms"
        
        if [[ "$speed" -lt "$fastest_time" ]]; then
            fastest_time="$speed"
            fastest_dns="$dns"
        fi
    done
    
    if [[ -n "$fastest_dns" ]]; then
        log "Fastest DNS server: $fastest_dns (${fastest_time}ms)"
        echo "$fastest_dns"
    else
        log "No responsive DNS servers found, using Cloudflare as fallback"
        echo "1.1.1.1"
    fi
}

# Backup original config if not exists
backup_original_config() {
    if [[ ! -f "$BACKUP_CONF" ]]; then
        cp "$RESOLVED_CONF" "$BACKUP_CONF"
        log "Backed up original systemd-resolved config"
    fi
}



# Get ExpressVPN DNS server from current connection
get_expressvpn_dns() {
    if ! $EXPRESSVPN_CMD status | grep -q "Connected"; then
        echo ""
        return 1
    fi
    
    local vpn_dns=""
    
    # Method 1: Check current resolv.conf for VPN DNS
    if [[ -f /etc/resolv.conf ]]; then
        vpn_dns=$(grep "nameserver" /etc/resolv.conf | grep -v "127.0.0.53" | head -1 | awk '{print $2}')
    fi
    
    # Method 2: Check ExpressVPN's backup resolv.conf
    if [[ -z "$vpn_dns" && -f /etc/resolv.conf.___expressvpn-orig ]]; then
        vpn_dns=$(grep "nameserver" /etc/resolv.conf | grep -v "127.0.0.53" | head -1 | awk '{print $2}')
    fi
    
    # Method 3: Try to extract from ExpressVPN status output
    if [[ -z "$vpn_dns" ]]; then
        local status_output=$($EXPRESSVPN_CMD status 2>/dev/null)
        # Look for IP patterns that might be DNS servers
        vpn_dns=$(echo "$status_output" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | grep -E '^(10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.|100\.64\.)' | head -1)
    fi
    
    # Method 4: Common ExpressVPN DNS servers as fallback
    if [[ -z "$vpn_dns" ]]; then
        # These are commonly used by ExpressVPN
        local common_vpn_dns="100.64.100.1 10.0.0.1 172.16.0.1"
        for dns in $common_vpn_dns; do
            if test_dns_speed "$dns" "google.com" 2 >/dev/null | grep -qv "999999"; then
                vpn_dns="$dns"
                break
            fi
        done
    fi
    
    # Final fallback
    if [[ -z "$vpn_dns" ]]; then
        vpn_dns="100.64.100.1"
    fi
    
    echo "$vpn_dns"
}

# Configure DNS for VPN connection
configure_vpn_dns() {
    local vpn_dns=$(get_expressvpn_dns)
    
    if [[ -n "$vpn_dns" ]]; then
        log "Configuring DNS for ExpressVPN connection (DNS: $vpn_dns)"
        
        # Configure systemd-resolved only
        cat > "$RESOLVED_CONF" << EOF
[Resolve]
DNS=$vpn_dns
FallbackDNS=$CLOUDFLARE_DNS_V4 $GOOGLE_DNS_V4
Domains=~.
DNSSEC=no
DNSOverTLS=no
Cache=yes
DNSStubListener=yes
EOF
        
        # Restart systemd-resolved
        systemctl restart systemd-resolved
        
        log "DNS configured for ExpressVPN (Primary: $vpn_dns)"
        return 0
    else
        log "ERROR: Could not determine ExpressVPN DNS server"
        return 1
    fi
}

# Restore original DNS configuration
restore_original_dns() {
    log "Restoring original DNS configuration"
    
    if [[ -f "$BACKUP_CONF" ]]; then
        cp "$BACKUP_CONF" "$RESOLVED_CONF"
        log "Original systemd-resolved config restored"
    else
        log "Original backup config not found, finding optimal DNS..."
        local fastest_dns=$(find_fastest_dns)
        
        cat > "$RESOLVED_CONF" << EOF
[Resolve]
DNS=$fastest_dns
FallbackDNS=$CLOUDFLARE_DNS_V4 $GOOGLE_DNS_V4
#Domains=
DNSSEC=no
DNSOverTLS=no
Cache=yes
DNSStubListener=yes
EOF
        log "Configured with fastest DNS: $fastest_dns"
    fi
    
    systemctl restart systemd-resolved
    log "DNS configuration restoration completed"
}

# Check ExpressVPN status and configure DNS accordingly
check_and_configure() {
    if $EXPRESSVPN_CMD status | grep -q "Connected"; then
        log "ExpressVPN is connected"
        configure_vpn_dns
    else
        log "ExpressVPN is disconnected"
        restore_original_dns
    fi
}

# Monitor ExpressVPN status continuously
monitor_expressvpn() {
    local previous_status=""

    log "Starting ExpressVPN DNS monitoring (using: $EXPRESSVPN_CMD)"

    while true; do
        local current_status
        if $EXPRESSVPN_CMD status | grep -q "Connected"; then
            current_status="connected"
        else
            current_status="disconnected"
        fi

        # Only act on status changes
        if [[ "$current_status" != "$previous_status" ]]; then
            log "ExpressVPN status changed: $previous_status -> $current_status"
            check_and_configure
            previous_status="$current_status"
        fi

        sleep 5
    done
}

# Test and display DNS speeds
test_all_dns() {
    log "Testing DNS server speeds..."
    echo "Testing DNS server response times:"
    echo "=================================="
    
    local router_dns=$(get_router_dns)
    if [[ -n "$router_dns" ]]; then
        local speed=$(test_dns_speed "$router_dns")
        printf "Router DNS (%s): %sms\n" "$router_dns" "$speed"
    fi
    
    for dns in $GOOGLE_DNS_V4; do
        local speed=$(test_dns_speed "$dns")
        printf "Google DNS (%s): %sms\n" "$dns" "$speed"
    done
    
    for dns in $CLOUDFLARE_DNS_V4; do
        local speed=$(test_dns_speed "$dns")
        printf "Cloudflare DNS (%s): %sms\n" "$dns" "$speed"
    done
    
    echo "=================================="
    local fastest=$(find_fastest_dns)
    echo "Fastest DNS server: $fastest"
}

# Main script logic
case "${1:-monitor}" in
    "connect")
        backup_original_config
        configure_vpn_dns
        ;;
    "disconnect")
        restore_original_dns
        ;;
    "monitor")
        backup_original_config
        monitor_expressvpn
        ;;
    "check")
        check_and_configure
        ;;
    "restore")
        restore_original_dns
        ;;
    "test-dns")
        test_all_dns
        ;;
    "find-fastest")
        find_fastest_dns
        ;;
    *)
        echo "Usage: $0 {connect|disconnect|monitor|check|restore|test-dns|find-fastest}"
        echo "  connect      - Configure DNS for VPN connection"
        echo "  disconnect   - Restore original DNS"
        echo "  monitor      - Continuously monitor and auto-configure (default)"
        echo "  check        - Check current status and configure accordingly"
        echo "  restore      - Restore original DNS configuration"
        echo "  test-dns     - Test and display DNS server speeds"
        echo "  find-fastest - Find and display fastest DNS server"
        exit 1
        ;;
esac
