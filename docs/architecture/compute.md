# Compute

## Nodes

| Node | Environment | IP | CPU threads | RAM | Local VM storage |
|---|---|---|---|---|---|
| darrow | TheRising | 10.12.5.11 | 12 | 31 GiB | `fast-local` ZFS, 899 GiB |
| sevro | TheRising | 10.12.5.12 | 8 | 31 GiB | `fast-local` ZFS, 450 GiB |
| ragnar | TheRising | 10.12.5.13 | 8 | 23 GiB | `fast-local` ZFS, 450 GiB |
| sefi | Sefi (standalone) | 10.12.5.14 | 4 | 15 GiB | `local-zfs`, 450 GiB, plus the `pax` pool |

Node names come from Pierce Brown's *Red Rising* series. The cluster is named `TheRising`.

## Cluster: TheRising

- 3 nodes, 3 votes. Quorum needs 2, so any single node can be taken down for maintenance.
- Each node has a ZFS pool named `fast-local`. Because the name is the same everywhere, guests can move between nodes with `--with-local-disks` migration.
- No shared VM-disk storage and no HA manager yet. That's a deliberate trade-off (see [ADR 0001](../adr/0001-cluster-plus-standalone-storage-node.md)).

## Standalone: Sefi

A lower-power node that is mainly the storage server (see [storage.md](storage.md)). It also runs the services that shouldn't share fate with the cluster: `dns2` and the `ops` VM.

## Guest standards

| Standard | Practice |
|---|---|
| VMIDs | Grouped by role: `1xx` desktops, `2xx` core/security, `3xx` apps, `4xx` Sefi-hosted, `9xxx` templates |
| Containers | Unprivileged LXC by default |
| VMs | VirtIO disk/NIC, QEMU guest agent enabled, cloud-init where supported |
| Templates | Golden images (e.g. `Kali-Master`, VMID 9000) on shared NFS so any node can clone them |
| Snapshots | Taken before risky changes. The lab VM `kali` keeps a `Clean` baseline snapshot |
| Critical guests | `onboot=1`; dns1 also has deletion protection enabled |
