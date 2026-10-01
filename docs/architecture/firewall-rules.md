# Firewall rules (Omada gateway ACLs)

**Status:** default-deny between VLANs is **enforced** as of 2026-09-30. All 29 original tests pass. The 2026-10-01 retests after the [agent-workstation move](../adr/0008-agent-workstation-in-management-bots-scoped.md) found and removed one undocumented rule (T36).

## Design
An allow-list with a default-deny at the bottom. Omada evaluates gateway ACLs top-down and the first match wins. Rules 1–9 permit specific flows, rule 10 isolates Guest, rule 11 blocks the gateway's own admin UI, and rule 12 denies everything else between VLANs. Management isn't in the deny rules' source lists, so it keeps full reach. The policy matrix is in [network.md](network.md#segmentation-policy).

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
| 9 | Dashboard → Mgmt APIs | Permit | TCP | IP group `Dashboard` | IP-Port group `Dashboard Targets` | Off |
| 10 | GUEST → RFC1918 | Deny | All | Guest | All other networks | On |
| 11 | DENY Gateway UI | Deny | **TCP** | Internal, IoT, Servers, Security, DMZ, Guest | Type: **Gateway Management Page** | On |
| 12 | DENY Inter-LAN | Deny | All | Internal, IoT, Guest, DMZ, Security, Servers | IP group `All VLAN` | On |

Rule 9 was added on 2026-09-30, after enabling default-deny broke homepage's status checks for the Omada controller and Technitium (see T20).

Rule 11 closes a gap LAN → LAN rules can't cover: traffic addressed to the gateway's *own* interface IPs (10.12.x.1) isn't routed between VLANs, so rule 12 never sees it. The "Gateway Management Page" destination type matches every packet sent to the gateway itself. It's limited to **TCP** because "All" would also block DNS and other traffic devices send to their gateway, and TP-Link users report losing internet access that way. The gateway is managed through the Omada controller (10.12.5.2) anyway.

Logging on the deny rules sends blocked traffic to the gateway log. Once gateway syslog reaches Splunk (roadmap Phase 3), denied connections out of the Security VLAN become detection data: lateral-movement attempts from the lab show up as firewall events.

## IP groups

Hosts listed by address have a static IP or a DHCP reservation, so their permissions stay tied to the host.

| Group | Type | Members | Used by |
|---|---|---|---|
| `Admin Terminals` | IP | Admin desktop (reserved IP) | Rule 1 |
| `DNS` | IP-Port | 10.12.5.53, 10.12.5.54 · port 53 | Rule 5 |
| `NFS` | IP-Port | 10.12.5.14 · port 2049 (NFSv4) | Rule 6 |
| `Proxmox Clients` | IP | 10.12.30.101 (`bots`, formerly `claude`), 10.12.30.100 (`homepage`). Both reserved | Rule 7 |
| `Dashboard` | IP | 10.12.30.100 (`homepage`) | Rule 9 |
| `Dashboard Targets` | IP-Port | 10.12.5.2 · 443 (Omada controller). 10.12.5.53, 10.12.5.54 · 5380 (Technitium API) | Rule 9 |
| `Proxmox Port` | IP-Port | 10.12.5.11, .12, .13, .14 · port 8006 | Rule 7 |
| `SIEM In` | IP-Port | 10.12.30.20 · port 9997. Add :8089 if a Splunk deployment server is used | Rule 8 |
| `All VLAN` | IP | 10.12.0.0/16 | Rule 12 |

`ops` (10.12.5.10) needs no group entries because it's in Management ([ADR 0005](../adr/0005-admin-hosts-in-management-zone.md)).

## Test results

"Before" was measured on 2026-09-29 with the default-deny rule disabled. "After" was measured on 2026-09-30 with default-deny enabled. Tests ran as TCP connects from the named host: `kali` (10.12.40.101, Security), `ops` (10.12.5.10, Management), `claude` (10.12.30.101, Servers; renamed `bots` on 2026-10-01, same IP and groups).

| # | From → To | Port | Expected | Before | After | Pass |
|---|---|---|---|---|---|---|
| T1 | kali → darrow / sefi Proxmox UI | 8006 | ❌ | 🔴 OPEN | BLOCKED | ✅ |
| T2 | kali → darrow SSH | 22 | ❌ | 🔴 OPEN | BLOCKED | ✅ |
| T3 | kali → dns1 admin UI | 5380 | ❌ | 🔴 OPEN | BLOCKED | ✅ |
| T4 | kali → dns1 DNS (TCP connect and real lookups) | 53 | ✅ | OPEN | OPEN, resolves internal and external names | ✅ |
| T5 | kali → ops SSH | 22 | ❌ | 🔴 OPEN | BLOCKED | ✅ |
| T6 | kali → gateway UI (10.12.5.1) | 443, 80 | ❌ | 🔴 OPEN | BLOCKED after rule 11 was added | ✅ |
| T7 | kali → gateway UI (10.12.40.1) | 443, 80 | ❌ | 🔴 OPEN | BLOCKED after rule 11 was added | ✅ |
| T8 | ops → kali (temporary listener) | 8080 | ✅ | n/a | HTTP 200. **Proves the ACLs are stateful** | ✅ |
| T9 | kali → homepage (Servers) | 3000 | ❌ | 🔴 OPEN | BLOCKED | ✅ |
| T10 | kali → internet | 443 | ✅ | OPEN | OPEN | ✅ |
| T11 | kali → Splunk forwarding | 9997 | ✅ | n/a | OPEN (rule 8) | ✅ |
| T12 | kali → Splunk web UI, mgmt API, SSH, PostgreSQL | 8000, 8089, 22, 5432 | ❌ | n/a | BLOCKED (rule 12 + ufw) | ✅ |
| T13 | claude → Proxmox API (darrow, sefi) | 8006 | ✅ | OPEN | OPEN | ✅ |
| T14 | claude → darrow SSH | 22 | ❌ | 🔴 OPEN | BLOCKED | ✅ |
| T15 | claude → dns1 admin UI | 5380 | ❌ | n/a | BLOCKED | ✅ |
| T16 | claude → ops SSH (Servers → Mgmt) | 22 | ❌ | n/a | BLOCKED | ✅ |
| T17 | claude → kali (Servers → Security) | 8080 | ❌ | n/a | BLOCKED | ✅ |
| T18 | kali → claude SSH (Security → Servers) | 22 | ❌ | n/a | BLOCKED | ✅ |
| T19 | ops → homepage, claude (Mgmt → Servers) | 3000, 22 | ✅ | n/a | OPEN | ✅ |
| T20 | homepage → Omada controller, Technitium API (homepage status checks) | 443, 5380 | ✅ | OPEN | Timed out after default-deny. **200 after rule 9 was added** | ✅ |
| T21 | claude → Omada controller, Technitium API (same VLAN, not in `Dashboard`) | 443, 5380 | ❌ | n/a | BLOCKED | ✅ |
| T22 | kali → Omada controller (10.12.5.2) | 443 | ❌ | n/a | BLOCKED | ✅ |
| T23 | claude → gateway UI (10.12.30.1, 10.12.5.1) | 443 | ❌ | n/a | BLOCKED | ✅ |
| T24 | kali and claude → internet and DNS, after rule 11 (regression check for the TCP-only choice) | 443, 53 | ✅ | OPEN | OPEN | ✅ |
| T25 | Internal devices that **aren't** the admin desktop (owner's phone and laptop) → Splunk web UI | 8000 | ❌ | n/a | BLOCKED (ufw) | ✅ |
| T26 | ops (Mgmt) → Splunk web UI | 8000 | ✅ | n/a | OPEN (redirects to login) | ✅ |
| T27 | ops (Mgmt) → Splunk forwarding | 9997 | ✅ | n/a | OPEN | ✅ |
| T28 | claude (Servers) → Splunk web UI | 8000 | ❌ | n/a | BLOCKED (ufw: Servers isn't an admin zone) | ✅ |
| T29 | claude (Servers) → Splunk forwarding | 9997 | ✅ | n/a | OPEN | ✅ |
| T30 | claude (Servers) → Splunk mgmt API | 8089 | ❌ | n/a | BLOCKED (ufw) | ✅ |

### Retests after the agent-workstation move (2026-10-01)
The admin work moved from `claude` (Servers) to `ops` (Management), 301 became `bots`, and `fantasy` (10.12.30.30) joined Servers with no IP group memberships ([ADR 0008](../adr/0008-agent-workstation-in-management-bots-scoped.md)). Same method: TCP connects, with timeouts telling gateway drops apart from host refusals.

| # | From → To | Port | Expected | Result | Pass |
|---|---|---|---|---|---|
| T31 | ops → darrow, sefi SSH (was T14 from claude) | 22 | ✅ | OPEN | ✅ |
| T32 | ops → dns1, dns2 admin UI (was T15/T21) | 5380 | ✅ | OPEN, HTTP 200 | ✅ |
| T33 | ops → Omada controller, gateway UI on 10.12.5.1 and 10.12.30.1 (was T21/T23) | 443 | ✅ | OPEN | ✅ |
| T34 | ops → Proxmox API on all four nodes | 8006 | ✅ | OPEN | ✅ |
| T35 | ops → Splunk web UI, SSH / mgmt API (was T28/T30) | 8000, 22 / 8089 | ✅ / ❌ | OPEN (303 to login), OPEN / BLOCKED (ufw, by design) | ✅ |
| T36 | fantasy (Servers, no groups) → Proxmox API, darrow SSH, dns1 admin UI | 8006, 22, 5380 | ❌ | 🔴 **OPEN on the first run.** An undocumented rule from 2026-09-30 ("claude → VLAN 5", with its own IP group) was still on the gateway. The owner deleted the rule and the group, and the rerun was BLOCKED (timeouts). Splunk confirms it: see below | ✅ after fix |
| T36b | fantasy → ops SSH, Omada controller, gateway UI; → Splunk forwarding; → internet and DNS | 22, 443 / 9997 / 443, 53 | ❌ / ✅ / ✅ | BLOCKED / OPEN / OPEN | ✅ |
| T37 | bots, fantasy → Splunk SSH (ufw no longer allows Servers); ops → Splunk SSH | 22 | ❌ / ✅ | BLOCKED (timeouts, ufw drop) / OPEN | ✅ |
| T38 | bots after the rename: T13, T14, T16, T21, T23, T28, T30 re-run from 10.12.30.101 | various | as before | Proxmox API OPEN (rule 7), everything else into Management BLOCKED | ✅ |

**T36 in Splunk** (`index=netfw src_ip=10.12.30.30`, local time). The undocumented rule had logging off, so the connections it allowed left no events. That's why the evidence is the *absence* of blocks:
- Before 12:01:25, no events from `fantasy` at all.
- 12:01:27–12:01:39: the four targets the first run reported as BLOCKED (ops :22, Omada :443, both gateway UIs), 4 s apart, matching the test's timeout. The targets it reported as OPEN (darrow :22, sefi :8006, dns1 :5380) have **no blocks until the reruns** (12:02:34, 12:04:43, 12:03:43).
- The owner deleted the rule during that first run. At 12:01:25–12:01:31 the gateway also blocked the tail of a darrow :8006 connection and a reply inside an `ops` → `fantasy` SSH session (ops port 42396). A stateful firewall only does that when its connection table is reset. **Pushing an ACL change resets live inter-VLAN sessions**, so ACL changes belong in a quiet window.

**A second undocumented rule** turned up in the old demarzo.dev notes: `claude` (301) → `dmz-edge` tcp/22, for site deploys. Deploys now run from `ops` (Management → DMZ, rule 2), so the owner removed it on 2026-10-01. Check: `bots` and `fantasy` → 10.12.50.10:22 time out.

**Lesson from T36:** the rules table above must match the gateway. Any gateway change gets recorded the same day, and every new guest gets a reachability check from its own address before it's considered done.

Not tested by me: rules 1, 3, and 4 start from the owner's personal devices, where I can't run tests.

## Planned changes (Splunk, roadmap Phase 3)
| Change | Reason |
|---|---|
| Rule 8 "Sec → SIEM": add **DMZ** to its source | `dmz-edge` forwarder → 10.12.30.20:9997. A single documented exception to DMZ isolation ([ADR 0007](../adr/0007-splunk-topology-and-household-data.md)) |
| Gateway → 10.12.30.20:514 (syslog) | ✅ Works with no ACL change. The ER605 sends from its Servers interface (10.12.30.1), so the traffic never crosses VLANs. The controller (10.12.5.2) and access point (10.12.5.200) are covered by rule 2 |
| New test **T25**: Internal (non-admin) → Splunk :8000 must be blocked | Rule 3 permits Internal → Servers, so the host firewall (ufw) on `splunk` does the blocking |

## Open items
- ✅ **Dashboard credentials** (resolved 2026-10-01): rule 9 makes homepage a pivot point, because it stores API credentials for Proxmox, Omada and Technitium and can reach all three. All of them are now read-only: Proxmox `PVEAuditor` tokens, the Omada `Viewer` role, and a Technitium `homepage` user with Dashboard view only. Before that, the Technitium keys were **admin** tokens on both servers.
- **Log injection:** Security can send to Splunk :9997, so a compromised lab host could forge log events. Accepted for the lab. Future hardening: forwarder TLS with client certificates.
