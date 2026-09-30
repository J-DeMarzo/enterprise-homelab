# 0002. Technitium DNS pair split across failure domains

- **Status:** Accepted
- **Date:** 2026-09-29 (written after the fact)

## Context
Internal name resolution (`demarzo.lab`) is needed by everything: hypervisors, guests, automation. If DNS is down, the lab looks down even when every service is running. Enterprise environments always run at least two DNS servers.

## Decision
- Run **Technitium DNS Server** in two small unprivileged LXCs: `dns1` (10.12.5.53) on the cluster and `dns2` (10.12.5.54) on standalone sefi.
- Put both on the management VLAN with static IPs, and hand both to every client.

Technitium was chosen over Pi-hole/AdGuard because it's a full authoritative server (zones, zone transfers, DNSSEC) as well as a recursive resolver, and it has a web UI and an API. It's closer to what enterprise DNS does, but light enough for a 512 MiB container.

## Consequences
- ✅ DNS survives losing any single host, including the whole cluster or all of sefi.
- ✅ Each server needs only about 512 MiB of RAM.
- ❌ Keeping the two servers in sync has to be set up and checked (see open items in [dns.md](../architecture/dns.md)).
- ❌ It isn't integrated with DHCP, so dynamic guests don't get DNS records automatically.
