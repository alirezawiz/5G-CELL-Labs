#!/usr/bin/env bash
#
# create-vagrant-nat.sh
#
# Creates (or recreates) the "vagrant-nat" libvirt NAT network used by
# the Vagrantfile (private_network with libvirt__network_name: "vagrant-nat").
#
# - Gateway (host):  192.168.50.1
# - DHCP range:      192.168.50.100 - 192.168.50.199
# - Static IPs safe: anything outside the DHCP range (e.g. 192.168.50.10)
#
# Usage:
#   chmod +x create-vagrant-nat.sh
#   ./create-vagrant-nat.sh            # create if missing, replace if exists
#   ./create-vagrant-nat.sh --keep     # create only if missing, never replace

set -euo pipefail

NET_NAME="vagrant-nat"
NET_XML="/tmp/${NET_NAME}.xml"
BRIDGE_NAME="virbr50"
GATEWAY_IP="192.168.50.1"
NETMASK="255.255.255.0"
DHCP_START="192.168.50.100"
DHCP_END="192.168.50.199"
KEEP_EXISTING="no"

[[ "${1:-}" == "--keep" ]] && KEEP_EXISTING="yes"

info() { echo -e "\e[1;34m[INFO]\e[0m  $*"; }
ok()   { echo -e "\e[1;32m[ OK ]\e[0m  $*"; }
warn() { echo -e "\e[1;33m[WARN]\e[0m  $*"; }

# Always talk to the system libvirt instance (same one Vagrant uses)
VIRSH="virsh --connect qemu:///system"

# ---------------------------------------------------------------------------
# 1. Handle an existing network
# ---------------------------------------------------------------------------
if $VIRSH net-info "$NET_NAME" >/dev/null 2>&1; then
    if [[ "$KEEP_EXISTING" == "yes" ]]; then
        ok "Network '$NET_NAME' already exists - keeping it (--keep)."
        $VIRSH net-autostart "$NET_NAME" >/dev/null 2>&1 || true
        $VIRSH net-list --all
        exit 0
    fi
    warn "Network '$NET_NAME' already exists - removing it first..."
    # Stop it if active (net-destroy = power off, does not delete config)
    if $VIRSH net-info "$NET_NAME" | grep -q "Active:.*yes"; then
        $VIRSH net-destroy "$NET_NAME"
        ok "Stopped '$NET_NAME'."
    fi
    # Delete the definition
    $VIRSH net-undefine "$NET_NAME"
    ok "Undefined '$NET_NAME'."
fi

# ---------------------------------------------------------------------------
# 2. Write the network XML
# ---------------------------------------------------------------------------
info "Writing network definition to $NET_XML..."
cat > "$NET_XML" <<XML
<network>
<name>${NET_NAME}</name>
<forward mode='nat'/>
<bridge name='${BRIDGE_NAME}' stp='on' delay='0'/>
<ip address='${GATEWAY_IP}' netmask='${NETMASK}'>
<dhcp>
<range start='${DHCP_START}' end='${DHCP_END}'/>
</dhcp>
</ip>
</network>
XML
ok "XML written."

# ---------------------------------------------------------------------------
# 3. Define, start, autostart
# ---------------------------------------------------------------------------
info "Defining network '$NET_NAME'..."
$VIRSH net-define "$NET_XML"

info "Starting network '$NET_NAME'..."
$VIRSH net-start "$NET_NAME"

info "Enabling autostart for '$NET_NAME'..."
$VIRSH net-autostart "$NET_NAME"

# ---------------------------------------------------------------------------
# 4. Verify
# ---------------------------------------------------------------------------
echo
ok "Network '$NET_NAME' is ready:"
$VIRSH net-list --all
echo
echo "  Gateway:     ${GATEWAY_IP}"
echo "  DHCP range:  ${DHCP_START} - ${DHCP_END}"
echo "  Static IPs:  use addresses outside the DHCP range (e.g. 192.168.50.10)"
echo
echo "  Vagrantfile snippet:"
echo '    config.vm.network "private_network",'
echo '      ip: "192.168.50.10",'
echo "      libvirt__network_name: \"${NET_NAME}\""