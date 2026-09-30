# Runbook: Deploy a VM from a template

**When:** You need a new VM based on a golden image (e.g. a fresh Kali box from `Kali-Master`, VMID 9000).

## Before you start
- Pick a VMID from the right range ([compute.md](../architecture/compute.md#guest-standards)). You can also get the next free one with `pvesh get /cluster/nextid`.
- Decide the VLAN ([network.md](../architecture/network.md#vlan-plan)). **Always set a tag.** Untagged guests land on management.
- Check the target node has enough free RAM (see [inventory](../inventory.md)).

## Steps
1. **Clone** (on any TheRising node; templates live on shared NFS):
   ```bash
   qm clone 9000 <NEWID> --name <name> --full --storage fast-local --target <node>
   ```
   Use `--full` so the clone doesn't depend on the template's disk.
2. **Set the network and resources:**
   ```bash
   qm set <NEWID> --net0 virtio,bridge=vmbr0,firewall=1,tag=<VLAN> --memory <MiB> --cores <n>
   qm set <NEWID> --description "Owner: demarzo | Role: <role> | VLAN: <VLAN>" --tags <tag1>;<tag2>
   ```
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
