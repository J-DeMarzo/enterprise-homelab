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
- [ ] **Least-privilege API token** for `claude-mcp@pve`: it currently holds near-admin rights (can create users, allocate SDN, and so on). Replace it with a custom role scoped to VM, storage, and guest-agent operations. Record the change as an ADR
- [ ] **Rebuild `ops`** as a headless Ubuntu 24.04 jump box (2 vCPU / 4 GiB) from a verified cloud image. Build a golden cloud-init template (VMID 9001) on TheRising for Splunk and future VMs. Runbook

## Phase 2: Safe to attack
- [x] **Enforce default-deny between VLANs**: IP groups corrected, DNS rule limited to port 53, default-deny enabled. *Evidence:* [before/after test table](architecture/firewall-rules.md#test-results). 16/18 pass, and the ACLs are verified stateful
- [ ] Restrict the gateway's admin UI to Management (tests T6/T7 still open from the Security VLAN)
- [ ] Read-only credentials for homepage's widgets (Proxmox `PVEAuditor`, Omada viewer, Technitium read-only). Homepage can reach management APIs through rule 9

## Phase 3: Visibility (SIEM)
| Item | Placement | Evidence to finish it |
|---|---|---|
| [ ] **Splunk Enterprise** (60-day trial → Free), VM at 10.12.30.20 | darrow · 4 vCPU / 8 GiB / ~150 GiB | Web UI reachable from management only (firewall test T12) |
| [ ] Indexes and data onboarding: `linux`, `wineventlog`, `sysmon`, `dns`, `network` | – | Each source searchable with correct sourcetypes |
| [ ] Universal Forwarder on Linux guests and the Proxmox hosts | – | Auth logs from each host in Splunk |
| [ ] **Technitium DNS query logs** → Splunk | dns1, dns2 | Queries from kali visible by client IP |
| [ ] **Omada firewall syslog** → Splunk | gateway | ACL-deny events visible (the Phase 2 tests will generate them) |
| [ ] **Alert queue**: scheduled detections → `soc_alerts` summary index → triage dashboard | – | A test detection shows up in the queue |

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
