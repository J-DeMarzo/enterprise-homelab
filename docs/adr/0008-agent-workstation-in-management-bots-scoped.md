# 0008. Agent workstation moves to Management; bots isolated with a scoped token

- **Status:** Accepted
- **Date:** 2026-10-01

## Context
LXC 301 `claude` (ragnar, Servers VLAN 30) did several jobs at once. It was the AI agent workstation (Claude Code, herdr, the Proxmox MCP server with a `PVEAdmin` token for both environments), it held the repos, it ran the Discord Proxmox bot and the plan-usage feed for homepage, and it hosted a development app (fantasy-app).

That caused three problems:
- **Admin work from a workload zone.** Most lab administration failed by design from Servers: SSH to the hypervisors, the Technitium and Omada admin UIs, the gateway UI, Splunk's web UI (T14, T16, T21, T23, T28, T30). Working around it took ACL exceptions: rule 7 (`Proxmox Clients`) and, briefly, an extra gateway rule (see the change record). [ADR 0005](0005-admin-hosts-in-management-zone.md) had already flagged `claude` as an `admin` host in the wrong zone.
- **One credential for everything.** The Discord bot used the same near-admin token as the workstation, so anyone who could influence the bot's prompt was one approval away from admin rights on Proxmox.
- **Mixed fate.** A broken app build or a bot problem shared a box with the workstation.

## Decision
1. **`ops` (VM 450, Management) is the single agent workstation.** It runs Claude Code, herdr and the Proxmox MCP server, and holds the repos. Its token, `claude-mcp@pve!ops`, exists only on `ops`. The previous token was rotated during the move.
2. **301 becomes `bots`** and keeps only the Discord bot and the usage feed. The bot gets **its own user, `discord-bot@pve`**, with `PVEAuditor` plus a custom `DiscordBot` role (`VM.PowerMgmt`, `VM.Snapshot`, `Sys.Syslog`) on both environments. It can read, start, stop, and snapshot guests, but can't change config, delete, roll back, clone, or open consoles. The token enforces this, not the bot's prompt.
3. **`bots` stays on Servers, not the DMZ.** The DMZ is for services that accept inbound connections from the internet. The bot only connects outbound. A DMZ host that needs the Proxmox API would require a DMZ → Management hole, the worst possible exception. Keeping the reserved IP (10.12.30.101) keeps rule 7 unchanged.
4. **Development apps get their own guest:** fantasy-app moved to LXC 201 `fantasy` (sevro, 10.12.30.30), driven from `ops` through herdr's remote machines. It's in no IP group.
5. **No new ACLs.** Management → all zones is already allowed, so `ops` reaches `fantasy`, `bots`, and everything else without changes.

## Consequences
- ✅ No host outside Management holds a credential that can change Proxmox configuration. A compromised or prompt-injected bot can at worst power-cycle or snapshot guests. *Evidence:* a config write with the bot's token returns `403 Permission check failed`, even after the request is approved in Discord.
- ✅ Admin tasks that were blocked from Servers now work from `ops` without exceptions (T31–T35).
- ✅ The Servers → Management exceptions shrink to rule 7 for `bots` and `homepage`, port 8006 only. Splunk's host firewall no longer accepts SSH from Servers (T37).
- ❌ `ops` is now the highest-value host in the lab: a Proxmox token (PVEAdmin at first, cut down to `OpsAgent` the same day, [ADR 0009](0009-least-privilege-proxmox-api-identities.md)), a GitHub token, and SSH keys for `fantasy` and `dmz-edge`. Mitigations: key-only SSH, Management is reachable only from Management and the admin desktop, and the scoped token role.
- ❌ `VM.PowerMgmt` still lets the bot stop any guest, including `dns1`. Accepted: the bot's rules require an explicit "yes" in Discord before any disruptive action, and the power is needed for its main job.
- ⚠️ The retests exposed **configuration drift**: a gateway rule added on 2026-09-30 for `claude` → Management was never recorded in [firewall-rules.md](../architecture/firewall-rules.md), and it let a brand-new Servers host (`fantasy`) reach Management. The rule and its IP group were deleted during this change. Lesson: every gateway change gets recorded in the rules table the same day, and every new guest gets a reachability check (T36).

## Change record
| Step | Result |
|---|---|
| `ops` resized to 4 vCPU / 6 GiB, snapshot `pre-agent-host` | Rollback point |
| Tooling and state moved to `ops` (Claude Code, herdr, MCP, repos, memory) | Fresh logins and a new SSH key. No credentials copied |
| fantasy-app → LXC 201 `fantasy` | Same commit, data checksums identical, 103 tests pass, `next dev` serving. 301's copy removed after verification |
| `discord-bot@pve` + `DiscordBot` role created (owner, as root), bot token minted and installed on 301 | Reads OK, config write → 403 |
| `claude-mcp@pve!mcp` → `!ops` | Old token deleted on both environments, returns 401 |
| 301 renamed `bots`, restarted | Same IP, both services back, bot answers in Discord |
| `ops` key authorized on `dmz-edge` (from 10.12.5.10 only); 301's key and GitHub login removed | demarzo.dev deploys from `ops` |
| Undocumented gateway rules "claude → VLAN 5" (with its IP group) and "claude → dmz-edge:22" deleted (owner) | `fantasy` → Management blocked (T36). Servers → dmz-edge:22 blocked |
| Splunk ufw: SSH from Servers (10.12.30.0/24) removed (owner, `qm guest exec` from darrow); 301's stale key removed from splunk, `ops` key added | T37 |
