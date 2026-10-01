# 0009. Least-privilege Proxmox API identities

- **Status:** Accepted
- **Date:** 2026-10-01

## Context
Automation reaches Proxmox through API tokens. Until 2026-10-01 there was one: `claude-mcp@pve!mcp`, with the built-in **PVEAdmin** role on `/` in both environments. It was used by the agent workstation and by the Discord bot. PVEAdmin is "everything except permissions": it can create users and tokens, define storage, allocate SDN, and open a root shell on any node (`Sys.Console`). That token then showed up in a session transcript and had to be rotated. A single broad credential shared by two programs is the textbook case for least privilege.

The other API consumer, homepage's dashboard, already uses a separate `PVEAuditor` token.

## Decision
One identity per consumer, each with a role cut to what it does:

| Identity | Used by | Role (on `/`, both environments) | Can't |
|---|---|---|---|
| `claude-mcp@pve!ops` | Agent workstation on `ops` ([ADR 0008](0008-agent-workstation-in-management-bots-scoped.md)) | **`OpsAgent`** (custom, 27 privileges): audit everything; build, configure, clone, migrate, power, snapshot, back up and roll back guests; run guest-agent commands; use storage space and upload ISOs and templates; attach NICs (`SDN.Use`) | Manage users, groups, realms, tokens or pools; define or remove storage; use node shells or VM consoles; allocate SDN; replicate |
| `discord-bot@pve!bot` | Discord bot on `bots` | `PVEAuditor` + **`DiscordBot`** (`VM.PowerMgmt`, `VM.Snapshot`, `Sys.Syslog`) | Change any config, delete, roll back, clone, or run commands in guests |
| `services@pam!Homepage` | homepage dashboard | `PVEAuditor` | Change anything |

Custom roles and ACLs are created by root in the node's web UI shell. No API token holds `Permissions.Modify`, `Sys.Modify` or `User.Modify`, so **no token can widen its own access or create new tokens.**

## Consequences
- ✅ A leaked `ops` token can still damage guests, but it can't create a persistent backdoor (a new user or token), change storage definitions, or get a root shell on a node.
- ✅ Dropping `Datastore.Allocate` also blocks API deletes of other owners' volumes on NFS storage, the action behind [INC-2026-001](../incidents/2026-09-30-darrow-nfs-stale-handle.md).
- ❌ Creating tokens and users now always takes the owner, as root. That's intended: it's rare and high-impact.
- ❌ `VM.Allocate` and `VM.GuestAgent.Unrestricted` remain powerful (delete guests, run anything inside VMs). Splitting them per path (for example `/vms/9xxx` for templates only) is possible but not worth the complexity at this size. Critical guests rely on Proxmox's deletion protection instead.
- ⚠️ If a needed privilege is missing, the API answers 403 naming it, and it's a one-line `pveum role modify`.

## Verification (2026-10-01)
| Check | Result |
|---|---|
| Effective privileges of `claude-mcp@pve` on `/`, both environments | Exactly the 27 in `OpsAgent`. PVEAdmin removed |
| Normal work: `scripts/inventory.py`, MCP listings, snapshot listing, a Notes write | All OK. The inventory matches the committed one |
| Dropped privilege: re-setting a user's comment (`User.Modify`) | `403 Permission check failed (/access/groups, User.Modify)` |
| Bot token: a config write | `403` ([ADR 0008](0008-agent-workstation-in-management-bots-scoped.md)) |

Role definition, as run on darrow (cluster) and sefi:
```
pveum role add OpsAgent --privs "VM.Audit,Datastore.Audit,Sys.Audit,Sys.Syslog,SDN.Audit,Pool.Audit,Mapping.Audit,VM.Allocate,VM.Clone,VM.Config.CDROM,VM.Config.CPU,VM.Config.Cloudinit,VM.Config.Disk,VM.Config.HWType,VM.Config.Memory,VM.Config.Network,VM.Config.Options,SDN.Use,VM.PowerMgmt,VM.Migrate,VM.Snapshot,VM.Snapshot.Rollback,VM.Backup,VM.GuestAgent.Audit,VM.GuestAgent.Unrestricted,Datastore.AllocateSpace,Datastore.AllocateTemplate"
pveum acl modify / --users claude-mcp@pve --roles OpsAgent
pveum acl delete / --users claude-mcp@pve --roles PVEAdmin
```
