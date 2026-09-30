# 0003. VLAN segmentation by trust zone

- **Status:** Accepted
- **Date:** 2026-09-29 (written after the fact)

## Context
A flat network lets any compromised or misbehaving guest reach the hypervisor management interfaces. The lab also runs offensive-security tools (Kali) that must not reach real infrastructure by accident.

## Decision
Seven VLANs, one per trust zone, routed by the Omada gateway. The subnet is `10.12.<VLAN>.0/24`:

| VLAN | Zone | Role |
|---|---|---|
| 5 | Management | Hypervisors, DNS, admin hosts (native/untagged on `vmbr0`) |
| 10 | Internal | Trusted personal devices |
| 20 | IoT | Smart-home and embedded devices |
| 30 | Servers | Workloads, dashboards, SIEM |
| 40 | Security | Attack VMs and deliberately vulnerable targets |
| 50 | DMZ | Internet-exposed services |
| 99 | Guest | Visitors, internet only |

The policy is an allow-list with a default-deny between VLANs ([firewall-rules.md](../architecture/firewall-rules.md)).

Guests pick a VLAN with a tag on their virtual NIC. The hosts use one bridge (`vmbr0`) with a single uplink.

## Consequences
- ✅ Clear trust zones that map to enterprise patterns: management, user, IoT, server, DMZ, guest, and an isolated lab.
- ✅ Moving a guest between zones is a one-field change.
- ❌ Segmentation is only real once the gateway has ACLs between VLANs. Until then VLANs separate broadcast domains but may still route freely. Enforcing and testing the policy is roadmap Phase 2.
- ❌ Management is the native VLAN, so an untagged guest lands on management by default. New guests must be tagged on purpose.
