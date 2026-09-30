# Firewall rules (Omada gateway ACLs)

**Status:** the rules exist, but the default-deny rule (#9) is **disabled**, so inter-VLAN traffic is effectively unrestricted. IP groups are being corrected. Baseline measured 2026-09-29.

## Design
An allow-list with a default-deny at the bottom. Omada evaluates gateway ACLs top-down and the first match wins. Rules 1–8 permit specific flows, and rule 9 denies everything else between VLANs. Management isn't in rule 9's source list, so it keeps full reach. The policy matrix is in [network.md](network.md#segmentation-policy).

## Current rules (Gateway ACL, LAN → LAN)

| # | Name | Action | Protocol | Source | Destination | Enabled | Notes |
|---|---|---|---|---|---|---|---|
| 1 | Golden Ticket | Permit | All | IP group `Admin Terminals` | All networks | ✅ | Rename suggested: "Golden Ticket" is also a Kerberos attack name (T1558.001) |
| 2 | MGMT → ALL | Permit | All | Management | All other networks | ✅ | |
| 3 | INT → Servers | Permit | All | Internal | Servers | ✅ | |
| 4 | ALLOW DNS | Permit | TCP+UDP | Mgmt, Internal, IoT, Servers, Security, DMZ | IP group `DNS` | ✅ | ⚠️ **All ports**, not just 53, because the destination is an IP group, not an IP-Port group. Lets Security reach the Technitium admin UI (5380) |
| 5 | Servers → NFS | Permit | TCP+UDP | Servers | IP-Port group `NFS` | ✅ | |
| 6 | Allow Proxmox Access | Permit | TCP | IP group `Proxmox 8006` | IP-Port group `Proxmox Port` | ✅ | Logged |
| 7 | Sec → Servers | Permit | TCP | Security | IP-Port group `SIEM In` | ✅ | Splunk forwarding path |
| 8 | GUEST → RFC1918 | Deny | All | Guest | All internal networks | ✅ | |
| 9 | DENY Inter-LAN | Deny | All | Internal, IoT, Guest, DMZ, Security, Servers | IP group `All VLAN` | ❌ **Disabled** | The default-deny backstop. With it off, anything not matched above is allowed |

## IP groups: target definitions

Enter these in Omada under the IP group profiles. Hosts listed by address need a **static IP or DHCP reservation**.

| Group | Type | Members | Used by |
|---|---|---|---|
| `Admin Terminals` | IP | Your admin desktop (`demarzoDesk`, reserved IP) | Rule 1 |
| `DNS` → change to **IP-Port** | IP-Port | 10.12.5.53, 10.12.5.54 · port **53** | Rule 4 |
| `NFS` | IP-Port | 10.12.5.14 · port **2049** (NFSv4) | Rule 5 |
| `Proxmox 8006` | IP | 10.12.30.101 (`claude`, needs a reservation). Add 10.12.30.100 (`homepage`) only if its widgets query Proxmox | Rule 6 |
| `Proxmox Port` | IP-Port | 10.12.5.11, .12, .13, .14 · port **8006** | Rule 6 |
| `SIEM In` | IP-Port | 10.12.30.20 · port **9997** | Rule 7 |
| `All VLAN` | IP | 10.12.0.0/16 (all seven VLANs). Or all RFC 1918 ranges to also cover any upstream/ISP LAN | Rule 9 |

`ops` (10.12.5.10) needs no group entries because it's in Management ([ADR 0005](../adr/0005-admin-hosts-in-management-zone.md)).

## Change plan
1. Correct the IP groups (table above). Make rule 4's destination the `DNS` **IP-Port** group (port 53).
2. Reserve IPs for the admin desktop and `claude` (10.12.30.101).
3. Decide the [open decisions](#open-decisions).
4. **Enable rule 9.** Rollback is the same toggle.
5. Run the test plan below and record the results.

## Open decisions
- **Internal → IoT.** With rule 9 on, Internal devices can't start connections to IoT (casting to a TV, printing, a smart-home hub UI). If that's needed, add *Permit Internal → IoT* above rule 9. IoT → Internal stays blocked. Discovery protocols like mDNS don't cross VLANs anyway without a reflector.
- **Stateful ACLs.** If Omada's gateway ACLs are stateless on this firmware, rule 9 also drops the *replies* to permitted connections (e.g. Servers answering Internal under rule 3). Test T8 and T13 catch this.
- **Gateway self-access.** Traffic to the gateway's own IPs (10.12.x.1) may not be subject to LAN → LAN rules. If T6/T7 are still open, restrict the gateway's management access to Management.

## Baseline and test plan

"Before" was measured from `kali` (10.12.40.101, Security) on 2026-09-29 with rule 9 disabled.

| # | From → To | Port | Expected after | Before | After |
|---|---|---|---|---|---|
| T1 | kali → darrow Proxmox UI | 8006 | ❌ | 🔴 OPEN | |
| T2 | kali → darrow SSH | 22 | ❌ | 🔴 OPEN | |
| T3 | kali → dns1 admin UI | 5380 | ❌ | 🔴 OPEN | |
| T4 | kali → dns1 DNS | 53 | ✅ | OPEN | |
| T5 | kali → ops SSH | 22 | ❌ | 🔴 OPEN | |
| T6 | kali → gateway UI (10.12.5.1) | 443 | ❌ | 🔴 OPEN | |
| T7 | kali → gateway UI (10.12.40.1) | 443 | ❌ | 🔴 OPEN | |
| T8 | ops (Mgmt) → kali (temporary listener on 8080) | 8080 | ✅ | n/a | |
| T9 | kali → homepage (Servers) | 3000 | ❌ | 🔴 OPEN | |
| T10 | kali → internet | 443 | ✅ | OPEN | |
| T11 | kali → Splunk (once deployed) | 9997 | ✅ | n/a | |
| T12 | kali → Splunk web UI (once deployed) | 8000 | ❌ | n/a | |
| T13 | claude (Servers) → Proxmox API | 8006 | ✅ | OPEN | |
| T14 | claude (Servers) → darrow SSH | 22 | ❌ | 🔴 OPEN | |
