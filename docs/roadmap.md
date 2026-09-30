# Roadmap

Guiding rule: **enterprise patterns at a homelab scale.** Each addition has to earn its keep in upkeep. Something that needs constant babysitting doesn't belong here.

An item is checked off only when its **evidence** exists (a test, a screenshot, a log), linked from the item.

## Phase 0: Documentation foundation ✅
- [x] Repo structure, architecture docs, ADRs, runbooks
- [x] Inventory generated from the Proxmox API ([`scripts/inventory.py`](../scripts/inventory.py))
- [x] Secret scanning on commit (gitleaks)

## Phase 1: Hygiene
- [ ] DNS: records for `ops`, `homepage`, `gw`. Fix the NS records to list `dns1.demarzo.lab` + `dns2.demarzo.lab`. Document how dns2 syncs
- [ ] Guest metadata: description (owner/role/VLAN) and tags on every guest
- [ ] Clean up orphaned `unused0` disks on VMIDs 250 and 9000
- [ ] Omada ACLs enforcing the [segmentation policy](architecture/network.md#segmentation-policy). *Evidence:* blocked and allowed connection tests from each VLAN

## Phase 2: Enterprise core
| # | Item | Placement | RAM | Evidence to finish it |
|---|---|---|---|---|
| 1 | **Proxmox Backup Server**: datastore on `pax`, nightly jobs for both environments, retention policy | sefi | ~2–4 GiB | A test LXC restored from backup, written up in a runbook |
| 2 | **Ansible** from the `ops` VM: patching, baseline hardening, user/SSH key management | ops | – | A clean `--check` run across the inventory |
| 3 | **Monitoring**: Prometheus + Grafana + Uptime Kuma | ragnar | ~2 GiB | An alert fires when dns1 is stopped. Dashboard screenshot |
| 4 | **Wazuh SIEM**: agents on all guests | darrow | ~8 GiB | An Nmap scan from the Kali VLAN shows up as an alert. Write-up in `docs/labs/` |

## Phase 3: Stretch (optional)
- [ ] **Active Directory**: a Windows Server DC plus one domain-joined client on VLAN 30 (~8 GiB). Also a realistic target for Kali lab exercises
- [ ] **Terraform** (`bpg/proxmox` provider): guest definitions in code
- [ ] **Offsite backup** copy for a full 3-2-1 setup

## Capacity
Phases 2–3 add about 22 GiB of RAM. About 55 GiB is free across the four nodes, so no new hardware is needed.
