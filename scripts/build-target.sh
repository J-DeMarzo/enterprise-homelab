#!/usr/bin/env bash
# Build (or rebuild) a lab target on VLAN 40 from template 9001, run from ops.
#
#   scripts/build-target.sh <victim|web> <vmid> <name> [node]
#
#   victim  OpenSSH + auditd + UF (journald, auditd)          2 vCPU / 2 GiB / 16 GiB
#   web     victim + DVWA/MariaDB in Docker + UF (dvwa role)  2 vCPU / 4 GiB / 24 GiB
#
# Clones 9001 on sevro (the template's node), tags it VLAN 40, migrates it to
# <node> (default ragnar), verifies its SSH host key against the guest agent before
# trusting it, installs the forwarder roles, and takes the `Clean` snapshot.
# Prints the elapsed time. To rebuild an existing target, destroy it first:
#   ssh <node> 'sudo qm stop <vmid>; sudo qm destroy <vmid> --purge'
# Reserve the printed MAC in Omada afterwards to pin its IP. Runbook: docs/runbooks/rebuild-targets.md
set -euo pipefail

KIND=${1:?usage: $0 <victim|web> <vmid> <name> [node]}
VMID=${2:?vmid}; NAME=${3:?name}; NODE=${4:-ragnar}
HERE=$(cd "$(dirname "$0")/.." && pwd)
TEMPLATE_NODE=sevro
SSHO=(-o BatchMode=yes -o ConnectTimeout=5)
START=$SECONDS
log(){ echo "[build-target] $(printf '%3ds' $((SECONDS-START))) $*"; }

case $KIND in
  victim) MEM=2048 DISK=16G ROLES="linux auditd"
          ROLE_TXT="Deliberate Linux target for SSH and host-level attack emulation"
          SVC_TXT="OpenSSH, auditd (exec, identity and sudoers rules), Splunk UF (journald + auditd)" ;;
  web)    MEM=4096 DISK=24G ROLES="linux auditd dvwa"
          ROLE_TXT="Deliberately vulnerable web target (DVWA) for web attack emulation"
          SVC_TXT="DVWA + MariaDB in Docker (/opt/dvwa/compose.yml), port 80, default DVWA credentials. Apache log in /var/log/dvwa" ;;
  *) echo "kind must be victim or web" >&2; exit 2 ;;
esac

# 1. Clone on the template's node, configure, migrate, start.
log "cloning 9001 -> $VMID ($NAME)"
ssh "${SSHO[@]}" $TEMPLATE_NODE "sudo qm clone 9001 $VMID --name $NAME --full --storage fast-local >/dev/null &&
  sudo qm set $VMID --net0 virtio,bridge=vmbr0,firewall=1,tag=40 --memory $MEM --cores 2 --tags 'lab;net-lab' >/dev/null &&
  sudo qm resize $VMID scsi0 $DISK >/dev/null"
if [[ $NODE != $TEMPLATE_NODE ]]; then
  log "migrating to $NODE"
  ssh "${SSHO[@]}" $TEMPLATE_NODE "sudo qm migrate $VMID $NODE" >/dev/null
fi
ssh "${SSHO[@]}" $NODE "sudo qm start $VMID" >/dev/null

# 2. Wait for the guest agent to report a VLAN 40 address.
log "waiting for an address"
IP=""
for _ in $(seq 60); do
  IP=$(ssh "${SSHO[@]}" $NODE "sudo qm agent $VMID network-get-interfaces 2>/dev/null" |
       grep -o '"ip-address" : "10\.12\.40\.[0-9]*"' | grep -o '10\.12\.40\.[0-9]*' | head -1 || true)
  [[ -n $IP ]] && break; sleep 3
done
[[ -n $IP ]] || { echo "no VLAN 40 address after 3 min" >&2; exit 1; }
MAC=$(ssh "${SSHO[@]}" $NODE "sudo qm config $VMID" | grep -o 'virtio=[0-9A-F:]*' | cut -d= -f2)
log "up at $IP ($MAC)"

# 3. Trust the SSH host key only if it matches what the guest agent reports.
ssh-keygen -R "$IP" >/dev/null 2>&1 || true
for _ in $(seq 20); do
  GUEST_FP=$(ssh "${SSHO[@]}" $NODE "sudo qm guest exec $VMID -- ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub" 2>/dev/null |
             grep -o 'SHA256:[A-Za-z0-9+/]*' | head -1 || true)
  [[ -n $GUEST_FP ]] && break; sleep 3
done
KEY=$(ssh-keyscan -t ed25519 "$IP" 2>/dev/null)
SCAN_FP=$(ssh-keygen -lf <(echo "$KEY") | grep -o 'SHA256:[A-Za-z0-9+/]*')
[[ -n $GUEST_FP && $GUEST_FP == "$SCAN_FP" ]] || { echo "host key mismatch: guest=$GUEST_FP scan=$SCAN_FP" >&2; exit 1; }
echo "$KEY" >> ~/.ssh/known_hosts
log "host key verified ($GUEST_FP)"

# 4. Provision. cloud-init must finish first (it holds the apt lock on first boot).
RSSH=(ssh "${SSHO[@]}" "$IP")
"${RSSH[@]}" 'cloud-init status --wait >/dev/null; sudo systemctl is-active qemu-guest-agent >/dev/null'
if [[ $KIND == web ]]; then
  log "installing Docker and starting DVWA"
  "${RSSH[@]}" 'sudo apt-get -o DPkg::Lock::Timeout=120 install -y docker.io docker-compose-v2 >/dev/null 2>&1; sudo mkdir -p /opt/dvwa /var/log/dvwa'
  "${RSSH[@]}" 'sudo tee /opt/dvwa/compose.yml >/dev/null' < "$HERE/scripts/targets/dvwa-compose.yml"
  "${RSSH[@]}" 'cd /opt/dvwa && sudo docker compose up -d >/dev/null 2>&1; for i in $(seq 30); do [ -s /var/log/dvwa/access.log ] || curl -s -o /dev/null http://127.0.0.1/login.php; [ -s /var/log/dvwa/access.log ] && break; sleep 2; done'
fi
log "installing forwarder roles: $ROLES"
"${RSSH[@]}" "f=\$(mktemp); cat >\"\$f\"; sudo bash \"\$f\" $ROLES; rm -f \"\$f\"" < "$HERE/splunk/forwarder/install-uf.sh" | tail -1

# 5. Notes card and baseline snapshot.
DESC="### $NAME · ${ROLE_TXT%% for *}

| | |
|---|---|
| **Role** | $ROLE_TXT |
| **Service** | $SVC_TXT |
| **Network** | VLAN 40 (Security lab) · DHCP |
| **Scope** | Attack from kali only. Intentionally weak: never move it out of VLAN 40 |
| **Reset** | Roll back to snapshot \`Clean\`, or rebuild with scripts/build-target.sh |
| **Golden image** | ubuntu-2404-ci (VMID 9001) |
| **Owner** | demarzo |

Docs: https://github.com/J-DeMarzo/enterprise-homelab/blob/main/docs/runbooks/rebuild-targets.md"
ssh "${SSHO[@]}" $NODE "sudo qm set $VMID --description $(printf %q "$DESC")" >/dev/null
ssh "${SSHO[@]}" $NODE "sudo qm snapshot $VMID Clean --description 'Baseline: built by build-target.sh'" >/dev/null
log "done: $NAME ($VMID) on $NODE at $IP, MAC $MAC"
