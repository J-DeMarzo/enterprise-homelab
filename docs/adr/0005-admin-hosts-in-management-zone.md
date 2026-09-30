# 0005. Admin hosts live in the management zone

- **Status:** Accepted
- **Date:** 2026-09-29

## Context
`ops`, the admin and automation VM (the future Ansible control node), sat on the Servers VLAN (30). The planned segmentation policy ([ADR 0003](0003-vlan-segmentation.md)) blocks Servers → Management. That meant the management rule needed a per-host exception for ops: "Servers can't reach Management, *except 10.12.30.10*". Per-host exceptions are hard to audit and tend to multiply.

Tagging every guest by role ([tag scheme](../architecture/compute.md#tag-scheme)) made this visible. ops is an `admin` host, not a workload.

## Decision
Hosts the lab is managed *from* (`admin` role) live on the Management VLAN (5), next to what they manage. ops moved from 10.12.30.10 (VLAN 30) to **10.12.5.10** (VLAN 5, untagged). Management → all zones is already allowed, so ops can still reach every workload it automates.

## Consequences
- ✅ The management ACL becomes a zone rule ("only the management VLAN reaches management") with no host-level holes.
- ✅ Automation traffic (Ansible → hypervisors, DNS, guests) no longer crosses a zone boundary to reach the hypervisors.
- ❌ An admin host that gets compromised is already inside the management zone. Mitigations: key-only SSH (already the case), and later, Wazuh monitoring (roadmap Phase 2).
- ❌ Changing the cloud-init network config made cloud-init treat ops as a new instance and regenerate its SSH host keys. Clients see it as a new host.
- ⚠️ `claude` is also an `admin` host but stays on VLAN 30 for now. Until it moves, the ACLs need one documented exception: `claude` → Proxmox API (TCP 8006).

## Change record
| Step | Result |
|---|---|
| Snapshot `pre-vlan5-move` | Rollback point |
| Graceful shutdown → `net0` tag removed, `ipconfig0=ip=10.12.5.10/24,gw=10.12.5.1` → start | Up in ~15 s, cloud-init `done` |
| Verification from inside ops | Gateway, VLAN 30, internal and external DNS, and internet all reachable. Old IP silent |
| Pre-existing issue found | `lightdm.service` failed on every boot (headless VM, `vga: serial0`), unrelated to this change. Fixed with `systemctl disable lightdm`, and ops now reports `running` with no failed units |
| Superseded | 2026-09-30: ops was rebuilt from scratch as a headless jump box at the same address ([runbook](../runbooks/build-ubuntu-template.md)). The old VM and its `pre-vlan5-move` snapshot were destroyed |
