# DNS

## Design

| Server | Host | IP | Software |
|---|---|---|---|
| dns1 | LXC 200 on sevro (TheRising) | 10.12.5.53 | Technitium DNS Server |
| dns2 | LXC 400 on sefi (standalone) | 10.12.5.54 | Technitium DNS Server |

- **Internal zone:** `demarzo.lab`. dns1 is primary (SOA `mname`). Both servers answer for the zone with the same SOA serial.
- **Split across failure domains:** one server runs on the cluster and one on the standalone node. Losing the whole cluster or all of Sefi still leaves working DNS. See [ADR 0002](../adr/0002-technitium-dns-pair.md).
- **Clients** get both servers (`10.12.5.53`, `10.12.5.54`) and the search domain `demarzo.lab`. The `ops` VM and the Ubuntu template set both through cloud-init.
- **Recursion:** both servers resolve external names for lab clients.
- **Admin UI:** Technitium web console on port 5380 on each server.
- **Query logging:** on (Settings → Logging, "Log All Queries", UTC), written to `/var/log/technitium/dns/<date>.log` and shipped to Splunk (`index=dns`) by a Universal Forwarder on each server, with household privacy filtering ([siem.md](siem.md)).

## Zone sync (dns1 → dns2)

dns1 is the only server where zones are edited. dns2 follows it through a **catalog zone** (RFC 9432):
- `catalog.demarzo.lab` on dns1 lists the member zones: `demarzo.lab`, `5.12.10.in-addr.arpa`, `30.12.10.in-addr.arpa`. dns2 is a secondary for the catalog, so a zone added to the catalog appears on dns2 without touching dns2.
- Member zones inherit the catalog's transfer settings: **zone transfers are allowed only to 10.12.5.54** (dns2). Anyone else gets `Transfer failed`.
- The catalog **notifies dns2** on every change. Measured: a new record was served by dns2 about 10 s after it was added on dns1. Without notify, dns2 only picks changes up on its SOA refresh (900 s). New *zones* in the catalog appear on dns2 at its next catalog check (every 5 min).
- ⚠️ Member zones also inherit the catalog's **Query Access**. Leave it at **Allow**. If it's restricted, every member zone starts refusing clients on both servers.
- To check sync, compare the SOA serial on both servers (see the [runbook](../runbooks/add-dns-record.md)).

Found and fixed on 2026-10-01: `30.12.10.in-addr.arpa` (VLAN 30 reverse lookups) existed only on dns1 because it had never been added to the catalog. Catalog notify was off, so dns2 lagged by up to 15 minutes. While notify was being set in the console, the dns2 address briefly landed in the catalog's Query Access field. For a few minutes both servers returned REFUSED for all internal names (internet lookups were unaffected), until Query Access was set back to Allow.

## Records

**`demarzo.lab`.** SOA and NS: `dns1.demarzo.lab`, `dns2.demarzo.lab`.

| Name | Type | Value | PTR |
|---|---|---|---|
| gw | A | 10.12.5.1 | ✅ |
| ops | A | 10.12.5.10 | ✅ |
| darrow | A | 10.12.5.11 | ✅ |
| sevro | A | 10.12.5.12 | ✅ |
| ragnar | A | 10.12.5.13 | ✅ |
| sefi | A | 10.12.5.14 | ✅ |
| dns1 | A | 10.12.5.53 | ✅ |
| dns2 | A | 10.12.5.54 | ✅ |
| splunk | A | 10.12.30.20 | ✅ |
| fantasy | A | 10.12.30.30 | ✅ |
| llm | A | 10.12.30.40 | ✅ |
| homepage | A | 10.12.30.100 | (PTR is `dashboard`) |
| dashboard | A | 10.12.30.100 | ✅ |
| bots | A | 10.12.30.101 | ✅ |
| dc01 | A | 10.12.40.10 | no reverse zone for Security. The AD domain `ad.demarzo.lab` itself is served by dc01, not Technitium |
| dmz-edge | A | 10.12.50.10 | no reverse zone for the DMZ |

## API access

**Technitium's built-in "Everyone" group** includes every user implicitly and, by default, can *view* Logs, Cache, DNS Client, Allowed, Blocked and Apps. A brand-new "read-only" user can therefore download the raw query logs: every client's lookups, before the household privacy filter in Splunk. On both servers, "Everyone" has been removed from those sections (2026-10-01). Non-admin users get only what's granted to them by name.

| User | Server | Can | Used by |
|---|---|---|---|
| `admin` | both | everything | owner, console only |
| `ops` | dns1 | View + Modify on the four zones | `ops` (API) |
| `homepage` | both | Dashboard: View | homepage's DNS widgets |


Changes can be made through the Technitium API from `ops` with a dedicated user, **`ops`**. It isn't an administrator: it has the Zones section plus View + Modify on the four zones above. It can add and update records, but **can't delete them**, because Technitium requires the zone's Delete permission even for single records. Its token lives on `ops` at `~/.config/technitium/dns1.token` (mode 600) and is never committed. Zone *options* (catalog membership, notify, transfer ACLs) need an administrator in the console.

Procedure: [runbooks/add-dns-record.md](../runbooks/add-dns-record.md)
