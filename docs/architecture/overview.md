# Architecture overview

## Design goals

1. **Look like an enterprise, run like a home.** Use the same patterns a small company would (segmentation, redundancy, backups, config management, monitoring) at a scale that doesn't need a full-time admin.
2. **No single box takes down core services.** DNS runs on both Proxmox environments. The cluster keeps quorum with one node down.
3. **Rebuildable.** Every guest comes from a template or a script, and every decision is written down.
4. **Safe to break things.** Offensive-security work happens on its own VLAN with snapshot-based resets.

## Components

| Layer | Component | Doc |
|---|---|---|
| Network | TP-Link Omada gateway, VLANs 5 / 30 / 40 | [network.md](network.md) |
| Compute | Proxmox cluster `TheRising` (darrow, ragnar, sevro) + standalone `Sefi` | [compute.md](compute.md) |
| Storage | Per-node ZFS for guest disks, `pax` ZFS pool on Sefi shared over NFS | [storage.md](storage.md) |
| Name resolution | Technitium DNS pair, zone `demarzo.lab` | [dns.md](dns.md) |

## Why two Proxmox environments?

`TheRising` is a 3-node cluster: three votes, so quorum survives one node going down. `Sefi` is kept out of the cluster on purpose. It holds bulk storage and the second DNS server, so a cluster-wide problem (lost quorum, a bad upgrade) doesn't take out storage or name resolution too. See [ADR 0001](../adr/0001-cluster-plus-standalone-storage-node.md).

## Current guests

See the generated [inventory](../inventory.md). In short:

| Guest | Role | Where |
|---|---|---|
| dns1 / dns2 | Internal DNS (Technitium) | sevro / sefi |
| ops | Headless admin jump box and agent workstation: Claude Code, herdr, the Proxmox MCP (Ubuntu 24.04, rebuilt 2026-09-30). Ansible/Terraform control node when that resumes ([ADR 0006](../adr/0006-soc-focus-with-splunk.md)) | sefi |
| ubuntu-2404-ci | Golden Ubuntu template (9001) for Splunk and future VMs | sevro (disk on pax) |
| dmz-edge | Internet-facing edge in the DMZ: Caddy + cloudflared (Cloudflare Tunnel) for demarzo.dev | sefi |
| splunk | SIEM: Splunk Enterprise (VMID 151, built from template 9001) | darrow |
| homepage | Lab dashboard | ragnar |
| bots | Discord Proxmox bot (scoped `discord-bot@pve` token) and the plan-usage feed for homepage. Formerly `claude`, the agent workstation | ragnar |
| fantasy | Dev/runtime host for the fantasy-app project (LXC 201) | sevro |
| kali / Kali-Master | Offensive-security VM and its golden template | sevro / darrow |
| Omarchy | Linux desktop VM (stopped) | darrow |
