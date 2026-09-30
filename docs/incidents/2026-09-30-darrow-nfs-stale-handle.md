# INC-2026-001: darrow lost access to `VM-Templates` (stale NFS handle)

| | |
|---|---|
| **Date** | 2026-09-30, from 01:02 (local) until the owner remounted the share |
| **Severity** | Low. No running workloads affected |
| **Detected by** | API error while building template 9001 |
| **Status** | Resolved |

## Summary
While building the Ubuntu golden template, a corrupted image upload was deleted from `VM-Templates` through the Proxmox API on **darrow**. Three seconds later darrow marked the NFS storage inactive, and every listing on darrow failed with `failed to create content directory '/mnt/pve/VM-Templates/import' … File exists`. sevro and ragnar kept normal access to the same share.

## Impact
- darrow couldn't read `VM-Templates`, so no cloning of Kali-Master (9000) from darrow.
- `pvestatd` logged the error every 10 seconds.
- No running VM used the share from darrow. Data on the share was intact (confirmed from sevro and ragnar).

## Timeline
| Time | Event |
|---|---|
| 01:01:47 | Image uploaded through darrow. Checksum fields after the file part were appended into the file (+286 bytes) |
| 01:02:16 | Corrupted image deleted through darrow's API (`imgdel` OK) |
| 01:02:19 | First `failed to create content directory … File exists` on darrow. `active=0` |
| 01:02–01:05 | Diagnosis: sevro and ragnar healthy, fault limited to darrow's mount |
| Before rebuild resumed | Owner remounted the share on darrow (suggested: lazy unmount, then Proxmox auto-remounts). Verified `active=1` and identical listings on all three nodes |

## Root cause (probable)
A **stale NFS file handle** on darrow for the `import/` directory, which darrow itself had created seconds earlier on its first upload of `import` content. After the delete, darrow's cached handle for the directory was invalid. Proxmox's "ensure content directory exists" check then saw `mkdir` fail with EEXIST while the directory test failed, and marked the storage inactive. The exact NFS-client trigger wasn't reproduced.

## Resolution
Owner, on darrow as root (suggested procedure):
```bash
ls -la /mnt/pve/VM-Templates/       # shows the stale handle
umount -l /mnt/pve/VM-Templates
pvesm status | grep VM-Templates   # auto-remounted, active
```
The automation token couldn't fix this itself: remounting needs root.

## Follow-ups
- [x] Upload procedure fixed so no corrective delete is needed (file as the last multipart field, byte-exact size check). See [the template runbook](../runbooks/build-ubuntu-template.md)
- [x] Working practice: avoid deleting files on NFS-backed storage through the API during automation. Prefer overwriting with a correct upload, or deleting from a single designated node
- [ ] Once Splunk is ingesting Proxmox syslog: alert on `failed to create content directory` and on storage `active=0`
