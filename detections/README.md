# Detections

SPL detections for the lab's Splunk instance, one file per detection, named `<tactic>-<short-name>.spl`. These files are the **source of truth**: [`splunk/build-savedsearches.py`](../splunk/build-savedsearches.py) generates the app's `savedsearches.conf` from them, and [`splunk/server/deploy-app.sh`](../splunk/server/deploy-app.sh) ships it.

Each file starts with a header. `Name`, `Cron` and `Window` are read by the generator, and the rest is documentation:

````spl
``` Name:        Denied probes toward Management
    ATT&CK:      T1046 (Network Service Discovery)
    Data:        index=netfw sourcetype=omada:gateway action=Block
    Cron:        */15 * * * *
    Window:      -20m@m to -5m@m
    Severity:    high from Security/DMZ/IoT/Guest, medium from other zones
    Tested with: nmap from kali against two Management hosts (2026-10-01)
    False positives: ... ```
index=netfw ... | stats ... | where ...
| eval detection="denied_probes_to_management", severity=..., attack="T1046", summary=...
| collect index=soc_alerts source="detection:denied_probes_to_management"
````

Every detection is a **scheduled report**, not an alert. It ends by writing its hits to the `soc_alerts` summary index with `collect`, and the **Alert queue** dashboard reads from there. That replaces alert actions on Splunk Free ([ADR 0006](../docs/adr/0006-soc-focus-with-splunk.md)) and mirrors how Enterprise Security's notable events work. The 15-minute windows don't overlap (`-20m@m` to `-5m@m`, run every 15 minutes), so each event is evaluated once, with 5 minutes of slack for indexing delay.

Every hit carries the same fields: `detection`, `severity`, `attack`, `summary`, `src_ip`, `src_zone`, plus detection-specific evidence.

**Baselines** ([`baselines/`](baselines/)) are daily searches that build the "known" lists some detections compare against. They stop an hour back, so a new device or domain is never learned before the detection has seen it. The lookups they write stay on the server, out of the repo.

A detection is added here only once it has **fired against a recorded test**. Its emulated-attack case write-up in [`docs/investigations/`](../docs/investigations/) follows in Phase 5.

| Detection | ATT&CK | Tested (2026-10-01) | Case |
|---|---|---|---|
| [Denied probes toward Management](discovery-denied-probes-to-management.spl) | T1046 | ✅ `nmap --top-ports 50` from kali against 2 Management hosts: 33 blocks on 25 ports logged, **high** alert on the first scheduled run | Phase 5 |
| [New device on the Management VLAN](initial-access-new-device-on-management.spl) | T1200 | ✅ Temporary LXC plugged into Management: DHCP lease and first DNS query both raised **high** alerts. Two signals, because a static-IP device leaves no DHCP trace | Phase 5 |
| [IoT device resolves a never-seen domain](command-and-control-new-iot-domain.spl) | T1071 | ✅ Temporary LXC on IoT resolved 2 domains no IoT device had used: **low** alert naming both. In learning mode until the 7-day review | Phase 5 |
| [DNS tunneling](exfiltration-dns-tunneling.spl) | T1071.004 | ✅ 100 random 40-character labels under `exfil-test.invalid` from kali: **high** alert. No false positives in the previous 24 h | Phase 5 |
| [Web probing against demarzo.dev](reconnaissance-web-probing.spl) | T1595.003 | ✅ 20 scanner paths from ops through Cloudflare: **low** alert. Real internet scanners trigger it too | Phase 5 |

Tuning notes from building them on real data (24 h, 15-minute buckets):
- **Probes:** "10+ blocked events" would have fired on a phone retrying DNS-over-TLS (:853) to dns1/dns2. The rule needs **5 ports or 3 hosts** instead.
- **Tunneling:** the busiest legitimate pattern (an IoT device under `apple.com`) peaked at 37 unique names with 12-character labels. The threshold is 50 names averaging 30+ characters.
- **New IoT domain:** IoT still meets ~50 new base domains a day while the baseline is young, so it's one low-severity alert per device per run. The volume gets reviewed at the 7-day license check.
