# 0001. 3-node cluster plus a standalone storage node

- **Status:** Accepted
- **Date:** 2026-09-29 (written after the fact)

## Context
There are four physical hosts. Three have plenty of CPU and RAM (darrow, sevro, ragnar). One (sefi) has less compute but holds the large ZFS pool. A Proxmox cluster needs a majority of votes (quorum) to make changes. An even number of nodes, or a 2-node cluster, needs a QDevice to survive losing a node.

## Decision
- Cluster the three compute hosts as `TheRising`. Three votes means any one node can go down and the cluster keeps quorum.
- Run `sefi` as a **standalone** Proxmox host that provides storage (NFS) and the second copy of core services (dns2, ops).

## Consequences
- ✅ Quorum math is simple, with no QDevice needed.
- ✅ Problems that hit the whole cluster (lost quorum, a bad upgrade across all nodes) don't take down storage, dns2, or the ops VM. Those are what you need to fix the cluster.
- ✅ Storage maintenance on sefi doesn't affect cluster quorum.
- ❌ Guests can't live-migrate between the cluster and sefi. Moving one means backup and restore.
- ❌ Two management UIs and API endpoints instead of one.
