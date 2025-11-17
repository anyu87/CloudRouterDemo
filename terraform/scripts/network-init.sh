#!/bin/bash
set -e

log() { 
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a /var/log/network-config.log
}

log "Starting network configuration..."

# Validate required commands exist
for cmd in ip netplan systemctl; do
    if ! command -v "$cmd" &> /dev/null; then
        log "ERROR: Required command '$cmd' is not available"
        exit 1
    fi
done

# Validate directories exist
if [ ! -d "/etc/netplan" ]; then
    log "ERROR: /etc/netplan directory does not exist"
    exit 1
fi

if [ ! -d "/sys/class/net" ]; then
    log "ERROR: /sys/class/net directory does not exist"
    exit 1
fi

# Enhanced function to check if IP is in private subnet (RFC 1918)
is_private_ip() {
    local ip="$1"
    local clean_ip=$(echo "$ip" | cut -d'/' -f1)  # Remove subnet mask if present
    
    # Check RFC 1918 private ranges:
    # 10.0.0.0/8 (10.0.0.0 - 10.255.255.255)
    # 172.16.0.0/12 (172.16.0.0 - 172.31.255.255) 
    # 192.168.0.0/16 (192.168.0.0 - 192.168.255.255)
    
    if [[ $clean_ip =~ ^10\. ]]; then
        return 0  # 10.0.0.0/8
    elif [[ $clean_ip =~ ^172\.(1[6-9]|2[0-9]|3[0-1])\. ]]; then
        return 0  # 172.16.0.0/12
    elif [[ $clean_ip =~ ^192\.168\. ]]; then
        return 0  # 192.168.0.0/16
    else
        return 1  # Is public IP
    fi
}

# Function to convert CIDR to netmask
cidr_to_netmask() {
    local cidr="$1"
    
    # Input validation
    if [[ ! $cidr =~ ^[0-9]+$ ]] || [ "$cidr" -lt 0 ] || [ "$cidr" -gt 32 ]; then
        echo "Error: CIDR must be a number between 0 and 32" >&2
        return 1
    fi
    
    local netmask=""
    local full_octets=$((cidr / 8))
    local remaining_bits=$((cidr % 8))
    local partial_octet=0
    
    # Calculate partial octet if there are remaining bits
    if [ "$remaining_bits" -gt 0 ]; then
        partial_octet=$((256 - (256 >> remaining_bits)))
    fi
    
    for ((i=0; i<4; i++)); do
        if [ "$i" -lt "$full_octets" ]; then
            netmask="${netmask}255"
        elif [ "$i" -eq "$full_octets" ] && [ "$remaining_bits" -gt 0 ]; then
            netmask="${netmask}${partial_octet}"
        else
            netmask="${netmask}0"
        fi
        
        if [ "$i" -lt 3 ]; then
            netmask="${netmask}."
        fi
    done
    
    echo "$netmask"
}

# Function to convert netmask to CIDR
netmask_to_cidr() {
    local netmask="$1"
    local cidr=0
    
    # Use -a for array, not -o
    IFS='.' read -ra octets <<< "$netmask"
    
    for octet in "${octets[@]}"; do
        case $octet in
            255) cidr=$((cidr + 8)) ;;
            254) cidr=$((cidr + 7)) ;;
            252) cidr=$((cidr + 6)) ;;
            248) cidr=$((cidr + 5)) ;;
            240) cidr=$((cidr + 4)) ;;
            224) cidr=$((cidr + 3)) ;;
            192) cidr=$((cidr + 2)) ;;
            128) cidr=$((cidr + 1)) ;;
            0)   ;;
            *)   echo "32"; return 1 ;;  # Invalid netmask, default to /32
        esac
    done
    
    echo "$cidr"
}

# Function to extract IP, netmask, and CIDR from CIDR notation
get_ip_netmask_cidr() {
    local cidr_ip="$1"
    local ip=$(echo "$cidr_ip" | cut -d'/' -f1)
    local cidr_part=$(echo "$cidr_ip" | cut -d'/' -f2)
    local netmask=""
    local cidr=""
    
    if [[ $cidr_part =~ ^[0-9]{1,2}$ ]]; then
        # CIDR notation (e.g., /24)
        cidr="$cidr_part"
        netmask=$(cidr_to_netmask "$cidr")
    elif [[ $cidr_part =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        # Already in netmask format
        netmask="$cidr_part"
        cidr=$(netmask_to_cidr "$netmask")
    else
        # Default to /32 if no valid netmask found
        cidr="32"
        netmask="255.255.255.255"
    fi
    
    echo "$ip,$netmask,$cidr"
}

# Function to extract the first private IPv4 address, netmask, and CIDR from an interface
get_private_ip_netmask_cidr() {
    local interface="$1"
    local ip_addrs=$(ip addr show "$interface" 2>/dev/null | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}')
    
    if [ -n "$ip_addrs" ]; then
        while IFS= read -r ip; do
            if [ -n "$ip" ] && is_private_ip "$ip"; then
                # Return IP, netmask, and CIDR
                get_ip_netmask_cidr "$ip"
                return 0
            fi
        done <<< "$ip_addrs"
    fi
    return 1
}

# Function to extract the first public IPv4 address, netmask, and CIDR from an interface
get_public_ip_netmask_cidr() {
    local interface="$1"
    local ip_addrs=$(ip addr show "$interface" 2>/dev/null | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}')
    
    if [ -n "$ip_addrs" ]; then
        while IFS= read -r ip; do
            if [ -n "$ip" ] && ! is_private_ip "$ip"; then
                # Return IP, netmask, and CIDR
                get_ip_netmask_cidr "$ip"
                return 0
            fi
        done <<< "$ip_addrs"
    fi
    return 1
}

# Function to get default gateway for an interface
get_interface_gateway() {
    local interface="$1"
    
    # Try to get gateway from route table for the specific interface
    local gateway=$(ip route show dev "$interface" 2>/dev/null | grep '^default via' | awk '{print $3}' | head -n1)
    
    if [ -n "$gateway" ]; then
        echo "$gateway"
        return 0
    fi
    
    # Fallback: get default gateway from main route table
    gateway=$(ip route show 2>/dev/null | grep '^default via' | awk '{print $3}' | head -n1)
    
    if [ -n "$gateway" ]; then
        echo "$gateway"
        return 0
    fi
    
    return 1
}

# Enhanced function to check if interface has private IP
has_private_ip() {
    local interface="$1"
    local ip_addrs=$(ip addr show "$interface" 2>/dev/null | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}')
    
    if [ -n "$ip_addrs" ]; then
        while IFS= read -r ip; do
            if [ -n "$ip" ] && is_private_ip "$ip"; then
                return 0  # Has at least one private IP
            fi
        done <<< "$ip_addrs"
    fi
    return 1  # No private IP
}

# Identify LAN and WAN interfaces with enhanced logic
LAN_IFACE=""
LAN_MAC=""
LAN_IFACE_IPv4=""
LAN_NETMASK=""
LAN_CIDR=""
WAN_IFACE=""
WAN_MAC=""
WAN_IFACE_IPv4=""
WAN_NETMASK=""
WAN_CIDR=""
WAN_GW_IPv4=""

# First pass: Look for interfaces with private IPs (LAN candidates)
for iface in $(ls /sys/class/net/ | grep -v lo); do
    if has_private_ip "$iface"; then
        if [ -z "$LAN_IFACE" ]; then
            LAN_IFACE="$iface"
            LAN_MAC=$(cat "/sys/class/net/$iface/address" 2>/dev/null)
            
            # Get IP, netmask, and CIDR
            lan_ip_netmask_cidr=$(get_private_ip_netmask_cidr "$iface")
            if [ -n "$lan_ip_netmask_cidr" ]; then
                LAN_IFACE_IPv4=$(echo "$lan_ip_netmask_cidr" | cut -d',' -f1)
                LAN_NETMASK=$(echo "$lan_ip_netmask_cidr" | cut -d',' -f2)
                LAN_CIDR=$(echo "$lan_ip_netmask_cidr" | cut -d',' -f3)
            fi
            
            log "Identified LAN interface: $iface (MAC: $LAN_MAC) with private IP: $LAN_IFACE_IPv4, Netmask: $LAN_NETMASK, CIDR: /$LAN_CIDR"
        else
            log "Multiple LAN interface candidates found: $LAN_IFACE and $iface"
        fi
    fi
done

# Second pass: Look for WAN interface
for iface in $(ls /sys/class/net/ | grep -v lo); do
    # Skip if this is already identified as LAN
    [ "$iface" = "$LAN_IFACE" ] && continue
    
    ip_addrs=$(ip addr show "$iface" 2>/dev/null | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}')
    
    if [ -n "$ip_addrs" ]; then
        # Check if interface has public IPs
        has_public="false"
        while IFS= read -r ip; do
            if [ -n "$ip" ] && ! is_private_ip "$ip"; then
                has_public="true"
                break
            fi
        done <<< "$ip_addrs"
        
        if [ "$has_public" = "true" ]; then
            WAN_IFACE="$iface"
            WAN_MAC=$(cat "/sys/class/net/$iface/address" 2>/dev/null)
            
            # Get both IP, netmask, and CIDR for WAN
            wan_ip_netmask_cidr=$(get_public_ip_netmask_cidr "$iface")
            if [ -n "$wan_ip_netmask_cidr" ]; then
                WAN_IFACE_IPv4=$(echo "$wan_ip_netmask_cidr" | cut -d',' -f1)
                WAN_NETMASK=$(echo "$wan_ip_netmask_cidr" | cut -d',' -f2)
                WAN_CIDR=$(echo "$wan_ip_netmask_cidr" | cut -d',' -f3)
            fi
            
            WAN_GW_IPv4=$(get_interface_gateway "$iface")
            log "Identified WAN interface: $iface (MAC: $WAN_MAC) with public IP: $WAN_IFACE_IPv4, Netmask: $WAN_NETMASK, CIDR: /$WAN_CIDR, Gateway: $WAN_GW_IPv4"
            break
        fi
    else
        # Interface with no IP - potential WAN candidate
        if [ -z "$WAN_IFACE" ]; then
            WAN_IFACE="$iface"
            WAN_MAC=$(cat "/sys/class/net/$iface/address" 2>/dev/null)
            WAN_GW_IPv4=$(get_interface_gateway "$iface")
            log "Identified WAN interface candidate: $iface (MAC: $WAN_MAC) - no IP assigned, Gateway: $WAN_GW_IPv4"
        fi
    fi
done

# If no WAN found but we have LAN, pick first non-LAN interface
if [ -z "$WAN_IFACE" ] && [ -n "$LAN_IFACE" ]; then
    for iface in $(ls /sys/class/net/ | grep -v lo); do
        if [ "$iface" != "$LAN_IFACE" ]; then
            WAN_IFACE="$iface"
            WAN_MAC=$(cat "/sys/class/net/$iface/address" 2>/dev/null)
            WAN_GW_IPv4=$(get_interface_gateway "$iface")
            log "Assumed WAN interface: $iface (MAC: $WAN_MAC) - default selection, Gateway: $WAN_GW_IPv4"
            break
        fi
    done
fi

# Final assignment and logging
log "Final interface assignment:"
log "  LAN Interface: $LAN_IFACE (MAC: $LAN_MAC)"

if [ -n "$LAN_IFACE_IPv4" ]; then
    log "  LAN IPv4: $LAN_IFACE_IPv4"
    log "  LAN Netmask: $LAN_NETMASK"
    log "  LAN CIDR: /$LAN_CIDR"
else
    log "  LAN IPv4: Not assigned"
    LAN_IFACE_IPv4=""  # Ensure it's empty if no IP found
    LAN_NETMASK=""     # Ensure netmask is also empty
    LAN_CIDR=""        # Ensure CIDR is also empty
fi

if [ -n "$WAN_IFACE" ]; then
    # Only set WAN IP, Netmask, CIDR and Gateway if WAN interface is detected
    log "  WAN Interface: $WAN_IFACE (MAC: $WAN_MAC)"
    
    if [ -n "$WAN_IFACE_IPv4" ]; then
        log "  WAN IPv4: $WAN_IFACE_IPv4"
        log "  WAN Netmask: $WAN_NETMASK"
        log "  WAN CIDR: /$WAN_CIDR"
    else
        log "  WAN IPv4: Not assigned"
        log "  WAN Netmask: Not available"
        log "  WAN CIDR: Not available"
        WAN_IFACE_IPv4=""  # Ensure it's empty if no IP found
        WAN_NETMASK=""     # Ensure netmask is also empty
        WAN_CIDR=""        # Ensure CIDR is also empty
    fi
    
    if [ -n "$WAN_GW_IPv4" ]; then
        log "  WAN Gateway: $WAN_GW_IPv4"
    else
        log "  WAN Gateway: Not detected"
        WAN_GW_IPv4=""  # Ensure it's empty if no gateway found
    fi
else
    log "  WAN Interface: Not detected"
    # Ensure WAN-related variables are empty
    WAN_IFACE_IPv4=""
    WAN_NETMASK=""
    WAN_CIDR=""
    WAN_GW_IPv4=""
fi

# Validate that we have the required information before proceeding
if [ -z "$WAN_MAC" ] || [ -z "$WAN_IFACE_IPv4" ] || [ -z "$WAN_CIDR" ] || [ -z "$WAN_GW_IPv4" ] || [ -z "$LAN_MAC" ] || [ -z "$LAN_IFACE_IPv4" ] || [ -z "$LAN_CIDR" ]; then
    log "ERROR: Required network information is missing. Cannot proceed with network configuration."
    log "Missing information:"
    [ -z "$WAN_MAC" ] && log "  - WAN MAC address"
    [ -z "$WAN_IFACE_IPv4" ] && log "  - WAN IP address"
    [ -z "$WAN_CIDR" ] && log "  - WAN CIDR"
    [ -z "$WAN_GW_IPv4" ] && log "  - WAN Gateway"
    [ -z "$LAN_MAC" ] && log "  - LAN MAC address"
    [ -z "$LAN_IFACE_IPv4" ] && log "  - LAN IP address"
    [ -z "$LAN_CIDR" ] && log "  - LAN CIDR"
    exit 1
fi

# Create backup of existing netplan config if it exists
if [ -f "/etc/netplan/50-cloud-init.yaml" ]; then
    cp "/etc/netplan/50-cloud-init.yaml" "/etc/netplan/50-cloud-init.yaml.backup.$(date +%s)"
    log "Backed up existing netplan configuration"
fi

# Disabling Cloud-Init
log "Disabling Cloud-Init for Networking..."

cat > /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg <<'EOF'
network: {config: disabled}
EOF

log "Creating network config file"

# Creating netplan config with proper validation
cat > /etc/netplan/50-cloud-init.yaml << EOF
network:
  version: 2
  ethernets:
    wan-iface:
      match:
        macaddress: "$WAN_MAC"
      set-name: eth0
      dhcp4: false
      addresses:
        - $WAN_IFACE_IPv4/$WAN_CIDR
      routes:
        - to: default
          via: $WAN_GW_IPv4
      nameservers:
        addresses: [8.8.8.8, 1.1.1.1]
    lan-iface:
      match:
        macaddress: "$LAN_MAC"
      set-name: eth1
      dhcp4: false
      addresses:
        - $LAN_IFACE_IPv4/$LAN_CIDR
EOF

log "Network config file has been created"

# Test the netplan configuration before applying
if netplan --debug generate; then
    log "Netplan configuration generated successfully"
    
    # Apply the configuration
    netplan apply
    systemctl restart systemd-networkd
    
    # Wait a moment for network to come up
    sleep 2
    
    # Test connectivity to gateway
    if ping -c 1 -W 5 "$WAN_GW_IPv4" >/dev/null 2>&1; then
        log "Network configuration applied successfully! Gateway is reachable."
        
        # Ask for confirmation before rebooting (optional safety measure)
        log "Network configuration applied. Rebooting in 10 seconds. Press Ctrl+C to cancel."
        sleep 10
        reboot
    else
        log "WARNING: Gateway is not reachable after configuration. Not rebooting to prevent lockout."
        log "Please check the network configuration manually."
        exit 1
    fi
else
    log "ERROR: Netplan configuration failed to generate. Rolling back changes."
    # Note: In a real scenario, you'd want to restore the backup here
    exit 1
fi