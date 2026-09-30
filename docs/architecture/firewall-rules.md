# Firewall rules: security lab isolation (VLAN 40)

**Status:** Designed, not yet applied. Baseline measured 2026-09-29.

## Why
VLAN 40 is where attacks happen: Kali today, and soon deliberately vulnerable Windows/AD targets. A compromised or misconfigured lab host must not be able to reach the hypervisors, the core services, or the rest of the home network.

**The baseline test shows VLAN 40 is not isolated today.** From `kali` (10.12.40.101), before any rules:

| Target | Port | Result |
|---|---|---|
| Proxmox web UI, darrow / sefi | 8006 | 🔴 OPEN |
| Proxmox SSH, darrow | 22 | 🔴 OPEN |
| Technitium admin UI, dns1 | 5380 | 🔴 OPEN |
| ops SSH | 22 | 🔴 OPEN |
| Gateway admin UI (10.12.5.1 and 10.12.40.1) | 443 | 🔴 OPEN |
| homepage (VLAN 30) | 3000 | 🔴 OPEN |
| dns1 DNS | 53 | OPEN (intended) |
| Internet | 443 | OPEN (intended) |

## Design
- **Default for the lab:** deny all traffic to internal networks, allow the internet (updates, Windows evaluation activation, realistic C2/exfil exercises).
- **Narrow exceptions only**, each with a reason:
  - **DNS to dns1/dns2 (53).** Lab DNS goes through the central resolvers so DNS query logs land in Splunk, the way enterprise clients use corporate DNS. The Technitium admin UI (5380) stays blocked.
  - **Splunk forwarding (9997) to the Splunk server.** Endpoint telemetry has to reach the SIEM. Added when Splunk is deployed.
- **Management → lab stays open** so admins and the SIEM can reach lab hosts.

## Rule set (Omada Gateway ACL, LAN → LAN)

Omada evaluates ACL rules top-down and the first match wins, so the order matters. Create these **IP groups** first:

| IP group | Members |
|---|---|
| `LAB` | 10.12.40.0/24 |
| `DNS-SERVERS` | 10.12.5.53, 10.12.5.54 |
| `SIEM` | 10.12.30.20 (planned Splunk server) |
| `RFC1918` | 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 |

| # | Action | Source | Destination | Protocol / port | Purpose |
|---|---|---|---|---|---|
| 1 | Permit | `LAB` | `DNS-SERVERS` | UDP+TCP 53 | Name resolution via central, logged DNS |
| 2 | Permit | `LAB` | `SIEM` | TCP 9997 | Universal Forwarder → Splunk *(add once Splunk exists)* |
| 3 | Deny | `LAB` | `RFC1918` | All | Everything else internal: management, services, home LAN |

Traffic not matched (lab → internet) is allowed by default.

**Things to check in Omada while applying:**
- **Stateful or stateless ACL.** If Omada's gateway ACL isn't stateful, rule 3 also drops the *replies* to connections that management opens into the lab, so management → lab would break. Test T8 below catches this. If it fails, enable the stateful option on the rule if your firmware has one.
- **Gateway self-access.** Traffic to the gateway's own IPs (10.12.40.1, 10.12.5.1) may not go through LAN → LAN rules. If T6/T7 are still open afterwards, restrict the gateway's management access (the allowed-management-networks setting) to VLAN 5.

## Test plan

Run from `kali` after applying. Evidence is the before/after table, committed here.

| # | From → To | Port | Expected | Before | After |
|---|---|---|---|---|---|
| T1 | kali → darrow Proxmox UI | 8006 | ❌ blocked | OPEN | |
| T2 | kali → darrow SSH | 22 | ❌ blocked | OPEN | |
| T3 | kali → dns1 admin UI | 5380 | ❌ blocked | OPEN | |
| T4 | kali → dns1 DNS | 53 | ✅ allowed | OPEN | |
| T5 | kali → ops SSH | 22 | ❌ blocked | OPEN | |
| T6 | kali → gateway UI (10.12.5.1) | 443 | ❌ blocked | OPEN | |
| T7 | kali → gateway UI (10.12.40.1) | 443 | ❌ blocked | OPEN | |
| T8 | ops/claude → kali (temporary `python3 -m http.server 8080` on kali) | 8080 | ✅ allowed | n/a | |
| T9 | kali → homepage | 3000 | ❌ blocked | OPEN | |
| T10 | kali → internet | 443 | ✅ allowed | OPEN | |
| T11 | kali → Splunk (once deployed) | 9997 | ✅ allowed | n/a | |
| T12 | kali → Splunk web UI (once deployed) | 8000 | ❌ blocked | n/a | |
