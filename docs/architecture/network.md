# Network

## Edge

A **TP-Link Omada** gateway routes between VLANs and to the internet. It has an address in each VLAN (`.1`).

## VLAN plan

| VLAN | Name | Subnet | Gateway | Purpose | Tagging on vmbr0 |
|---|---|---|---|---|---|
| 5 | Management | 10.12.5.0/24 | 10.12.5.1 | Proxmox hosts, DNS, admin hosts | Untagged (native) |
| 30 | Services | 10.12.30.0/24 | 10.12.30.1 | Workloads and dashboards | `tag=30` |
| 40 | Security lab | 10.12.40.0/24 | 10.12.40.1 | Kali and future attack targets | `tag=40` |

## IP allocation

| Range | Use |
|---|---|
| `.1` | Gateway |
| `10.12.5.10` | ops, the admin host (static, set by cloud-init) |
| `10.12.5.11–.14` | Proxmox nodes (darrow `.11`, sevro `.12`, ragnar `.13`, sefi `.14`) |
| `10.12.5.53–.54` | DNS (dns1 `.53`, dns2 `.54`), named after port 53 |
| `.100+` | DHCP leases (observed) |

Infrastructure that other things depend on (hypervisors, DNS, ops) gets static addresses. Everything else uses DHCP.

## Host networking

Each Proxmox node has one NIC (`nic0`) bridged to `vmbr0`. Guests pick their VLAN with a tag on their virtual NIC, so a guest can move between VLANs without any host network change. Guest NICs have the Proxmox firewall flag enabled so per-guest rules can be added later.

## Segmentation policy

| From → To | Management | Services | Security lab |
|---|---|---|---|
| **Management** | ✅ | ✅ | ✅ |
| **Services** | ⚠️ DNS only, plus `claude` → Proxmox API until it moves (target) | ✅ | ✅ |
| **Security lab** | ❌ except DNS :53 to dns1/dns2 (target) | ❌ except Splunk :9997 (target) | ✅ |

Admin hosts sit *in* the management zone ([ADR 0005](../adr/0005-admin-hosts-in-management-zone.md)), so the management rule doesn't need per-host exceptions for them.

Rows marked *(target)* are the intended policy. The Omada ACLs that enforce the security-lab row, and the baseline test showing the lab is **not** isolated yet, are in [firewall-rules.md](firewall-rules.md).
