#!/usr/bin/env bash
# Install and configure the Splunk Universal Forwarder on a Linux host/LXC.
#   Usage (as root):  install-uf.sh <role> [<role> ...]
#   Roles:  linux       systemd journal -> index linux (every host)
#           technitium  Technitium DNS query logs -> index dns
# On a Proxmox host, for an LXC:
#   pct exec <vmid> -- bash -c "curl -fsSL <raw URL of this file> | bash -s -- linux technitium"
# Design and data policy: docs/architecture/siem.md, ADR 0007.
set -euo pipefail

VER=10.4.4 BUILD=f0f12fcdcaa1
PKG="splunkforwarder-${VER}-${BUILD}-linux-amd64.deb"
URL="https://download.splunk.com/products/universalforwarder/releases/${VER}/linux/${PKG}"
SHA512=9823acebac8201dbe3f4c19d22b4d1fb4af6f1033b9a8a9f86d304ae4e2be7a09c6c003023da1fb571eec9fa9b3a0b7e9bff2171d1f9e6d4ba223212b209b1f3
INDEXER=10.12.30.20:9997
UF=/opt/splunkforwarder
ROLES=("$@")
[[ ${#ROLES[@]} -gt 0 ]] || { echo "usage: $0 <role>..." >&2; exit 2; }
[[ $EUID -eq 0 ]] || { echo "run as root" >&2; exit 1; }

log(){ echo "[install-uf] $*"; }

# 1. Package (verified)
if [[ ! -x $UF/bin/splunk ]]; then
  tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
  log "downloading $PKG"
  if command -v curl >/dev/null; then curl -fsSL -o "$tmp/$PKG" "$URL"; else wget -q -O "$tmp/$PKG" "$URL"; fi
  echo "$SHA512  $tmp/$PKG" | sha512sum -c - >/dev/null || { echo "CHECKSUM MISMATCH, aborting" >&2; exit 1; }
  log "checksum OK, installing"
  DEBIAN_FRONTEND=noninteractive dpkg -i "$tmp/$PKG" >/dev/null
fi
USER_UF=$(stat -c %U $UF/bin/splunk)   # splunkfwd on recent packages

# 2. Local admin (random, root-only) + management port on localhost only
umask 077
if [[ ! -f /root/splunkfwd-admin.pass ]]; then
  openssl rand -base64 24 | tr -d '=+/' | cut -c1-24 > /root/splunkfwd-admin.pass
  printf '[user_info]\nUSERNAME = admin\nPASSWORD = %s\n' "$(cat /root/splunkfwd-admin.pass)" > $UF/etc/system/local/user-seed.conf
fi
printf '[settings]\nmgmtHostPort = 127.0.0.1:8089\n' > $UF/etc/system/local/web.conf

# 3. App: output + per-role inputs
APP=$UF/etc/apps/homelab_uf/local
mkdir -p "$APP"
printf '[tcpout]\ndefaultGroup = splunk\n\n[tcpout:splunk]\nserver = %s\n' "$INDEXER" > "$APP/outputs.conf"
: > "$APP/inputs.conf"
for role in "${ROLES[@]}"; do
  case $role in
    linux)
      cat >> "$APP/inputs.conf" <<'EOF'
[journald://journald]
index = linux
interval = 30
EOF
      getent group systemd-journal >/dev/null && usermod -aG systemd-journal "$USER_UF"
      ;;
    technitium)
      # Technitium writes query logs to <config dir>/logs when "Log All Queries" is on.
      DIR=""
      for d in /etc/dns/logs /opt/technitium/dns/logs /var/lib/technitium/dns/logs; do [[ -d $d ]] && DIR=$d && break; done
      [[ -n $DIR ]] || { echo "Technitium log folder not found. Enable query logging in the web UI first." >&2; exit 1; }
      cat >> "$APP/inputs.conf" <<EOF
[monitor://$DIR]
index = dns
sourcetype = technitium:query
whitelist = \\.log\$
EOF
      chgrp -R "$USER_UF" "$DIR" 2>/dev/null || true
      chmod -R g+rX "$DIR"
      log "technitium logs: $DIR"
      ;;
    *) echo "unknown role: $role" >&2; exit 2 ;;
  esac
done
chown -R "$USER_UF:$USER_UF" $UF/etc/apps/homelab_uf $UF/etc/system/local

# 4. Start + boot-start
$UF/bin/splunk stop >/dev/null 2>&1 || true
$UF/bin/splunk enable boot-start -user "$USER_UF" -systemd-managed 1 --accept-license --answer-yes --no-prompt >/dev/null 2>&1 || true
systemctl daemon-reload
systemctl restart SplunkForwarder
sleep 5
log "service: $(systemctl is-active SplunkForwarder) | roles: ${ROLES[*]} | indexer: $INDEXER"
