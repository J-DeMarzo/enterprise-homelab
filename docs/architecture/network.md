# Network

## Edge

A **TP-Link Omada ER605** gateway routes between VLANs and to the internet. It has an address in each VLAN (`.1`) and enforces the inter-VLAN policy with gateway ACLs ([firewall-rules.md](firewall-rules.md)).

## VLAN plan

Subnets follow `10.12.<VLAN>.0/24`, so an address tells you its VLAN.

| VLAN | Network | Subnet | Purpose | Trust |
|---|---|---|---|---|
| 5 | Management (default) | 10.12.5.0/24 | Proxmox hosts, DNS, admin hosts | Highest. Reaches everything |
| 10 | Internal | 10.12.10.0/24 | Trusted personal devices | Trusted user devices |
| 20 | IoT | 10.12.20.0/24 | Smart-home and embedded devices | Untrusted |
| 30 | Servers | 10.12.30.0/24 | Workloads, dashboards, SIEM (planned) | Service zone |
| 40 | Security | 10.12.40.0/24 | Attack lab: Kali and deliberately vulnerable targets | **Hostile by design** |
| 50 | DMZ | 10.12.50.0/24 | Anything exposed to the internet | Untrusted |
| 99 | Guest | 10.12.99.0/24 | Visitor devices | Internet only |

Proxmox guests use VLANs 5 (untagged, native), 30 (`tag=30`), and 40 (`tag=40`).

## IP allocation

| Range | Use |
|---|---|
| `.1` | Gateway (every VLAN) |
| `10.12.5.2` | Omada controller |
| `10.12.5.10` | ops, the admin host (static, set by cloud-init) |
| `10.12.5.200` | Omada access point (syslog sender) |
| `10.12.5.11–.14` | Proxmox nodes (darrow `.11`, sevro `.12`, ragnar `.13`, sefi `.14`) |
| `10.12.5.53–.54` | DNS (dns1 `.53`, dns2 `.54`), named after port 53 |
| `10.12.30.20` | splunk (SIEM, static) |
| `10.12.30.30` | fantasy (fantasy-app dev/runtime, LXC 201, static) |
| `10.12.30.40` | llm (Ollama, LXC 100, static) |
| `10.12.40.10` | dc01 (lab AD domain controller `ad.demarzo.lab`, VM 152, static) |
| `10.12.50.10` | dmz-edge (Caddy + cloudflared for demarzo.dev) |
| `.100+` | DHCP leases (observed) |

Infrastructure that other things depend on gets static addresses. Any host named in a firewall IP group must have a static address or a DHCP reservation, otherwise its firewall permissions follow the IP address instead of the host.

## Host networking

Each Proxmox node has one NIC (`nic0`) bridged to `vmbr0`. Guests pick their VLAN with a tag on their virtual NIC, so a guest can move between VLANs without any host network change. Guest NICs have the Proxmox firewall flag enabled so per-guest rules can be added later.

## Segmentation policy

Default deny between VLANs, with explicit allows (Omada evaluates the rules top-down and the first match wins). Management and designated admin terminals reach everything. Other zones get only what they need:

| From ↓ / To → | Mgmt | Internal | IoT | Servers | Security | DMZ | Guest |
|---|---|---|---|---|---|---|---|
| **Management** | – | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Internal** | DNS | – | ❓ | ✅ | ❌ | ❌ | ❌ |
| **IoT** | DNS | ❌ | – | ❌ | ❌ | ❌ | ❌ |
| **Servers** | DNS, NFS, Proxmox API and dashboard APIs (listed hosts only) | ❌ | ❌ | – | ❌ | ❌ | ❌ |
| **Security** | DNS | ❌ | ❌ | SIEM :9997 only | – | ❌ | ❌ |
| **DMZ** | DNS | ❌ | ❌ | SIEM :9997 only | ❌ | – | ❌ |
| **Guest** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | – |

Admin terminals (an IP group) have full access, like Management. ❓ = optional rule 4 (Internal → IoT), see [firewall-rules.md](firewall-rules.md#rules-gateway-acl-lan--lan).

**Enforced since 2026-09-30.** Rules, IP groups, and the before/after test results are in [firewall-rules.md](firewall-rules.md).
