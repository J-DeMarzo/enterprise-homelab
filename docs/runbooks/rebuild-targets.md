# Runbook: Build or rebuild a Linux lab target

**When:** a target needs to be rebuilt (after an exercise that can't be rolled back, a version bump, or a fresh start), or a new one is needed. For a normal reset, roll back to the `Clean` snapshot instead.

**Result:** a VM on VLAN 40 cloned from `ubuntu-2404-ci` (9001), with the Splunk forwarder, auditd, a Notes card and a `Clean` snapshot. Timed 2026-10-14 on ragnar: **1m48s** for a `victim`, **2m19s** for a `web` target (which adds Docker and DVWA).

| Kind | Contents | Size |
|---|---|---|
| `victim` | OpenSSH, auditd, UF roles `linux auditd` | 2 vCPU / 2 GiB / 16 GiB |
| `web` | victim plus DVWA + MariaDB in Docker ([compose](../../scripts/targets/dvwa-compose.yml)), UF roles `linux auditd dvwa` | 2 vCPU / 4 GiB / 24 GiB |

Why a script and not a baked template: the forwarder has a per-host identity and credentials, and its version is pinned in [`install-uf.sh`](../../splunk/forwarder/install-uf.sh). Provisioning after the clone keeps 9001 as the only image to maintain.

## Steps (from `ops`)
1. **Destroy the old one**, if rebuilding. The VM is disposable, but check the name first:
   ```bash
   ssh ragnar 'sudo qm stop <vmid>; sudo qm destroy <vmid> --purge'
   ```
2. **Build:**
   ```bash
   scripts/build-target.sh <victim|web> <vmid> <name> [node]
   ```
   Current targets: `victim 350 linux-victim`, `web 352 vuln-web` (both on ragnar). The script clones 9001 on sevro, tags VLAN 40, migrates, starts, waits for an address, **checks the SSH host key against the guest agent before trusting it**, installs the roles, writes the Notes card and takes `Clean`.
3. **Pin the address:** the script prints the MAC. Add a DHCP reservation in Omada for it, so the IP is stable and the Splunk zone lookup keeps working.
4. **Update the docs:** `python3 scripts/inventory.py` and commit.

## Check that it worked
- `| tstats count where index=linux host=<name> by sourcetype` shows `journald` and `linux:audit`. A `web` target also shows `apache:access` in `index=web` once DVWA has served a request.
- `qm listsnapshot <vmid>` shows `Clean`.

## Notes
- DHCP may hand out a free address that another lab machine uses elsewhere (a throwaway rebuild got 10.12.40.101, `kali`'s old address, while kali was stopped). Reserve addresses in Omada for machines that matter.
- The `victim` is key-only for SSH. Cases that need password authentication (SSH brute force) add a weak test account first, then re-take `Clean`.
- Remove the host key of a destroyed target from `~/.ssh/known_hosts` (`ssh-keygen -R <ip>`), or the next build on that address fails the host-key check.
