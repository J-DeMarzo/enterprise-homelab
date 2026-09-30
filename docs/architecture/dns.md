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

## Records

| Name | Type | Value |
|---|---|---|
| darrow | A | 10.12.5.11 |
| sevro | A | 10.12.5.12 |
| ragnar | A | 10.12.5.13 |
| sefi | A | 10.12.5.14 |
| dns1 | A | 10.12.5.53 |
| dns2 | A | 10.12.5.54 |

## Open items (roadmap Phase 1)

- Add records for `ops` (10.12.5.10), `homepage`, and the gateway (`gw`).
- The zone's NS record is the unqualified name `dns1.` and doesn't list dns2. Change it to `dns1.demarzo.lab` and `dns2.demarzo.lab`, with matching glue records.
- Write down how dns2 gets the zone (secondary zone transfer vs. separate copy) and check that it stays in sync after a change.

Procedure: [runbooks/add-dns-record.md](../runbooks/add-dns-record.md)
