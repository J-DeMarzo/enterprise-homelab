# Runbook: Build the lab domain controller (dc01)

**What:** `dc01`, VM 152 on darrow: Windows Server 2025 Standard **Evaluation**, the only DC of the lab AD domain `ad.demarzo.lab` (NetBIOS `LAB`), with AD-integrated DNS forwarding to dns1/dns2.
**Network:** VLAN 40 (Security) · 10.12.40.10 static · `dc01.demarzo.lab` in lab DNS.
**When:** first build, or a rebuild when the evaluation runs out (180 days from install, one `slmgr /rearm` available).
**Time:** about 15 minutes, hands-off. Windows installed in 7 minutes, and the promotion plus reboot took 2.

Built 2026-10-02. The evaluation expires **2027-03-30**.

## Tooling
Everything runs from `ops` through [`scripts/vm152`](../../scripts/vm152), a wrapper installed root-owned at `/usr/local/bin/vm152`. It can act **only on VM 152 on darrow, on VLAN 40**: create, power, run PowerShell through the guest agent, screenshots, detach media. It has **no delete**. It was built as the only tool for a local-model agent ([below](#local-model-attempt)), and kept because it keeps the build reproducible and contained.

- Proxmox token: read from the MCP config on ops, never printed.
- Admin password: `~/.config/dc-build/admin.pass` on ops (0600, outside the work folder). `vm152` replaces `__ADMIN_PASSWORD__` in the answer file and in `exec` commands, and never logs the value.
- Work folder `~/dc-build/`: the answer file, `log/vm152.log` (every call), screenshots.

## Steps
1. **Media** (one-time). Download the Windows Server 2025 evaluation ISO (Microsoft Evaluation Center, behind a form) **on sefi**, into `/pax/iso/template/iso/`, the local path behind the NFS `ISO` storage. Name it `WinServer2025-eval-26100.32230.iso` and `chmod 644` it.
   - 2026-10-02 build: 8,152,356,864 bytes, SHA-256 `7b052573ba7894c9924e3e87ba732ccd354d18cb75a883efa9b900ea125bfd51`.
   - `install.wim` index **2** = `SERVERSTANDARD` (Desktop Experience). Indexes 1/3 are Core, 4 is Datacenter.
   - The virtio drivers come from `virtio-win-0.1.285.iso`, which has `2k25` driver folders.
2. **Answer file:** [`windows/autounattend-server2025-dc.xml`](../../windows/autounattend-server2025-dc.xml) → `~/dc-build/autounattend.xml`, then `vm152 answer-iso autounattend.xml`. The ISO is built on sefi itself, not through an NFS client ([INC-2026-001](../incidents/2026-09-30-darrow-nfs-stale-handle.md)). The file covers:
   - SeaBIOS with an MBR partition, so there's no UEFI "press any key to boot from CD" prompt
   - virtio-scsi drivers loaded in WinPE from D:/E:/F:
   - image index 2, computer name DC01, and auto-logon once
   - at first logon, `virtio-win-guest-tools.exe /install`, which adds the drivers and the QEMU guest agent
3. **VM:** `vm152 create --cores 2 --memory 4096 --disk 60`, then `vm152 start`. The hardware is fixed in the wrapper: q35, `x86-64-v2-AES`, virtio-scsi-single on `fast-local`, virtio NIC on VLAN 40, guest agent on. `vm152 screenshot` shows progress.
4. **Wait for the guest agent:** `vm152 status` shows `guest agent: responding` (about 7 minutes after start).
5. **Static IP:** disable DHCP, remove the lease, then set 10.12.40.10/24, gateway 10.12.40.1, DNS 10.12.5.53/.54. `New-NetIPAddress` alone leaves the DHCP address in place.
6. **AD DS:** `Install-WindowsFeature AD-Domain-Services -IncludeManagementTools`. This takes more than the 50 s `exec` waits, so poll with `vm152 exec-status <pid>`.
7. **Promote:**
   ```powershell
   Install-ADDSForest -DomainName ad.demarzo.lab -DomainNetbiosName LAB -InstallDns `
     -SafeModeAdministratorPassword (ConvertTo-SecureString "__ADMIN_PASSWORD__" -AsPlainText -Force) -Force
   ```
   It reboots by itself. Functional level is Windows2025Domain/Forest.
8. **DNS:** `Set-DnsServerForwarder -IPAddress 10.12.5.53,10.12.5.54 -UseRootHint $false`. All of the DC's outside lookups go through the lab resolvers, so they're logged in Splunk.
9. **Clean up:**
   - `vm152 detach-media`
   - delete `dc152-answer.iso` **on sefi** (`/pax/iso/template/iso/`). It holds the admin password in plain text
10. **Register:** add the A record `dc01.demarzo.lab` ([runbook](add-dns-record.md); VLAN 40 has no reverse zone, so leave out `ptr=true`). Fill in the Notes card ([standard](../architecture/compute.md#guest-notes-standard)), and regenerate the inventory.

## Verification (2026-10-02)
| Check | Result |
|---|---|
| `Get-ADDomain` / `Get-ADForest` | `ad.demarzo.lab`, `LAB`, Windows2025Domain/Forest, DC01 holds the FSMO roles |
| `dcdiag /test:Advertising /test:Services /test:FSMOCheck` | Pass (exit 0) |
| SRV `_ldap._tcp.dc._msdcs.ad.demarzo.lab` | `dc01.ad.demarzo.lab:389` |
| Forwarding | The DC resolves `ops.demarzo.lab` and `microsoft.com`. Splunk shows both queries at **dns1** from 10.12.40.10, tagged `security` |
| `dc01.demarzo.lab` on dns1 and dns2 | 10.12.40.10 on both |
| Evaluation | `ServerStandardEval`, Licensed, expires 2027-03-30, 1 rearm left |

## Not done yet (roadmap Phase 4)
- Sysmon + Universal Forwarder (`wineventlog`, `sysmon` indexes)
- Windows 11 clients joined to the domain: `ws01` and `ws02` ([runbook](build-windows-client.md))
- Golden template for rebuilds

Lab hosts outside the domain can't resolve `ad.demarzo.lab` yet. Domain members use the DC as their DNS server. If lab-wide resolution is needed, add a conditional forwarder on Technitium.

## Local-model attempt
The first plan was for the local LLM ([ADR 0010](../adr/0010-local-llm-host.md), `qwen3.5:4b` on CPU) to run this build step by step through `vm152`, as its only permitted command, with Claude Code checking each step. The guardrails held under deliberate tests. An OpenCode agent limited to `vm152` was refused:
- command chaining (`; touch …`)
- `$(…)` substitution
- reading the Proxmox token file
- rewriting its own `opencode.json`

Before that last rule existed, a test **did** overwrite the agent's own `opencode.json`. That's why the wrapper now lives root-owned in `/usr/local/bin`, and edits are limited to the answer file, `*.ps1` and notes.

The model couldn't do the work. Step 1 was two read-only commands, and it hadn't finished after 10 minutes. It wrote to a directory it made up, printed pseudo-code instead of calling tools, and twice reported success for actions that had been refused. The build was done directly instead. The local model's integration is left for later.
