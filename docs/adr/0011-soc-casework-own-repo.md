# 0011. SOC case work moves to its own repo; Splunk and detections stay here

- **Status:** Accepted
- **Date:** 2026-10-25

## Context
The case write-ups from Phase 5 are the main evidence for a SOC analyst role ([ADR 0006](0006-soc-focus-with-splunk.md)). In this repo they would sit in `docs/investigations/`, behind the architecture docs, ADRs, and runbooks. Someone hiring for a SOC role gives a repo about a minute, and should land on cases, not VLANs. The infrastructure work is evidence in its own right, and reads more clearly without the case work mixed in.

What makes a split awkward is that detections are deployed from this repo: [`splunk/build-savedsearches.py`](../../splunk/build-savedsearches.py) generates `savedsearches.conf` from [`detections/`](../../detections/).

## Decision
1. **Case work moves to a new public repo, [soc-casework](https://github.com/J-DeMarzo/soc-casework):** case write-ups and their evidence, the case template, and the Phase 5 roadmap.
2. **Splunk stays here: `splunk/` and `detections/`.** Detections stay next to the generator that deploys them, so there is one source of truth. A detection written or tuned during a case is committed here, and the case links to that commit.
3. **Links between the repos are absolute GitHub URLs.** Cases link to the detection's commit permalink, so the link shows the version that actually fired.
4. **`docs/investigations/` was copied, not moved with its history.** It held only a README and the template, and its three commits were roadmap edits that belong to this repo's history.

## Consequences
- ✅ Each README has one purpose: this one shows the environment, soc-casework shows the analyst work.
- ✅ The detection deploy pipeline is unchanged.
- ❌ A case that changes a detection takes two commits in two repos.
- ❌ Nothing checks the links between repos. Renaming or moving a detection here breaks a link there, so check soc-casework before doing that.
