# Roadmap

**Goal:** show SOC analyst skills with evidence: attacks emulated, detected in Splunk, investigated, and written up. See [ADR 0006](adr/0006-soc-focus-with-splunk.md).

Guiding rule: **enterprise patterns at a homelab scale.** An item is checked off only when its evidence exists (a test, a screenshot, a case write-up), linked from the item.

## Phase 0: Documentation foundation ✅
- [x] Repo structure, architecture docs, ADRs, runbooks
- [x] Inventory generated from the Proxmox API ([`scripts/inventory.py`](../scripts/inventory.py))
- [x] Secret scanning on commit (gitleaks)

## Phase 1: Hygiene ✅ (mostly)
- [x] Guest metadata: Notes cards and [role/zone tags](architecture/compute.md#tag-scheme) on all guests, following the [guest notes standard](architecture/compute.md#guest-notes-standard)
- [x] Move `ops` to the management VLAN ([ADR 0005](adr/0005-admin-hosts-in-management-zone.md)). *Evidence:* change record and connectivity checks in the ADR
- [ ] DNS: records for `ops`, `homepage`, `gw`, `splunk`. Fix the NS records. Document how dns2 syncs
- [ ] Clean up orphaned `unused0` disks on VMIDs 250 and 9000
- [ ] Renumber `splunk` 210 → 151 to fit the [VMID scheme](architecture/compute.md#guest-standards) (node by hundreds, LXC `x00–49`, VM `x50–99`)
- [ ] **Least-privilege API token** for `claude-mcp@pve`: it currently holds near-admin rights (can create users, allocate SDN, and so on). Replace it with a custom role scoped to VM, storage, and guest-agent operations. Record the change as an ADR
  - [x] The Discord bot no longer shares it: its own user `discord-bot@pve` holds `PVEAuditor` plus a custom `DiscordBot` role (`VM.PowerMgmt`, `VM.Snapshot`, `Sys.Syslog`) on both targets. *Evidence:* a config write from the bot's token returns 403 `Permission check failed`
  - [x] `claude-mcp@pve` token rotated (`!mcp` → `!ops`, 2026-10-01). It now exists only on `ops`, and the old token returns 401
  - [ ] Scope `claude-mcp@pve`'s own role down from `PVEAdmin`
- [ ] Restore SSH access to sefi: `sshd` accepts public keys only (since an old hardening playbook) and no admin key is authorized. Add the `ops` key from the web UI shell
- [x] **Rebuild `ops`** as a headless Ubuntu 24.04 jump box (2 vCPU / 4 GiB, both DNS servers) and build the golden template `ubuntu-2404-ci` (9001). *Evidence:* [runbook](runbooks/build-ubuntu-template.md), verified test clone, [INC-2026-001](incidents/2026-09-30-darrow-nfs-stale-handle.md)

## Phase 2: Safe to attack ✅
- [x] **Enforce default-deny between VLANs**: IP groups corrected, DNS rule limited to port 53, default-deny enabled. *Evidence:* [before/after test table](architecture/firewall-rules.md#test-results). all 21 executed tests pass, and the ACLs are verified stateful
- [x] Block the gateway's admin UI from every non-management VLAN (rule 11). *Evidence:* T6/T7/T23 blocked, internet and DNS unaffected (T24)
- [ ] Read-only credentials for homepage's widgets (Proxmox `PVEAuditor`, Omada viewer, Technitium read-only). Homepage can reach management APIs through rule 9

## Phase 3: Visibility (SIEM)
Design: [siem.md](architecture/siem.md) · [ADR 0007](adr/0007-splunk-topology-and-household-data.md) · config in [`splunk/`](../splunk/)

| Item | Placement | Evidence to finish it |
|---|---|---|
| [x] **Splunk Enterprise** 10.4.4 (60-day trial → Free), VM `splunk` (210) at 10.12.30.20, cloned from template 9001 ([runbook](runbooks/deploy-splunk.md)) | darrow · 4 vCPU / 8 GiB / 150 GiB | T11 ✅, T12 ✅, T25 ✅, T26–T30 ✅ |
| [x] Indexes, zone lookup, rsyslog intake (`homelab_base` app) | splunk | 7 indexes with retention. Zone lookup verified for one IP per VLAN + external. 514 intake tested |
| [x] **Omada** remote syslog: gateway ACL events, controller DHCP, access point flows (household-filtered) | gateway, controller, AP | ✅ A kali → Management probe at 11:30:58 was indexed at 11:30:58 as `security → management`, Block. 0 household flows indexed |
| [x] NTP and time zone (with DST) on the Omada devices (clocks were ~3 min slow). Splunk uses rsyslog's receive time regardless | Omada | ✅ After the fix: gateway within 3 s and AP within 1 s of receive time |
| [x] **Technitium** query logs with the household privacy filter | dns1, dns2 | ✅ 7-case filter test all correct. Live: Internal shows only failures, lab/IoT in full, zones resolved |
| [ ] Universal Forwarders: ~~ops~~ ✅, ~~dns1~~ ✅, ~~dns2~~ ✅, homepage, bots, fantasy, Proxmox hosts ([installer](../splunk/forwarder/install-uf.sh)) | – | Journald from each host in `linux`. ops: ✅ logger test indexed within seconds |
| [ ] **dmz-edge** forwarder: Caddy + cloudflared → `web` (rule 8 gets DMZ as a source) | dmz-edge | Real internet requests to demarzo.dev searchable, with the client IP taken from `Cf-Connecting-Ip` |
| [ ] Zone overview dashboard (deny matrix, DNS by zone, new DHCP devices) | – | Screenshot (aggregates only) |
| [ ] **Alert queue** + first detections (new device on Management, denied probes toward Management, new IoT domain, DNS tunneling, web probing) | – | Each detection fired by a test |
| [ ] License check after 7 days | – | Measured MB/day per source vs. the budget in siem.md |

## Phase 4: Something worth defending
| Item | Placement | Evidence to finish it |
|---|---|---|
| [ ] **Windows Server DC** (evaluation), small AD domain | VLAN 40 · ~4 GiB | Domain up, lab DNS forwards to dns1/dns2 |
| [ ] **Windows 11 client**, domain-joined | VLAN 40 · ~4 GiB | Domain logon events in Splunk |
| [ ] **Sysmon** (community config) + Universal Forwarder on both | – | Sysmon process/network/DNS events in Splunk, within the ingest budget |
| [ ] Golden templates for both, for rebuilding when the evaluations expire | VM-Templates (NFS) | Runbook plus one timed rebuild |

## Phase 5: SOC workflow evidence
Each item is one emulated attack → [detection](../detections/) → [case write-up](investigations/).
- [ ] SSH brute force against a Linux host (T1110.001)
- [ ] Password spraying against AD (T1110.003)
- [ ] Kerberoasting (T1558.003)
- [ ] LSASS credential dumping (T1003.001)
- [ ] Persistence via scheduled task (T1053.005)
- [ ] DNS tunneling / exfiltration (T1071.004)
- [ ] Bonus: [Boss of the SOC](https://github.com/splunk/botsv3) dataset investigations

## Later / optional
- Case management (TheHive or DFIR-IRIS) and SOAR (Shuffle)
- Network security monitoring (Zeek / Security Onion)
- **Proxmox Backup Server** on sefi (`pax`), for backups and restore tests
- Monitoring (Prometheus + Grafana + Uptime Kuma)

## On hold
- **Ansible** config management and **Terraform** provisioning from `ops`. Paused in favor of SOC work ([ADR 0006](adr/0006-soc-focus-with-splunk.md)). `ops` stays ready as the control node.

## Capacity
Splunk (8 GiB) plus the AD targets (~8 GiB) come to about 16 GiB. darrow alone has about 25 GiB free.
