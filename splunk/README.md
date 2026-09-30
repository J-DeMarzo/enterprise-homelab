# Splunk configuration

Version-controlled Splunk configuration for the lab SIEM. Design: [docs/architecture/siem.md](../docs/architecture/siem.md).

```
apps/homelab_base/        installed on the indexer (splunk, 10.12.30.20)
  metadata/default.meta   export = system (required, otherwise the lookup is invisible outside the app)
  default/indexes.conf    indexes + retention
  default/transforms.conf zone lookup definition (+ DNS privacy filter, added when Technitium is onboarded)
  default/props.conf      sourcetypes + automatic lookups (added per source as onboarded)
  lookups/vlan_zones.csv  10.12.<vlan>.0/24 → zone, trust
forwarder/install-uf.sh   Universal Forwarder installer: checksum-verified package, localhost-only mgmt port,
                          roles `linux` (journald → linux) and `technitium` (query logs → dns)
server/                   rsyslog intake, ufw host firewall, raw-buffer cleanup cron for the Splunk VM
```

Deploy: copy `apps/homelab_base` to `$SPLUNK_HOME/etc/apps/` on the indexer and restart Splunk. Sourcetypes and filters are written against **real sample events** from each source, not guessed formats, so they're added as each source is onboarded.
