#!/usr/bin/env bash
# Standard admin access for a lab host, run from ops. Idempotent.
#
#   scripts/admin-access.sh <ssh-alias> [standard|node]
#
# 1. Creates `demarzo` with passwordless sudo and two keys: demarzo@ops
#    (primary, only from 10.12.5.10) and the admin desktop's key (backup).
# 2. Proves from ops that `demarzo` can log in and sudo. Stops here if not.
# 3. Only then hardens sshd with a drop-in: key-only logins, and
#      standard: no root login at all
#      node:     root only from the other cluster nodes (Proxmox needs it
#                for migrations, the web UI shell, and replication)
# 4. Proves `demarzo` still works and (standard) that root is refused.
#
# The first connection uses whatever ~/.ssh/config says for the alias (root,
# or a sudoer with passwordless sudo). If neither works yet, set ROOT_VIA to
# reach root through the Proxmox node instead, e.g. for LXC 301 on ragnar:
#   ROOT_VIA="ragnar pct exec 301 --" scripts/admin-access.sh bots
# Break-glass if something goes wrong: the Proxmox web UI shell
# (nodes), `pct enter <id>` (LXCs), or `qm guest exec <id>` (VMs).
set -euo pipefail

HOST=${1:?usage: $0 <ssh-alias> [standard|node]}
MODE=${2:-standard}
OPS_KEY='from="10.12.5.10" '"$(cat ~/.ssh/id_ed25519.pub)"
DESK_KEY='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOJtNrZFyiC2bd673PFPhR3E7K/zo2xjCsYGQaqYsH0H demarzo@demarzoDesk'
CLUSTER_NODES='10.12.5.11,10.12.5.12,10.12.5.13'
SSH=(ssh -T -o BatchMode=yes -o ConnectTimeout=5)

case "$MODE" in
  standard) ROOT_POLICY='PermitRootLogin no' ;;
  node)     ROOT_POLICY="PermitRootLogin no
Match Address $CLUSTER_NODES
    PermitRootLogin prohibit-password" ;;
  *) echo "mode must be standard or node" >&2; exit 2 ;;
esac

# Run a root script on the host, whether we log in as root or as a sudoer
as_root() {
  if [ -n "${ROOT_VIA:-}" ]; then
    read -r via_host via_cmd <<<"$ROOT_VIA"
    "${SSH[@]}" "$via_host" "if [ \"\$(id -u)\" = 0 ]; then $via_cmd bash -s; else sudo -n $via_cmd bash -s; fi"
  else
    "${SSH[@]}" "$HOST" 'if [ "$(id -u)" = 0 ]; then bash -s; else sudo -n bash -s; fi'
  fi
}

echo "==> [$HOST] 1/4 demarzo user, keys, sudo"
as_root <<EOF
set -e
command -v sudo >/dev/null || { export DEBIAN_FRONTEND=noninteractive; apt-get -qq update; apt-get -qq install -y sudo >/dev/null; }
id demarzo >/dev/null 2>&1 || useradd -m -s /bin/bash demarzo
usermod -aG sudo demarzo
install -d -m 700 -o demarzo -g demarzo /home/demarzo/.ssh
f=/home/demarzo/.ssh/authorized_keys; touch \$f
grep -q 'demarzo@ops\$' \$f || echo '$OPS_KEY' >> \$f
grep -q 'demarzo@demarzoDesk\$' \$f || echo '$DESK_KEY' >> \$f
for k in \$f /root/.ssh/authorized_keys; do if [ -f \$k ]; then sed -i '/ claude@10[.]12[.]30[.]101\$/d' \$k; fi; done
chown demarzo:demarzo \$f; chmod 600 \$f
echo 'demarzo ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/90-demarzo
chmod 440 /etc/sudoers.d/90-demarzo
visudo -cf /etc/sudoers.d/90-demarzo >/dev/null
EOF

echo "==> [$HOST] 2/4 verify demarzo login + sudo from ops"
"${SSH[@]}" "demarzo@$("${SSH[@]}" -G "$HOST" | awk '/^hostname /{print $2}')" 'sudo -n true && echo "   ok: $(whoami)@$(hostname), sudo works"'

echo "==> [$HOST] 3/4 sshd hardening ($MODE)"
as_root <<EOF
set -e
cat > /etc/ssh/sshd_config.d/05-admin-access.conf <<'CONF'
# Managed by enterprise-homelab scripts/admin-access.sh ($MODE)
# Sorts before other drop-ins so these values win (sshd keeps the first value it reads).
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
$ROOT_POLICY
CONF
install -d -m 755 /run/sshd   # sshd -t/-T need it; absent while socket-activated sshd is idle
sshd -t
# Restart, don't reload: on OpenSSH 10 (Debian 13) the reload's HUP + re-exec
# dies with "Cannot bind any address" and leaves sshd down. A restart keeps
# open sessions (KillMode=process). Socket-activated hosts just get a fresh
# listener on the next connection.
u=ssh; systemctl cat ssh.service >/dev/null 2>&1 || u=sshd
systemctl restart \$u.service || true
sleep 1
if ! systemctl is-active -q \$u.service && ! systemctl is-active -q ssh.socket; then
  systemctl start \$u.service
fi
systemctl is-active -q \$u.service || systemctl is-active -q ssh.socket || { echo "   FAIL: sshd not running" >&2; exit 1; }
install -d -m 755 /run/sshd; sshd -T | grep -Ei '^(permitrootlogin|passwordauthentication|kbdinteractiveauthentication) ' | sed 's/^/   /'
EOF

echo "==> [$HOST] 4/4 verify"
IP=$("${SSH[@]}" -G "$HOST" | awk '/^hostname /{print $2}')
"${SSH[@]}" "demarzo@$IP" 'sudo -n true && echo "   ok: demarzo + sudo still work"'
if [ "$MODE" = standard ]; then
  if "${SSH[@]}" "root@$IP" true 2>/dev/null; then echo "   FAIL: root login still accepted" >&2; exit 1
  else echo "   ok: root login refused"; fi
fi
# Point the alias at demarzo from now on (no-op if it already is)
python3 - "$HOST" <<'PY'
import re, sys, pathlib
p = pathlib.Path.home() / ".ssh/config"; s = p.read_text()
s2 = re.sub(r"(?m)^(Host %s\n(?:[ \t]+.*\n)*?[ \t]+User )root$" % re.escape(sys.argv[1]), r"\1demarzo", s)
if s2 != s: p.write_text(s2); print("   ~/.ssh/config: %s now logs in as demarzo" % sys.argv[1])
PY
echo "==> [$HOST] done"
