# Architecture Decision Records

Short records of significant design decisions: the context, what was decided, and what it costs. The format is based on [Michael Nygard's ADR template](https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions).

ADRs 0001–0004 were written after the fact, describing decisions already in place when this repo was created.

| # | Decision | Status |
|---|---|---|
| [0001](0001-cluster-plus-standalone-storage-node.md) | 3-node cluster plus a standalone storage node | Accepted |
| [0002](0002-technitium-dns-pair.md) | Technitium DNS pair split across failure domains | Accepted |
| [0003](0003-vlan-segmentation.md) | VLAN segmentation by trust zone | Accepted |
| [0004](0004-nfs-for-shared-media-local-zfs-for-guests.md) | NFS for shared media, local ZFS for guest disks | Accepted |
| [0005](0005-admin-hosts-in-management-zone.md) | Admin hosts live in the management zone | Accepted |
| [0006](0006-soc-focus-with-splunk.md) | Focus on SOC work, with Splunk as the SIEM | Accepted |
| [0007](0007-splunk-topology-and-household-data.md) | Splunk topology: one indexer, chokepoint-first, household data minimization | Accepted |
| [0008](0008-agent-workstation-in-management-bots-scoped.md) | Agent workstation moves to Management; bots isolated with a scoped token | Accepted |
| [0009](0009-least-privilege-proxmox-api-identities.md) | Least-privilege Proxmox API identities | Accepted |

## Template

```markdown
# NNNN. Title

- **Status:** Proposed | Accepted | Superseded by NNNN
- **Date:** YYYY-MM-DD

## Context
What problem or force makes this decision necessary?

## Decision
What we're doing.

## Consequences
What gets easier, what gets harder, what we accept.
```
