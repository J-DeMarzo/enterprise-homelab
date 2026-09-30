# Runbook: Build the Ubuntu golden template (VMID 9001)

**When:** Creating or refreshing the Ubuntu Server base image. Refresh roughly quarterly, or when the base is far behind on patches.

**Result:** template `ubuntu-2404-ci` (9001) on `VM-Templates` (NFS on pax): Ubuntu 24.04 LTS, fully patched, with `qemu-guest-agent`, generalized for cloning.

Last built: 2026-09-30.

## 1. Get and verify the image
```bash
curl -O https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img
curl -s https://cloud-images.ubuntu.com/noble/current/SHA256SUMS | grep 'noble-server-cloudimg-amd64.img$'
sha256sum noble-server-cloudimg-amd64.img     # must match the line above
```

## 2. Put it on `VM-Templates` as an import image
Upload it with content type **`import`** and a `.qcow2` filename (the `.img` file is qcow2 inside). In the UI: *VM-Templates → Import → Upload*. Through the API:
```bash
curl -H @auth.hdr -F content=import \
  -F "filename=@noble-server-cloudimg-amd64.img;filename=noble-server-cloudimg-amd64.qcow2" \
  https://<node>:8006/api2/json/nodes/<node>/storage/VM-Templates/upload
```
Then check the stored size **matches the verified file to the byte**.

> ⚠️ **Gotchas**
> - *Download from URL* (`download-url`) needs `Sys.Modify`, which the automation token doesn't have. Upload instead.
> - In the multipart upload, the **file has to be the last field**. Fields sent after it get appended *into the file* (the first attempt came out 286 bytes too large). Sending the `checksum` fields before the file was rejected by the parser. So upload with only `content` + file, and verify the size yourself.

## 3. Create the build VM
```bash
qm create 9001 --name ubuntu-2404-ci --ostype l26 --memory 2048 --cores 2 --cpu x86-64-v2-AES \
  --scsihw virtio-scsi-single \
  --scsi0 VM-Templates:0,import-from=VM-Templates:import/noble-server-cloudimg-amd64.qcow2,discard=on,iothread=1,ssd=1 \
  --ide2 VM-Templates:cloudinit --boot order=scsi0 --serial0 socket --vga serial0 \
  --agent enabled=1,fstrim_cloned_disks=1 \
  --net0 virtio,bridge=vmbr0,firewall=1,tag=30 --ipconfig0 ip=<temp-ip>/24,gw=10.12.30.1 \
  --nameserver "10.12.5.53 10.12.5.54" --searchdomain demarzo.lab \
  --ciuser demarzo --sshkeys <file-with-your-key(s)>
qm resize 9001 scsi0 8G
qm start 9001
```
The temporary address is on **Servers (VLAN 30)** so the build host can reach it over SSH. The default-deny ACLs block SSH from Servers into Management.

## 4. Patch and add the guest agent
```bash
ssh demarzo@<temp-ip>
cloud-init status --wait
sudo apt-get update
sudo apt-get -o DPkg::Lock::Timeout=300 -y full-upgrade
sudo apt-get -o DPkg::Lock::Timeout=300 -y install qemu-guest-agent
sudo systemctl start qemu-guest-agent
```
> ⚠️ Ubuntu runs its own package updates on first boot. Without `DPkg::Lock::Timeout`, the install fails on the dpkg lock.

Check: `qm agent 9001 network-get-interfaces` returns the VM's IP.

## 5. Generalize
Remove everything that would make clones identical:
```bash
sudo apt-get -y autoremove --purge && sudo apt-get clean
sudo cloud-init clean --logs --seed
sudo rm -f /etc/netplan/50-cloud-init.yaml          # temp IP config
sudo rm -f /etc/ssh/ssh_host_*                       # regenerated per clone
sudo truncate -s 0 /etc/machine-id                   # regenerated per clone
rm -f ~/.ssh/authorized_keys ~/.bash_history         # clones get only the keys you configure
sudo fstrim -av && sudo poweroff
```

## 6. Set defaults and convert
```bash
qm set 9001 --ipconfig0 ip=dhcp --sshkeys <desktop-key-only> --tags "template;net-svc"
qm template 9001
```
The default VLAN stays **30 (Servers)** so a clone never lands on Management by accident.

## 7. Test with a throwaway clone
Clone, boot, and check that the clone has its **own** hostname, machine-id, and SSH host key, that cloud-init shows `done`, that the guest agent answers, and that only the configured keys are authorized. Then destroy the test clone.

## Deploying from the template
See [deploy-guest-from-template.md](deploy-guest-from-template.md). **Proxmox won't clone directly to another node's local storage.** Clone on the template's node, then migrate.

## Sefi (standalone node)
Sefi isn't in the cluster and can't clone this template. Sefi VMs (e.g. `ops`) are built from the same verified image using steps 3–4, with the disk on `local-zfs` and the image on Sefi's `ISO` storage (content `iso,import`). Then set the final network, and remove any temporary SSH keys from `authorized_keys` **before** the final boot. Removing a key from cloud-init's settings doesn't delete it from a VM that already booted with it.
