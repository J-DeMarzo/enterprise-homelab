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
| VMIDs | The hundreds digit says **where a guest lives**: `1xx` darrow, `2xx` sevro, `3xx` ragnar, `4xx` sefi. Within each node, `x00–x49` are LXCs and `x50–x99` are VMs, so `201` reads as "sevro, container" at a glance. Templates are `9xxx`. Take the next free number in the range ([exceptions](#vmid-exceptions)) |
| Containers | Unprivileged LXC by default |
| VMs | VirtIO disk/NIC, QEMU guest agent enabled, cloud-init where supported |
| Templates | Golden images (`9xxx`) stored on `VM-Templates` (NFS from pax) so any cluster node can clone them. **Always full-cloned to `fast-local` on the template's node, then migrated** to the target node ([runbook](../runbooks/deploy-guest-from-template.md)). Proxmox can't clone directly to another node's local storage, and linked clones would have to stay on NFS, so running VMs would depend on Sefi |
| Snapshots | Taken before risky changes. The lab VM `kali` keeps a `Clean` baseline snapshot |
| Critical guests | `onboot=1`; dns1 also has deletion protection enabled |
| Notes | Every guest has a Markdown **Notes** card in the Proxmox UI (see below) |

### VMID exceptions

Guests that predate the scheme and still need a new number:

| Guest | Now | Should be | Plan |
|---|---|---|---|
| splunk | 210 (VM on darrow) | 151 | Renumber in a maintenance window (backup, then restore as 151) |
| dmz-edge | 500 (LXC on sefi) | 401 | Not yet scheduled |

## Tag scheme

Every guest has exactly two tags. They show up as colored chips in the Proxmox tree and can be filtered on.

**Role: what the guest does**

| Tag | Meaning | Test |
|---|---|---|
| `infra` | Core services everything else depends on | If it's down, other things break |
| `admin` | Hosts the lab is managed *from* | If it's down, nothing breaks, but nothing can be fixed or automated |
| `app` | Things people use, built on top of infra | If it's down, it's just inconvenient |
| `lab` | Disposable security-exercise machines | Safe to wreck and roll back |
| `template` | Golden images, never run directly | Clone, don't modify |
| `desktop` | Interactive workstations | |

**Zone: which VLAN it lives on:** `net-mgmt` (5), `net-svc` (30), `net-lab` (40), `net-dmz` (50)

| Guest | Role | Zone |
|---|---|---|
| dns1, dns2 | `infra` | `net-mgmt` |
| ops | `admin` | `net-mgmt` |
| bots | `admin` | `net-svc` |
| homepage | `app` | `net-svc` |
| fantasy | `app` | `net-svc` |
| dmz-edge | `app` | `net-dmz` |
| splunk | `infra` | `net-svc` |
| kali, Kali-Master | `lab` | `net-lab` |
| ubuntu-2404-ci (9001) | `template` | `net-svc` (default for clones) |
| Omarchy | `desktop` | `net-svc` |

## Guest notes standard

Every guest's Notes field (the `description` config key) follows the same layout, so anyone opening a guest in the Proxmox UI sees what it is, who owns it, and where it's documented:

```markdown
### <name> · <short role>

| | |
|---|---|
| **Role** | What it does |
| **Service** | Software, and its URL if it has one |
| **Network** | VLAN n (Name) · IP static/DHCP |
| **Protection** | Start on boot · deletion protection (if set) |
| **Owner** | demarzo |

Docs: <link to the relevant page in this repo>
```

Include only the rows that apply. Templates also get a clone command, and lab VMs get their scope and reset procedure.
