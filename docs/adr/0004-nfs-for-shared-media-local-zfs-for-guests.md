# 0004. NFS for shared media, local ZFS for guest disks

- **Status:** Accepted
- **Date:** 2026-09-29 (written after the fact)

## Context
The cluster nodes each have fast local storage. Sefi has a large 5.3 TB ZFS pool (`pax`). Running guests' disks from shared storage would allow instant migration and HA, but on a home network it adds latency and makes the storage host a single point of failure for every guest.

## Decision
- Guest disks go on each node's local ZFS pool (`fast-local` on the cluster, `local-zfs` on sefi).
- Sefi exports `ISO`, `Templates`, `VM-Templates`, and `Snippets` from `pax` over NFS to the cluster.

## Consequences
- ✅ Guest disk I/O runs at local-disk speed.
- ✅ If sefi goes down, running guests aren't affected. Only cloning new guests and mounting ISOs stop working.
- ✅ One copy of each ISO and template for the whole cluster.
- ❌ Migration has to copy disks (`--with-local-disks`), so it's slower than with shared storage.
- ❌ No automatic HA restart of guests on another node.
