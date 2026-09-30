# Detections

SPL detections for the lab's Splunk instance, one file per detection, named `<tactic>-<short-name>.spl`.

Each file starts with a header:

````spl
``` Name:        Password spraying against AD
    ATT&CK:      T1110.003
    Data:        index=wineventlog EventCode=4625 / 4771
    Schedule:    every 15m over last 15m
    Severity:    medium
    Tested with: Atomic T1110.003-1 (see linked case)
    False positives: service accounts with stale passwords ```
index=wineventlog ...
| collect index=soc_alerts marker="detection=pw_spray, severity=medium, attack=T1110.003"
````

The final `collect` writes hits to the `soc_alerts` summary index, which feeds the Alert Queue dashboard. That's the Splunk Free replacement for alerting ([ADR 0006](../docs/adr/0006-soc-focus-with-splunk.md)).

A detection is only added here once it has **fired against a real emulated attack**, with the matching case in [`docs/investigations/`](../docs/investigations/).

| Detection | ATT&CK | Tested | Case |
|---|---|---|---|
| *None yet* | | | |
