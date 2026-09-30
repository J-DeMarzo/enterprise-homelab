# Runbook: Cluster node maintenance (patching / reboot)

**When:** Applying Proxmox updates or doing hardware work on a TheRising node. Do **one node at a time**.

## Before you start
- Check the cluster is healthy and quorate: `pvecm status` shows `Quorate: Yes` and 3 votes.
- Read the Proxmox release notes if it's a major version jump.
- **If the node is `sevro`:** dns1 will go down and clients will fail over to dns2. First check that dns2 answers: `host sevro.demarzo.lab 10.12.5.54`.

## Steps
1. **Move or stop guests.** Guest disks are local ZFS, so migration copies the disk:
   ```bash
   # VMs, live:
   qm migrate <vmid> <other-node> --online --with-local-disks
   # Containers, restart migration (brief downtime):
   pct migrate <vmid> <other-node> --restart
   ```
   Lab or test guests can just be shut down.
2. **Update:**
   ```bash
   apt update && apt full-upgrade
   ```
3. **Reboot:** `reboot`
4. **Check:**
   - `pvecm status`: node is back, `Quorate: Yes`, 3 votes
   - `pveversion`: expected version
   - Guests with `onboot=1` are running again
5. **Move guests back** if you moved them, then go to the next node.

## Rollback
If a node won't rejoin after an update, the other two keep quorum (2 of 3). Guests that were moved keep running elsewhere. Boot the previous kernel from the boot menu, or pin it with `proxmox-boot-tool kernel pin <version>`.

## Afterwards
Run `scripts/inventory.py` and commit if anything changed.
