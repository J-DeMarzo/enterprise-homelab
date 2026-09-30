# 0006. Focus the lab on SOC work, with Splunk as the SIEM

- **Status:** Accepted
- **Date:** 2026-09-29

## Context
The lab's purpose is a portfolio for moving into cybersecurity, specifically SOC analyst work. What shows SOC readiness is **the workflow**: an alert fires, it gets triaged, investigated, documented, and the detection gets improved. Infrastructure automation (Ansible, Terraform) is useful but doesn't show that.

Two SIEMs were considered:

| | Wazuh | Splunk |
|---|---|---|
| Cost | Free, all features | Free tier (500 MB/day, **no alerting, no auth**). 60-day Enterprise trial. Developer license (10 GB/day, manual approval) |
| Out of the box | Agents, detection rules, FIM, vulnerability scanning, ATT&CK mapping | A search platform. Detections are written in SPL |
| Job-market relevance | Growing, common in smaller shops | Among the most-listed SIEMs in SOC job postings |

## Decision
- **The roadmap is driven by SOC workflow evidence.** Ansible and Terraform are on hold.
- **The SIEM is Splunk Enterprise.** Wazuh has more built in, but Splunk puts practice time into the tool most likely to be used on the job, and writing detections in SPL is itself the skill being shown.
- **Licensing path:** start on the 60-day Enterprise trial (real alerts, trigger conditions, throttling), then move to **Splunk Free**. On Free, alerting is replaced with a homemade alert queue: scheduled detection searches write hits to a summary index (`soc_alerts`), and analysts triage from a dashboard. Scheduled searches for dashboards and summary indexing are still allowed on Free. This mirrors how Splunk Enterprise Security's notable-event pipeline works.
- **Victims:** a small Active Directory (a DC plus a Windows 11 client) on the lab VLAN, with Sysmon and the Splunk Universal Forwarder.

## Consequences
- ✅ Hands-on SPL, data onboarding (forwarders, sourcetypes, indexes), and dashboard building. All of it maps directly to job requirements.
- ✅ The Free-tier alert queue is an extra, explainable design piece.
- ❌ Detections have to be written, not switched on. Mitigated by Splunk Security Essentials (free, ATT&CK-mapped examples).
- ❌ **Splunk Free has no authentication.** Anyone who can reach the web UI is admin, so the UI has to be network-restricted ([firewall rules](../architecture/firewall-rules.md)).
- ❌ The 500 MB/day limit on Free means Windows/Sysmon logging has to be filtered. Three overages in 30 days disables search.
- ❌ Evaluation Windows licenses expire (Server 180 days, Windows 11 90 days), so targets get rebuilt from templates on a schedule.
