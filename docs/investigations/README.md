# Investigations

Case write-ups from the lab. Each one follows a simulated attack from detection to conclusion, the way a SOC analyst would document an incident.

**How each case is produced:**
1. **Emulate:** run a technique from Kali or [Atomic Red Team](https://github.com/redcanaryco/atomic-red-team) against a lab target on VLAN 40.
2. **Detect:** an SPL detection in [`detections/`](../../detections/) puts a hit in the Splunk alert queue.
3. **Investigate:** triage, scope, and build the timeline from Splunk data.
4. **Document:** fill in [`TEMPLATE.md`](TEMPLATE.md) and save it as `YYYY-MM-DD-short-name.md`.
5. **Improve:** tune the detection or add a new one, and link it from the case.

## Cases

| Date | Case | ATT&CK | Verdict |
|---|---|---|---|
| *No cases yet. The first ones come after Splunk and the AD targets are deployed ([roadmap](../roadmap.md)).* | | | |
