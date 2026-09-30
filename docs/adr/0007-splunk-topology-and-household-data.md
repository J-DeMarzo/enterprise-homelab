# 0007. Splunk topology and household data

- **Status:** Accepted
- **Date:** 2026-09-30

## Context
Splunk (ADR 0006) has to provide visibility across seven VLANs. Four of them hold infrastructure and lab systems the lab controls: Management, Servers, Security, DMZ. Three hold household devices: Internal (personal devices), IoT (smart-home devices), and Guest (visitors). Agents can't be installed on IoT devices and shouldn't be on household devices. DNS query logs are among the best security data available, but for household zones they amount to a record of everyone's browsing.

## Decision
1. **A single indexer in the Servers zone** (10.12.30.20). Not a sensor in each VLAN.
2. **Chokepoint-first visibility.** The Omada gateway/controller and Technitium DNS are onboarded first, because they observe all seven zones without any agents.
3. **Agents only where the lab owns the host:** infrastructure, the Security lab, and the DMZ (`dmz-edge`).
4. **Zone enrichment** with a CIDR lookup, so trust-boundary detections ("Security → Management", "new device on Management") work on any data source.
5. **Household DNS minimization at index time.** Internal and Guest queries are indexed only when they failed or were blocked. IoT DNS is indexed in full: its traffic is machine-generated, and it's the best way to spot a compromised device.
6. **The DMZ gets one outbound exception:** `dmz-edge` → Splunk TCP 9997 (gateway ACL rule 8). This is a single, documented hole in the otherwise isolated DMZ.

## Consequences
- ✅ All seven VLANs are visible from day one with zero agents on household devices, the same pattern enterprises use for unmanaged and IoT devices.
- ✅ Household browsing never lands in the SIEM or in public portfolio screenshots. Data minimization is a deliberate, explainable design choice.
- ✅ Dropping routine household DNS also saves license volume on the 500 MB/day Free tier.
- ❌ The household filter hides one class of signal: a compromised Internal device resolving a real (successful) malicious domain won't show up in DNS. It would still show up in firewall denies, and the filter can be relaxed temporarily during an investigation.
- ❌ Visibility inside a VLAN (host-to-host on the same switch) isn't covered. That would need network security monitoring (Zeek via port mirroring), which is on the roadmap as optional.
- ❌ The DMZ → Servers:9997 exception means a compromised `dmz-edge` could send forged log events. Accepted for now; mitigation later is forwarder TLS with client certificates.
