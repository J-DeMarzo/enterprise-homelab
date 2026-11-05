# Runbook: Discord Proxmox bot

**What:** Claude Code in a tmux session on `bots` (LXC 301), running as the unprivileged user `discord-bot`, with the Discord channel plugin and the `proxmox` MCP server. Requests arrive as Discord messages. Its Proxmox access is the scoped `discord-bot@pve` token ([ADR 0009](../adr/0009-least-privilege-proxmox-api-identities.md)). Why it's set up this way: [ADR 0012](../adr/0012-discord-bot-unprivileged.md).
**When:** the bot isn't answering, you got a health alert DM, the login is due for renewal, or you're rebuilding `bots`.

## How it runs

Everything lives in `/home/discord-bot`, mode 750. The `demarzo` admin login holds no bot credentials.

| Piece | Where | What it does |
|---|---|---|
| `claude-discord.service` (user unit) | `~/.config/systemd/user/` | Waits for DNS, then starts Claude in tmux (socket `claude-discord`), from `~/proxmox-bot` |
| `claude-discord-health.timer` + `.service` (user units) | `~/.config/systemd/user/` | Runs the health check 5 minutes after boot, then every 5 minutes |
| `claude-discord-health` | `~/.local/bin/` | The health check, below |
| `CLAUDE.md`, `.claude/settings.json` | `~/proxmox-bot/` | The bot's rules and tool permissions |
| `.credentials.json` | `~/.claude/` | The Claude login. It lasts about 4 weeks and needs a browser to renew |
| `.env`, `access.json` | `~/.claude/channels/discord/` | Discord bot token and sender allowlist |
| `config.json` | `~/.config/proxmox-mcp/` | Proxmox targets and token |

Files: [`scripts/discord-bot/`](../../scripts/discord-bot/). Lingering is on for `discord-bot`, so the units run with no one logged in.

## What the bot can reach

The bot takes instructions from chat, so it gets only what its job needs. Proxmox permissions are enforced by the token, and these limits cover the host and the account:

| Limit | How | Check |
|---|---|---|
| No sudo, no access to admin files, no SSH in | Dedicated user, not in `sudo`, password locked, no `authorized_keys`. `NoNewPrivileges=yes` also blocks setuid programs for the whole process tree | `grep NoNewPrivs /proc/<pid>/status` shows `1` |
| No shell, file or web tools | `--tools ''` in the unit, so the model doesn't have them. `Bash`, `Edit`, `Write`, `NotebookEdit`, `WebFetch`, `WebSearch` and `Agent` are also denied in the settings file | Ask the bot from its terminal |
| No Gmail, Drive, Calendar or other claude.ai connectors | `"disableClaudeAiConnectors": true` in the settings file. A claude.ai login brings them into the session otherwise | Only `mcp-logs-plugin-discord-discord` and `mcp-logs-proxmox` exist under `~/.cache/claude-cli-nodejs/` |
| No Discord attachments | `download_attachment` denied in the settings file | |

**Don't deny `Read` in the settings file.** It stops `CLAUDE.md` from loading, and with it the bot's safety rules. The pane warns `Instruction file not loaded`.

**Don't use `claude setup-token`.** Channels refuse that token: the pane says `Channels are not currently available`, while the MCP servers still start and hold a Discord connection, so the bot looks healthy and drops every message. Channels need a claude.ai login or a Console API key.

## Why `active (running)` doesn't mean healthy

`systemctl` only sees the tmux server. Claude keeps running inside it even when the bot can't work, and `Restart=on-failure` never fires. Two failures look identical from systemd, and both had happened by 2026-11-05, after the bot had been silent for 19 days:

- **MCP servers don't retry.** They get one attempt at startup. On 2026-10-17 `ragnar` rebooted, and the bot started at 22:38:22, before the network was online at 22:38:55. Both servers failed on DNS and never came back. The old `After=network-online.target` did nothing, because that target only exists in the system manager. The unit now waits for DNS in `ExecStartPre`. *Evidence (2026-11-05):* with DNS blocked, restarting the bot left the service `activating`, with no Claude process, for the full 30 seconds. Once DNS returned, both servers connected first time with no DNS errors. A real reboot also came up clean, though the network was ready in about a second, so that alone doesn't test the wait.
- **The login expires.** A running session can't recover once it lapses, and a restart doesn't help.

## Health check

| Condition | Action |
|---|---|
| Logged out | Alert. No restart, because it wouldn't help |
| Login expires within 3 days, or its state can't be read | Alert |
| Discord server, its connection, or the Proxmox server missing on 2 runs in a row | Restart (at most once per 30 minutes) and alert |
| Service in any state other than `active` or `inactive` | Alert. systemd handles the restart |
| Service `inactive` | Nothing. It was stopped on purpose |

Alerts are Discord DMs from the bot to the allowlisted user, repeated every 6 hours while the problem lasts, with a second DM when it clears. They're also written to the journal.

**What it can't see:**
- A session waiting on a permission prompt, or one that has hit a plan usage limit.
- A login revoked on the server side while the local state still looks valid.
- Anything at all if Discord is down or the bot token is revoked, because the DM can't be sent. The journal still has the problem.

## Troubleshooting

From `ops`, run `ssh bots`, then `sudo -iu discord-bot`:

```bash
journalctl --user -u claude-discord-health -n 20      # what the check last found
claude auth status                                    # login state and expiry
tmux -L claude-discord capture-pane -p -t claude-discord    # the bot's screen
pstree -a $(tmux -L claude-discord list-panes -F '#{pane_pid}')    # expect bun server.ts and proxmox-mcp-plus
```

**Renew the login,** from `ops`, in your own terminal:

```bash
ssh -t bots 'sudo -u discord-bot -H env PATH=/home/discord-bot/.npm-global/bin:/usr/bin:/bin claude auth login'
ssh bots 'sudo -iu discord-bot systemctl --user restart claude-discord'
```

**Reset the Discord token.** Click **Reset Token** on the bot's page in the Discord Developer Portal, then run this from `ops`, in your own terminal, and paste once. The prompt is hidden, so nothing shows when you paste, and pasting more than once saves an invalid token:

```bash
ssh -t bots 'sudo -u discord-bot -H bash -c "umask 077; read -rsp \"New token: \" t; echo; printf \"DISCORD_BOT_TOKEN=%s\n\" \"\$t\" > ~/.claude/channels/discord/.env"'
ssh bots 'sudo -iu discord-bot systemctl --user restart claude-discord'
```

Don't use `/discord:configure` to do this, because it may leave the token in the Claude history files. A valid token is about 72 characters.

To work on the bot without the check restarting it, stop the service: `systemctl --user stop claude-discord`. To see the screen live, use `tmux -L claude-discord attach`, and detach with `Ctrl-b d`.

## Rebuild

As `demarzo` on `bots`, create the user:

```bash
sudo useradd -m -s /bin/bash -c "Discord Proxmox bot" discord-bot
sudo loginctl enable-linger discord-bot
sudo chmod 750 /home/discord-bot
printf '%s\n' 'export XDG_RUNTIME_DIR=/run/user/$(id -u)' 'export PATH=$HOME/.npm-global/bin:$HOME/.bun/bin:$HOME/.local/bin:$PATH' | sudo -u discord-bot tee -a /home/discord-bot/.profile
```

As `discord-bot`, install Claude Code (npm prefix `~/.npm-global`), Bun and uv, then install and configure the plugin and the MCP server:

1. `claude auth login`, then in a session: `/plugin install discord@claude-plugins-official`, `/discord:configure <token>`, `/discord:access pair <code>`, and `/discord:access policy allowlist`.
2. Write `~/.config/proxmox-mcp/config.json` (mode 600) with the `discord-bot@pve` token, and add the server: `claude mcp add -s user -e PROXMOX_MCP_CONFIG=$HOME/.config/proxmox-mcp/config.json proxmox -- $HOME/.local/bin/uvx proxmox-mcp-plus`.

Then copy the files from `scripts/discord-bot/` to these paths:

| File | Goes to | Mode |
|---|---|---|
| `bot-CLAUDE.md` | `~/proxmox-bot/CLAUDE.md` | 644 |
| `bot-settings.json` | `~/proxmox-bot/.claude/settings.json` | 644 |
| `claude-discord.service`, `claude-discord-health.service`, `claude-discord-health.timer` | `~/.config/systemd/user/` | 644 |
| `health.py` | `~/.local/bin/claude-discord-health` | 755 |

```bash
systemctl --user daemon-reload && systemctl --user enable --now claude-discord.service claude-discord-health.timer
```

Check: the plugin log says `Channel notifications registered`, the bot answers a Discord message, and `systemctl --user start claude-discord-health` logs `healthy`.
