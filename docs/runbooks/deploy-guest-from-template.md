# Runbook: Deploy a VM from a template

**When:** You need a new VM based on a golden image: `ubuntu-2404-ci` (9001, [how it's built](build-ubuntu-template.md)) or `Kali-Master` (9000).

## Before you start
- Pick a VMID from the right range ([compute.md](../architecture/compute.md#guest-standards)). You can also get the next free one with `pvesh get /cluster/nextid`.
- Decide the VLAN ([network.md](../architecture/network.md#vlan-plan)). **Always set a tag.** Untagged guests land on management.
- Check the target node has enough free RAM (see [inventory](../inventory.md)).

## Steps
1. **Clone onto fast-local on the template's own node**, then migrate if the VM should run elsewhere. Proxmox refuses to clone straight to another node's local storage (`can't clone to non-shared storage`):
   ```bash
   # on the node that owns the template (9001: sevro, 9000: darrow)
   qm clone <TEMPLATE> <NEWID> --name <name> --full --storage fast-local
   qm migrate <NEWID> <target-node>        # offline, copies the disk; ~25 s for 8 GiB
   ```
   Use `--full` so the clone doesn't depend on the template's disk (and on Sefi's NFS).
2. **Set the network and resources:**
   ```bash
   qm set <NEWID> --net0 virtio,bridge=vmbr0,firewall=1,tag=<VLAN> --memory <MiB> --cores <n>
   qm set <NEWID> --tags "<role>;<zone>"      # see the tag scheme in compute.md
   ```
   Add a Notes card following the [guest notes standard](../architecture/compute.md#guest-notes-standard).
3. **Start it** and wait for the guest agent:
   ```bash
   qm start <NEWID>
   qm agent <NEWID> network-get-interfaces
   ```
4. **Take a baseline snapshot** for lab VMs:
   ```bash
   qm snapshot <NEWID> Clean --description "Baseline after first boot"
   ```
5. **DNS:** if it has a static IP, add a record ([add-dns-record.md](add-dns-record.md)).
6. **Update the docs:** run `scripts/inventory.py` and commit the change.

## Check that it worked
- `qm status <NEWID>` shows `running`.
- The guest has an IP in the expected VLAN's subnet.
- It shows up in the regenerated `docs/inventory.md`.

## Rollback
`qm stop <NEWID> && qm destroy <NEWID> --purge`
