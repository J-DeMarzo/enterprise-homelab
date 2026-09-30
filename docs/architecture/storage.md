# Storage

## Layout

| Storage | Type | Where | Content | Why |
|---|---|---|---|---|
| `fast-local` | ZFS pool | each TheRising node | VM and container disks | Fast local I/O; same name on every node so guests can migrate |
| `local-zfs` | ZFS pool | sefi | Sefi guest disks | |
| `pax` | ZFS pool (5.3 TB) | sefi | Bulk data, backing store for the shares below | Large capacity on one box |
| `ISO` | NFS (from sefi) | cluster-wide | Installer ISOs | One copy for every node |
| `Templates` | NFS (from sefi) | cluster-wide | LXC templates | |
| `VM-Templates` | NFS (from sefi) | cluster-wide | Golden VM images (9000, 9001) and verified cloud images (`import/`) | Any node can clone from them |
| `Snippets` | NFS (from sefi) | cluster-wide | Cloud-init snippets, hookscripts | |

On Sefi the same shares show up as local `dir` storage, since they live on `pax`. Sefi's `ISO` storage (`/pax/iso`) also allows `import` content, so Sefi VMs can be built from the same verified cloud image.

**Incident:** [INC-2026-001](../incidents/2026-09-30-darrow-nfs-stale-handle.md). darrow lost access to `VM-Templates` after a file delete through the API (stale NFS handle).

## Design notes

- **Guest disks stay local; shared data goes on NFS.** Running VM disks over NFS on a home network would be slow and would make Sefi a single point of failure for every guest. Only install media and templates go on NFS: if Sefi is down you can't clone new guests, but running ones keep going. See [ADR 0004](../adr/0004-nfs-for-shared-media-local-zfs-for-guests.md).
- **ZFS everywhere**, for checksums, snapshots, and compression.

## Known gap: backups

There's currently **no backup target and no scheduled backup jobs**. Snapshots aren't backups. They live on the same pool as the disk they protect. Fixing this is the first item in [roadmap Phase 2](../roadmap.md): Proxmox Backup Server on Sefi with its datastore on `pax`.
