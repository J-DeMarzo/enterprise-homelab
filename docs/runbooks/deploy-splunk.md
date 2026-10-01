# Runbook: Deploy the Splunk server

**Result:** `splunk` (VMID 151, originally built as 210, darrow, 10.12.30.20) running Splunk Enterprise with the `homelab_base` app, rsyslog intake on 514, and a host firewall. Design: [siem.md](../architecture/siem.md). Last done: 2026-09-30 (Splunk 10.4.4, 60-day trial).

## 1. VM
Clone template 9001 per [deploy-guest-from-template.md](deploy-guest-from-template.md): clone to fast-local on sevro, migrate to darrow. Then set 4 vCPU / 8192 MiB, resize `scsi0` to 150G, `ipconfig0 ip=10.12.30.20/24,gw=10.12.30.1`, tags `infra;net-svc`, and add a Notes card. Check that cloud-init shows `done`, the disk grew, the agent is up, and **NTP is synchronized** (SIEM timestamps depend on it).

## 2. Install
```bash
F=splunk-10.4.4-f0f12fcdcaa1-linux-amd64.deb
wget -O $F https://download.splunk.com/products/splunk/releases/10.4.4/linux/$F
curl -s https://download.splunk.com/products/splunk/releases/10.4.4/linux/$F.sha512   # compare
sha512sum $F
sudo dpkg -i $F        # creates user "splunk", installs to /opt/splunk
```
The Linux package sits next to the Windows `.msi` on the download site: same version and build hash, `linux-amd64.deb`.

## 3. App (config as code)
Copy [`splunk/apps/homelab_base`](../../splunk/apps/homelab_base/) to `/opt/splunk/etc/apps/` and `chown -R splunk:splunk` it.
> ⚠️ The app **must** include `metadata/default.meta` with `export = system`. Without it, the `vlan_zones` lookup is private to the app, and searches from the Search app **return nothing, with no error**.

## 4. Admin credential and first start
```bash
umask 077; openssl rand -base64 24 | tr -d '=+/' | cut -c1-24 | sudo tee /root/splunk-admin.pass >/dev/null
# write /opt/splunk/etc/system/local/user-seed.conf (USERNAME = admin, PASSWORD = <that>), owned by splunk, mode 600
sudo -u splunk /opt/splunk/bin/splunk start --accept-license --answer-yes --no-prompt
sudo -u splunk /opt/splunk/bin/splunk stop
sudo /opt/splunk/bin/splunk enable boot-start -user splunk -systemd-managed 1 --accept-license --answer-yes --no-prompt
sudo systemctl start Splunkd
```
Splunk consumes and deletes `user-seed.conf` on first start. Move the password from `/root/splunk-admin.pass` into a password manager, then delete the file.

## 5. Syslog intake
```bash
sudo install -d -o syslog -g splunk -m 2750 /var/log/remote     # setgid: files inherit group splunk
sudo cp splunk/server/rsyslog-remote.conf /etc/rsyslog.d/10-remote.conf
sudo rsyslogd -N1 && sudo systemctl restart rsyslog
```
> ⚠️ Ubuntu's rsyslog runs as `syslog`, so it can't chown files. Use the setgid directory, not `fileGroup=`. `dirCreateMode` only accepts `0xxx` values (`2750` is a config error).

Test: `logger -n 127.0.0.1 -P 514 test`. A file should appear under `/var/log/remote/127.0.0.1/` as `syslog:splunk 0640`. Delete it afterwards.

## 5b. Sourcetypes per sender (important)
Set the sourcetype **in `inputs.conf`, one monitor per sender folder** ([inputs.conf](../../splunk/apps/homelab_base/default/inputs.conf)).
> ⚠️ An explicit `sourcetype` in `inputs.conf` **outranks** `props.conf` `[source::]` renames. With a single catch-all monitor, the per-sender parsing silently didn't apply, and **neither did the household privacy filter** attached to `omada:eap`, so household flows were indexed. It was caught by testing and fixed by purging.

**Purge and re-index** after fixing parsing or filters:
```bash
sudo systemctl stop Splunkd
sudo -u splunk /opt/splunk/bin/splunk clean eventdata -index netfw -f
for f in /var/log/remote/*/*.log; do
  sudo -u splunk /opt/splunk/bin/splunk cmd btprobe -d /opt/splunk/var/lib/splunk/fishbucket/splunk_private_db --file "$f" --reset
done
sudo systemctl start Splunkd
```
Then verify: `| tstats count where index=netfw by host sourcetype`, and a search showing **0** Internal/Guest records in `omada:eap`.

Install [`cron-remote-cleanup`](../../splunk/server/cron-remote-cleanup) as `/etc/cron.d/remote-syslog-cleanup`, so only today's raw files are kept.

## 6. Host firewall
Run [`splunk/server/ufw-rules.sh`](../../splunk/server/ufw-rules.sh) as root. Default deny, and:
- 8000 from Management and the admin desktop
- 9997 from Management, Servers, Security, and DMZ
- 514 from Management and the gateway's Servers interface
- 22 from Servers, Management, and the admin desktop

Splunk 10 also listens on **0.0.0.0:5432** (bundled PostgreSQL) and 8089. Both stay closed to the network.

## 6b. Universal Forwarders
Installer: [`splunk/forwarder/install-uf.sh`](../../splunk/forwarder/install-uf.sh). It downloads UF 10.4.4, verifies the SHA-512, and installs it with a random root-only admin credential. Roles: `linux` (journald → `linux`), `technitium` (query logs → `dns`). Run it from a URL **pinned to a commit** so the script can't change under you:
```bash
# VM (e.g. ops), as root:
curl -fsSL https://raw.githubusercontent.com/J-DeMarzo/enterprise-homelab/<commit>/splunk/forwarder/install-uf.sh | bash -s -- linux
# LXC, from its Proxmox host:
pct exec <vmid> -- bash -c "curl -fsSL <same URL> | bash -s -- linux technitium"
```
> ⚠️ **Lessons from the first install (ops):** (1) never run the `splunk` binary as root before `enable boot-start`, because it drops to `splunkfwd` and trips over root-owned dirs; (2) a manual `splunk start` + `splunk stop` hung with the journald input active, so let `enable boot-start` and systemd handle it; (3) the QEMU guest agent kills commands after 60 s, so run long installs over SSH or `pct exec`, not the guest agent.

Verify: `| tstats count where index=linux by host`, plus a `logger` test message showing up within seconds.

**Technitium:** enable Settings → Logging → *Log All Queries* (UTC) first. On v15+ the logs are in `/var/log/technitium/dns/` (older: `/etc/dns/logs`, `/etc/dns/config/logs`). The installer searches all of them. The first run backfills today's whole log file, so expect a one-time spike in license usage.

## 7. Verify
- `server/info`: version and `activeLicenseGroup = Trial`
- `| rest /services/data/indexes`: the 7 lab indexes with the expected retention
- `| makeresults … | lookup vlan_zones cidr AS ip`: one IP per VLAN resolves to its zone, anything else to `external`
- `| rest /services/data/inputs/tcp/cooked`: 9997 enabled
- Firewall tests T11, T12, T25–T30 ([firewall-rules.md](../architecture/firewall-rules.md#test-results))
