# Runbook: Rebuild the Kali attack box and its template

**When:** Kali needs a clean start (a polluted box, a new Kali release), or the template is stale. For a normal reset, roll `kali` back to its `Clean` snapshot.

**Result:** `kali` (VM 250, sevro, VLAN 40) and the golden template `Kali-Master` (9000, sevro). Last done 2026-10-14 with Kali 2026.2. Both are built from Kali's **official prebuilt QEMU image**, not the installer, so there's no console clicking.

## 1. Get and verify the image (on `ops`)
Work in a new empty directory. The image is 3.9 GB (16 GB extracted, 80 GiB virtual).
```bash
curl -fsSLO https://cdimage.kali.org/current/SHA256SUMS
curl -fsSLO https://cdimage.kali.org/current/SHA256SUMS.gpg
curl -fsSL  https://archive.kali.org/archive-keyring.gpg -o keyring.gpg
gpg --show-keys --with-fingerprint keyring.gpg        # check the fingerprints against kali.org
gpg --no-default-keyring --keyring ./kali.kbx --import keyring.gpg
gpg --no-default-keyring --keyring ./kali.kbx --verify SHA256SUMS.gpg SHA256SUMS   # "Good signature"
curl -fsSLO https://cdimage.kali.org/current/kali-linux-<ver>-qemu-amd64.7z
sha256sum kali-linux-<ver>-qemu-amd64.7z               # must equal the line in SHA256SUMS
7z x kali-linux-<ver>-qemu-amd64.7z                    # needs p7zip-full
```

## 2. Tear down the old ones (if rebuilding)
Both are disposable, but check they're the right VMs first.
```bash
ssh sevro 'sudo qm stop 250; sudo qm destroy 250 --purge'
```
If the old template's disk is on NFS (`VM-Templates`), **delete it from sevro, never darrow** ([INC-2026-001](../incidents/2026-09-30-darrow-nfs-stale-handle.md)). A template's config belongs to its node, so move it first, then destroy from sevro:
```bash
ssh sevro 'sudo mv /etc/pve/nodes/<owner>/qemu-server/9000.conf /etc/pve/nodes/sevro/qemu-server/; sudo qm destroy 9000 --purge'
```
The `chattr … Operation not supported` line on NFS is harmless. Afterwards check `pvesm status` on all three nodes shows `VM-Templates` active.

## 3. Create the VM
Stream the extracted `.qcow2` to sevro, then create the VM and import the disk (thin on ZFS: ~9 GiB used of 80):
```bash
cat kali-linux-<ver>-qemu-amd64.qcow2 | ssh sevro 'sudo mkdir -p /var/tmp/kali-import && sudo tee /var/tmp/kali-import/kali.qcow2 >/dev/null'   # ~7 min
ssh sevro 'sudo qm create 250 --name kali --memory 4096 --cores 4 --cpu x86-64-v2-AES \
  --net0 virtio,bridge=vmbr0,firewall=1,tag=40 --scsihw virtio-scsi-single --ostype l26 --agent 1 --vga qxl --tags "lab;net-lab"
  sudo qm importdisk 250 /var/tmp/kali-import/kali.qcow2 fast-local
  sudo qm set 250 --scsi0 fast-local:vm-250-disk-0,discard=on,iothread=1,ssd=1 --boot order=scsi0
  sudo qm start 250; sudo rm -rf /var/tmp/kali-import'
```
Find its address from the Omada DHCP log in Splunk by MAC (`qm config 250` shows it, written with dashes). The image already runs the guest agent, so `qm guest exec 250` works before SSH does.

## 4. Access (through the guest agent)
The image ships with SSH **off** and the well-known `kali`/`kali` login. Through `qm guest exec` (a script passed as base64 into `bash`):
- create `demarzo` in `sudo` with `NOPASSWD` sudo, `authorized_keys` = the `demarzo@ops` key (`from="10.12.5.10"`) and the desktop key;
- `/etc/ssh/sshd_config.d/10-lab.conf`: `PasswordAuthentication no`, `KbdInteractiveAuthentication no`, `PermitRootLogin no`, `AllowUsers demarzo`; then `systemctl enable --now ssh`;
- give `kali` a random password (set from a hash with `chpasswd -e`, kept in `~/.config/kennel/kali-console.pass` on ops), and give `demarzo` the lab's console password.
Pin the host key only after its fingerprint (`qm guest exec 250 -- ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub`) matches `ssh-keyscan`.

## 5. Update, snapshot, template
1. `sudo apt-get update && sudo apt-get -y full-upgrade` (detached: it took ~20 min after a June image), reboot, check the new kernel, `sudo apt-get clean`.
2. Write the Notes card, shut down, then **clone to the template**: `qm clone 250 9000 --name Kali-Master --full --storage fast-local`.
3. Boot the clone once and generalize it through the guest agent: install a first-boot unit `regen-ssh-host-keys.service` (`ConditionPathExists=!/etc/ssh/ssh_host_ed25519_key`, `Before=ssh.service`, `ssh-keygen -A`), delete `/etc/ssh/ssh_host_*`, empty `/etc/machine-id`, clear shell history and the journal. Shut down and `qm template 9000`.
4. **Prove it:** clone 9000 to a throwaway VMID, boot it, and check it has its own host key and machine-id, `demarzo` can SSH in with sudo, and the agent answers. Destroy the throwaway and remove its key from `known_hosts`.
5. Take the baseline on the stopped box: `qm snapshot 250 Clean`.

## Notes
- The template stays on sevro's `fast-local`, like the Ubuntu one's clones: clone there, then `qm migrate` to the target node. Unlike 9001 it is not on NFS, which avoids the delete problem above.
- DHCP gives `kali` an address from the VLAN 40 pool. Reserve it in Omada if other docs or rules need to name it.
