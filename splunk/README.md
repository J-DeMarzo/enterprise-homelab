# Splunk configuration

Version-controlled Splunk configuration for the lab SIEM. Design: [docs/architecture/siem.md](../docs/architecture/siem.md).

```
apps/homelab_base/        installed on the indexer (splunk, 10.12.30.20)
  metadata/default.meta   export = system (required, otherwise the lookup is invisible outside the app)
  default/indexes.conf    indexes + retention
  default/transforms.conf zone lookup definition (+ DNS privacy filter, added when Technitium is onboarded)
  default/props.conf      sourcetypes + automatic lookups (added per source as onboarded)
  lookups/vlan_zones.csv  10.12.<vlan>.0/24 → zone, trust
  lookups/omada_acl_rules.csv  gateway ACL rule ID → rule name
  default/app.conf, data/ui/nav  app label "Homelab SOC", nav (Zone overview is the home page)
  default/data/ui/views/  Dashboard Studio dashboards (version="2" XML with the JSON definition inside)
forwarder/install-uf.sh   Universal Forwarder installer: checksum-verified package, localhost-only mgmt port,
                          roles `linux` (journald → linux), `technitium` (query logs → dns),
                          `pve` (Proxmox API access log → linux) and `caddy` (Caddy JSON → web)
server/                   rsyslog intake, ufw host firewall, raw-buffer cleanup cron for the Splunk VM,
                          deploy-app.sh (push homelab_base to the indexer from ops)
```

Deploy: copy `apps/homelab_base` to `$SPLUNK_HOME/etc/apps/` on the indexer and restart Splunk. Sourcetypes and filters are written against **real sample events** from each source, not guessed formats, so they're added as each source is onboarded.
