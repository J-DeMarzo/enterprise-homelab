#!/usr/bin/env bash
# Host firewall for splunk (10.12.30.20). Splunk Free has no authentication, so
# this is the access control for the web UI. Run as root. Idempotent.
set -euo pipefail

MGMT=10.12.5.0/24
SERVERS=10.12.30.0/24
SECURITY=10.12.40.0/24
DMZ=10.12.50.0/24
ADMIN_DESKTOP=10.12.10.10     # IP group "Admin Terminals" in Omada
GATEWAY_SERVERS_IF=10.12.30.1 # gateway may source syslog from its Servers-VLAN interface

ufw --force reset >/dev/null
ufw default deny incoming
ufw default allow outgoing

# SSH: Management (ops) and the admin desktop. Servers lost SSH on 2026-10-01
# when the agent workstation moved from claude (Servers) to ops (ADR 0008)
ufw allow from "$MGMT"          to any port 22 proto tcp comment 'ssh mgmt'
ufw allow from "$ADMIN_DESKTOP" to any port 22 proto tcp comment 'ssh admin desktop'

# Web UI: Management + admin desktop only
ufw allow from "$MGMT"          to any port 8000 proto tcp comment 'splunk web mgmt'
ufw allow from "$ADMIN_DESKTOP" to any port 8000 proto tcp comment 'splunk web admin desktop'

# Forwarders
for net in "$MGMT" "$SERVERS" "$SECURITY" "$DMZ"; do
  ufw allow from "$net" to any port 9997 proto tcp comment 'splunk forwarders'
done

# Syslog: gateway/controller/Proxmox (Management) + gateway's Servers interface
for src in "$MGMT" "$GATEWAY_SERVERS_IF"; do
  ufw allow from "$src" to any port 514 comment 'syslog'
done

# 8089 (splunkd management) is intentionally NOT opened: local CLI only.
ufw --force enable
ufw status numbered
