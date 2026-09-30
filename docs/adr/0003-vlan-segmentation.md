# 0003. VLAN segmentation: management / services / security lab

- **Status:** Accepted
- **Date:** 2026-09-29 (written after the fact)

## Context
A flat network lets any compromised or misbehaving guest reach the hypervisor management interfaces. The lab also runs offensive-security tools (Kali) that must not reach real infrastructure by accident.

## Decision
Three VLANs, routed by the Omada gateway:

| VLAN | Role |
|---|---|
| 5 | Management: hypervisors and core infrastructure (native/untagged on `vmbr0`) |
| 30 | Services: workloads and tooling |
| 40 | Security lab: attack VMs and deliberately vulnerable targets |

Guests pick a VLAN with a tag on their virtual NIC. The hosts use one bridge (`vmbr0`) with a single uplink.

## Consequences
- ✅ Clear trust zones that map to enterprise patterns (a management network, a server network, a DMZ/lab).
- ✅ Moving a guest between zones is a one-field change.
- ❌ Segmentation is only real once the gateway has ACLs between VLANs. Until then VLANs separate broadcast domains but may still route freely. Enforcing and testing the policy is roadmap Phase 1.
- ❌ Management is the native VLAN, so an untagged guest lands on management by default. New guests must be tagged on purpose.
