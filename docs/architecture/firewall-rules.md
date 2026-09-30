# Firewall rules (Omada gateway ACLs)

**Status:** default-deny between VLANs is **enforced** as of 2026-09-30. 16 of 18 tests pass. The 2 failures are the gateway's own admin UI, which LAN → LAN ACLs don't cover (see [open items](#open-items)).

## Design
An allow-list with a default-deny at the bottom. Omada evaluates gateway ACLs top-down and the first match wins. Rules 1–8 permit specific flows, rule 9 isolates Guest, and rule 10 denies everything else between VLANs. Management isn't in rule 10's source list, so it keeps full reach. The policy matrix is in [network.md](network.md#segmentation-policy).

**The ACLs are stateful** (verified by T8): replies to permitted connections are allowed back, so a deny on A → B doesn't break connections that B starts to A.

## Rules (Gateway ACL, LAN → LAN)

| # | Name | Action | Protocol | Source | Destination | Log |
|---|---|---|---|---|---|---|
| 1 | Admin Terminals → ALL | Permit | All | IP group `Admin Terminals` | All 7 networks | Off |
| 2 | MGMT → ALL | Permit | All | Management | Internal, IoT, Servers, Security, DMZ, Guest | Off |
| 3 | INT → Servers | Permit | All | Internal | Servers | Off |
| 4 | INT → IoT *(optional)* | Permit | All | Internal | IoT | Off |
| 5 | ALLOW DNS | Permit | TCP+UDP | Mgmt, Internal, IoT, Servers, Security, DMZ | IP-Port group `DNS` (:53) | Off |
| 6 | Servers → NFS | Permit | TCP+UDP | Servers | IP-Port group `NFS` | Off |
| 7 | Allow Proxmox Access | Permit | TCP | IP group `Proxmox Clients` | IP-Port group `Proxmox Port` | On |
| 8 | Sec → SIEM | Permit | TCP | Security | IP-Port group `SIEM In` | Off |
| 9 | GUEST → RFC1918 | Deny | All | Guest | All other networks | On |
| 10 | DENY Inter-LAN | Deny | All | Internal, IoT, Guest, DMZ, Security, Servers | IP group `All VLAN` | On |

Logging on the deny rules sends blocked traffic to the gateway log. Once gateway syslog reaches Splunk (roadmap Phase 3), denied connections out of the Security VLAN become detection data: lateral-movement attempts from the lab show up as firewall events.

## IP groups

Hosts listed by address have a static IP or a DHCP reservation, so their permissions stay tied to the host.

| Group | Type | Members | Used by |
|---|---|---|---|
| `Admin Terminals` | IP | Admin desktop (reserved IP) | Rule 1 |
| `DNS` | IP-Port | 10.12.5.53, 10.12.5.54 · port 53 | Rule 5 |
| `NFS` | IP-Port | 10.12.5.14 · port 2049 (NFSv4) | Rule 6 |
| `Proxmox Clients` | IP | 10.12.30.101 (`claude`, reserved) | Rule 7 |
| `Proxmox Port` | IP-Port | 10.12.5.11, .12, .13, .14 · port 8006 | Rule 7 |
| `SIEM In` | IP-Port | 10.12.30.20 · port 9997. Add :8089 if a Splunk deployment server is used | Rule 8 |
| `All VLAN` | IP | 10.12.0.0/16 | Rule 10 |

`ops` (10.12.5.10) needs no group entries because it's in Management ([ADR 0005](../adr/0005-admin-hosts-in-management-zone.md)).

## Test results

"Before" was measured on 2026-09-29 with the default-deny rule disabled. "After" was measured on 2026-09-30 with rule 10 enabled. Tests ran as TCP connects from the named host: `kali` (10.12.40.101, Security), `ops` (10.12.5.10, Management), `claude` (10.12.30.101, Servers).

| # | From → To | Port | Expected | Before | After | Pass |
|---|---|---|---|---|---|---|
| T1 | kali → darrow / sefi Proxmox UI | 8006 | ❌ | 🔴 OPEN | BLOCKED | ✅ |
| T2 | kali → darrow SSH | 22 | ❌ | 🔴 OPEN | BLOCKED | ✅ |
| T3 | kali → dns1 admin UI | 5380 | ❌ | 🔴 OPEN | BLOCKED | ✅ |
| T4 | kali → dns1 DNS (TCP connect and real lookups) | 53 | ✅ | OPEN | OPEN, resolves internal and external names | ✅ |
| T5 | kali → ops SSH | 22 | ❌ | 🔴 OPEN | BLOCKED | ✅ |
| T6 | kali → gateway UI (10.12.5.1) | 443 | ❌ | 🔴 OPEN | 🔴 OPEN | ❌ |
| T7 | kali → gateway UI (10.12.40.1) | 443 | ❌ | 🔴 OPEN | 🔴 OPEN | ❌ |
| T8 | ops → kali (temporary listener) | 8080 | ✅ | n/a | HTTP 200. **Proves the ACLs are stateful** | ✅ |
| T9 | kali → homepage (Servers) | 3000 | ❌ | 🔴 OPEN | BLOCKED | ✅ |
| T10 | kali → internet | 443 | ✅ | OPEN | OPEN | ✅ |
| T11 | kali → Splunk forwarding | 9997 | ✅ | n/a | *Pending Splunk deployment* | – |
| T12 | kali → Splunk web UI | 8000 | ❌ | n/a | *Pending Splunk deployment* | – |
| T13 | claude → Proxmox API (darrow, sefi) | 8006 | ✅ | OPEN | OPEN | ✅ |
| T14 | claude → darrow SSH | 22 | ❌ | 🔴 OPEN | BLOCKED | ✅ |
| T15 | claude → dns1 admin UI | 5380 | ❌ | n/a | BLOCKED | ✅ |
| T16 | claude → ops SSH (Servers → Mgmt) | 22 | ❌ | n/a | BLOCKED | ✅ |
| T17 | claude → kali (Servers → Security) | 8080 | ❌ | n/a | BLOCKED | ✅ |
| T18 | kali → claude SSH (Security → Servers) | 22 | ❌ | n/a | BLOCKED | ✅ |
| T19 | ops → homepage, claude (Mgmt → Servers) | 3000, 22 | ✅ | n/a | OPEN | ✅ |

Not tested by me: rules 1, 3, and 4 start from the owner's personal devices, where I can't run tests.

## Open items
- **Gateway admin UI reachable from the Security VLAN (T6, T7).** Traffic to the gateway's own addresses isn't routed between VLANs, so LAN → LAN ACLs don't apply to it. Fix: restrict the gateway's management access to the Management network (and Admin Terminals) in the Omada controller, then rerun T6/T7.
- **T11/T12** once Splunk is deployed at 10.12.30.20.
- **Log injection:** Security can send to Splunk :9997, so a compromised lab host could forge log events. Accepted for the lab. Future hardening: forwarder TLS with client certificates.
