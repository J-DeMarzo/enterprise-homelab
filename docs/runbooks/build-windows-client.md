# Runbook: Build the lab Windows 11 clients (ws01, ws02)

**What:** two domain-joined workstations in `ad.demarzo.lab`, the endpoints for the Phase 5 attacks (password spraying, Kerberoasting, LSASS dumping, persistence). Windows 11 Enterprise **Evaluation** (90 days), stock image, no debloating: Defender, Windows Update and event logging stay as they ship, so attacks look like they would on a corporate desktop. Leaning the clients down is done with Group Policy from `dc01`, the way an enterprise does it.

| Client | VM | Node | Why there |
|---|---|---|---|
| `ws01` | 251 | sevro | darrow already runs splunk, dc01 and llm (78% RAM). Spreading the clients uses the idle nodes, and puts attacker (kali, sevro), DC (darrow) and victims on three hosts, so their traffic crosses the real VLAN 40 |
| `ws02` | 350 | ragnar | |

**Network:** VLAN 40 (Security) · address by DHCP (Omada) · DNS set to `dc01` (10.12.40.10), which forwards to dns1/dns2.
**When:** first build, or a rebuild when the evaluation runs out.
**Time:** about 13 minutes from power-on to the guest agent, both clients in parallel, then about 2 minutes for the join and reboot.

Built 2026-10-03. Both evaluations expire **2027-01-01**.

## Tooling
Everything runs from `ops` through [`scripts/win-client`](../../scripts/win-client), a generalized copy of the DC's [`vm152`](../../scripts/vm152). It acts **only on ws01 (251, sevro) and ws02 (350, ragnar), on VLAN 40**, and has no delete.

- Proxmox token: read from the MCP config on ops, never printed.
- Passwords on ops (0600, outside the work folder): `~/.config/dc-build/client-admin.pass` for the clients' local `labadmin`, and `~/.config/dc-build/admin.pass` for `LAB\Administrator`. `exec` fills in `__ADMIN_PASSWORD__` / `__DOMAIN_PASSWORD__` and never logs the values.
- Work folder `~/claude/dc-build/`: the answer file, `log/win-client.log` (every call), screenshots.

## Steps
1. **Media** (one-time). On **sefi**, into `/pax/iso/template/iso/` (the path behind the NFS `ISO` storage):
   ```bash
   curl -L -o Win11Ent-eval-26300.9457.iso 'https://go.microsoft.com/fwlink/?LinkId=2382600&clcid=0x409&culture=en-us&country=us'
   ```
   The Evaluation Center page asks for a form, but the fwlink behind it redirects straight to Microsoft's CDN. `chmod 644` the file.
   - 2026-10-03 build: 26H2, build 26300.9457, 8,225,329,152 bytes, SHA-256 `bc3f24086ebadc94489066b5ad78089e2cf5c3491e90e790bb81a2b199c10e38`.
   - `install.wim` has a single image (index 1, `Windows 11 Enterprise Evaluation`, `EnterpriseEval`). The media is UDF-only, so `isoinfo` can't list it; loop-mount it read-only on sefi to inspect it.
2. **Answer file:** [`windows/autounattend-win11-client.xml`](../../windows/autounattend-win11-client.xml) → `~/claude/dc-build/`, then `win-client ws01 answer-iso` (and `ws02`). The ISO is built on sefi itself ([INC-2026-001](../incidents/2026-09-30-darrow-nfs-stale-handle.md)). The file covers:
   - GPT for UEFI: EFI system partition, MSR, Windows
   - virtio-scsi and NetKVM drivers (`w11` folders) loaded in WinPE from D:/E:/F:
   - computer name, local `labadmin` (Administrators), online-account and Wi-Fi screens hidden, auto-logon once
   - at first logon, `virtio-win-guest-tools.exe /install` (drivers + QEMU guest agent)
3. **VM:** `win-client ws01 create`, then `win-client ws01 start --boot-cd`. The hardware is fixed in the wrapper: q35, **OVMF with Microsoft Secure Boot keys pre-enrolled, vTPM 2.0**, `x86-64-v2-AES`, 2 vCPU / 4 GiB, 64 GB virtio-scsi-single on `fast-local`, virtio NIC on VLAN 40. `--boot-cd` presses Enter through OVMF's "Press any key to boot from CD" prompt; dc01 avoided it with SeaBIOS, which Windows 11 can't use.
4. **Wait for the guest agent:** `win-client ws01 status` shows `guest agent: responding`.
5. **DNS → DC, then join** into `OU=Workstations` (created on dc01 for GPO targeting):
   ```powershell
   Set-DnsClientServerAddress -InterfaceAlias Ethernet* -ServerAddresses 10.12.40.10
   $c = New-Object PSCredential('LAB\Administrator', (ConvertTo-SecureString '__DOMAIN_PASSWORD__' -AsPlainText -Force))
   Add-Computer -DomainName ad.demarzo.lab -OUPath 'OU=Workstations,DC=ad,DC=demarzo,DC=lab' -Credential $c -Restart -Force
   ```
6. **Clean up:** `win-client ws01 detach-media`. It also deletes `ws01-answer.iso` on sefi, which holds `labadmin`'s password in plain text.
7. **Register:** Notes card ([standard](../architecture/compute.md#guest-notes-standard)) and regenerate the inventory.

## Verification
Run 2026-10-03 on both clients:

| Check | Result |
|---|---|
| Edition and build | `Windows 11 Enterprise Evaluation`, 10.0.26300.9457, `slmgr /xpr`: expires 2027-01-01 |
| Firmware | `Confirm-SecureBootUEFI` True · TPM present and ready · EFI disk `ms-cert=2023k` |
| Defender | Real-time protection on |
| Network | DHCP on VLAN 40: ws01 10.12.40.102, ws02 10.12.40.100, gateway 10.12.40.1. DNS 10.12.40.10 after step 5 |
| Domain | `PartOfDomain` True, `Test-ComputerSecureChannel` True, `nltest /dsgetdc` → `\\DC01.ad.demarzo.lab`. Both in `OU=Workstations` on dc01 with their OS version, and with A records in `ad.demarzo.lab` registered by the clients |
| Outside DNS | `microsoft.com` resolves through dc01 → dns1/dns2 |
| DC Security log | Kerberos TGTs (4768), service tickets (4769) and logons (4624) for WS01/WS02 within 15 minutes of the join. They reach Splunk once dc01 has a forwarder |
| Cleanup | Install media detached, both answer ISOs deleted on sefi. A cold boot from disk keeps the secure channel |

## Not done yet (roadmap Phase 4)
- Domain user accounts, so attacks run as people rather than machine accounts. Sysmon and the forwarders are on all three Windows hosts since 2026-10-03 ([installer](../../splunk/forwarder/install-uf-windows.ps1), [notes](../architecture/siem.md#windows-specifics))
- The GPO baseline (consumer features, widgets, Copilot off) linked to `OU=Workstations`
- Golden template for rebuilds
