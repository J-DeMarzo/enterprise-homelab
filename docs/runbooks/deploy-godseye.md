# Runbook: Deploy God's Eye View (`godseye`)

**Result:** LXC 202 `godseye` (sevro, 10.12.30.51, `godseye.demarzo.lab`) running [God's Eye View](https://github.com/bilawalsidhu/gods-eye-view) v0.3.0 keyless. It's a live 3D globe of public data: flights, satellites, quakes, weather, traffic cameras. The UI is at http://godseye.demarzo.lab:4173, reachable from Management and Internal only. Last done: 2026-10-28.

Upstream calls it "not a hardened production service": it's a Vite dev server plus a proxy that brokers any provider API keys. **Keep it internal.** Never publish it through dmz-edge.

## 1. Container (from ops)
- Template `Templates:vztmpl/debian-13-standard_13.6-1_amd64.tar.zst`, unprivileged, `nesting=1`, `onboot=1`.
- 2 cores, 3072 MiB RAM, 512 MiB swap, 16 GB on `fast-local`. The server side is light; the WebGL rendering happens in the viewer's browser. The disk holds `node_modules` and the `.gev-cache/` download cache.
- `pct create` sets the VLAN, DNS and tags in one go (sevro's sudo umask is 0022, so a shell create is fine there):
  ```bash
  ssh -n sevro 'sudo pct create 202 Templates:vztmpl/debian-13-standard_13.6-1_amd64.tar.zst --hostname godseye \
    --unprivileged 1 --features nesting=1 --cores 2 --memory 3072 --swap 512 --rootfs fast-local:16 \
    --net0 name=eth0,bridge=vmbr0,firewall=1,gw=10.12.30.1,ip=10.12.30.51/24,tag=30,type=veth \
    --nameserver "10.12.5.53 10.12.5.54" --searchdomain demarzo.lab --tags "app;net-svc" --onboot 1'
  ```
- Start it through the API ([why](../architecture/compute.md#renumbering-a-guest)).

## 2. Admin access and DNS
```bash
# ~/.ssh/config on ops:  Host godseye / HostName 10.12.30.51 / User demarzo
ssh -n sevro 'sudo pct exec 202 -- ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub'   # compare, then pin
ssh-keyscan -t ed25519 10.12.30.51 >> ~/.ssh/known_hosts
ROOT_VIA="sevro sudo pct exec 202 --" scripts/admin-access.sh godseye
```
DNS: `godseye` A 10.12.30.51 with PTR ([add-dns-record](add-dns-record.md)). Snapshot `base`.

## 3. Node 24 and the app
The app wants Node `>=24.14 <25` or 26. Node comes from NodeSource's signed apt repo (not their `curl | bash` setup script):
```bash
apt-get update && apt-get -y full-upgrade && apt-get -y install curl ca-certificates gnupg git ufw locales
install -d -m755 /etc/apt/keyrings
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_24.x nodistro main" \
  > /etc/apt/sources.list.d/nodesource.list
apt-get update && apt-get -y install nodejs
```
The app runs as a system user `gev` with its home at `/opt/gods-eye-view`. **Pin a release tag, and read the code before `npm ci`.** Popular repos attract lookalike clones, so clone from `bilawalsidhu/gods-eye-view` only.
```bash
useradd -r -m -d /opt/gods-eye-view -s /usr/sbin/nologin gev
sudo -u gev git clone https://github.com/bilawalsidhu/gods-eye-view.git /opt/gods-eye-view/app
cd /opt/gods-eye-view/app && sudo -u gev git checkout v0.3.0
```
Checked at v0.3.0: `package.json` has no lifecycle scripts. Only three locked packages run install scripts: `esbuild` (needed), `fsevents` (macOS only) and `puppeteer` (downloads Chrome for the test suite, not needed).

`.env`, owner-only. The settings in it: bind to the LAN, accept the DNS name (IP addresses are always accepted), and tighten the Google rate limit as `.env.example` suggests when the server isn't on localhost:
```bash
sudo -u gev bash -c 'umask 077; cat > /opt/gods-eye-view/app/.env' <<'EOF'
PORT=4173
HOST=0.0.0.0
GEV_ALLOWED_HOSTS=godseye.demarzo.lab,godseye
GEV_RATELIMIT_GOOGLE_PER_MIN=60
EOF
cd /opt/gods-eye-view/app && sudo -u gev env PUPPETEER_SKIP_DOWNLOAD=1 npm ci && sudo -u gev npm run doctor
```

## 4. Service
`/etc/systemd/system/gods-eye-view.service`:
```ini
[Unit]
Description=God's Eye View (Vite dev server + provider proxy)
After=network-online.target
Wants=network-online.target

[Service]
User=gev
Group=gev
WorkingDirectory=/opt/gods-eye-view/app
ExecStart=/usr/bin/npm run dev -- --host 0.0.0.0 --port 4173 --strictPort
Restart=on-failure
RestartSec=5
NoNewPrivileges=yes
ProtectSystem=strict
ReadWritePaths=/opt/gods-eye-view
PrivateTmp=yes
ProtectKernelTunables=yes
ProtectControlGroups=yes
RestrictSUIDSGID=yes

[Install]
WantedBy=multi-user.target
```
`systemctl daemon-reload && systemctl enable --now gods-eye-view`. The first `/api/cctv/health` call after a start builds the camera catalog and can take more than 20 s. Later calls are instant.

## 5. Host firewall
```bash
ufw default deny incoming && ufw default allow outgoing
ufw allow from 10.12.5.0/24  to any port 22   proto tcp comment 'SSH from Management'
ufw allow from 10.12.10.10   to any port 22   proto tcp comment 'SSH from admin desktop'
ufw allow from 10.12.5.0/24  to any port 4173 proto tcp comment 'GEV from Management'
ufw allow from 10.12.10.0/24 to any port 4173 proto tcp comment 'GEV from Internal'
ufw --force enable
```
The gateway ACLs already keep every other zone out except Management and Internal. ufw also blocks the other Servers hosts, which share the VLAN and so never pass the gateway.

## 6. Splunk forwarder
```bash
ssh godseye 'f=$(mktemp); cat >"$f"; sudo bash "$f" linux; rm -f "$f"' < splunk/forwarder/install-uf.sh
```
Expect the DNS-based detections to notice this host at first. It talks to dozens of public data APIs and state traffic-camera services, so `command-and-control-new-iot-domain` and `exfiltration-dns-tunneling` are the ones to watch.

## Adding provider keys
Keyless mode covers Esri imagery, flights (adsb.lol, anonymous OpenSky), satellites, quakes, weather, cyclones and public cameras. Keys go in `.env` as the `gev` user, then `sudo systemctl restart gods-eye-view`. The in-app **Provider Settings** panel answers only the machine running the server: from the LAN it returns 403 `not-loopback`, so nobody can write keys through the UI. That's by design.

- Free: `CESIUM_ION_TOKEN` (Google 3D tiles through ion), `AISSTREAM_API_KEY` (ships), `FIRMS_MAP_KEY` (fires).
- Metered: `GOOGLE_MAPS_API_KEY`, `OPENAI_API_KEY` (voice). Set a provider-side budget first. `GOOGLE_MAPS_API_KEY`, `CESIUM_ION_TOKEN` and `MAPILLARY_CLIENT_TOKEN` are sent to the browser by design, so restrict them by referrer or URL.

Check variable names against `.env.example` at the pinned tag.

## Verify
```bash
curl -s -o /dev/null -w '%{http_code}\n' http://godseye.demarzo.lab:4173/                        # 200
curl -s -o /dev/null -w '%{http_code}\n' -H 'Host: evil.example.com' http://10.12.30.51:4173/    # 403 (host check)
curl -s http://godseye.demarzo.lab:4173/api/setup/status                                         # 403 not-loopback
curl -s -o /dev/null -w '%{http_code}\n' http://godseye.demarzo.lab:4173/api/cyclones            # 200 (proxy egress)
ssh -n fantasy 'timeout 5 bash -c "exec 3<>/dev/tcp/10.12.30.51/4173" && echo OPEN || echo BLOCKED'   # BLOCKED
```

## Upgrading
```bash
cd /opt/gods-eye-view/app
sudo -u gev git fetch --tags && sudo -u gev git checkout <new tag>
# read the CHANGELOG and diff package.json / package-lock.json install scripts first
sudo -u gev env PUPPETEER_SKIP_DOWNLOAD=1 npm ci && sudo -u gev npm run doctor
sudo systemctl restart gods-eye-view
```
Take a snapshot first.

## Rollback
Snapshots: `base` (OS + admin access, before Node) and `gev-ready` (v0.3.0, keyless, service + ufw + UF). To remove the host: stop and delete LXC 202, delete the DNS record in the Technitium console (the `ops` API user can't delete), and drop `Host godseye` from `~/.ssh/config` and its `known_hosts` line.
