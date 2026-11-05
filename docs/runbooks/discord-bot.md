# Runbook: Discord Proxmox bot

**What:** Claude Code in a tmux session on `bots` (LXC 301), with the Discord channel plugin and the `proxmox` MCP server. Requests arrive as Discord messages. Its Proxmox access is the scoped `discord-bot@pve` token ([ADR 0009](../adr/0009-least-privilege-proxmox-api-identities.md)).
**When:** the bot isn't answering, you got a health alert DM, or you're rebuilding `bots`.

## How it runs

| Piece | Where on `bots` | What it does |
|---|---|---|
| `claude-discord.service` (user unit) | `~/.config/systemd/user/` | Waits for DNS, then starts `claude --channels plugin:discord@claude-plugins-official` in tmux (socket `claude-discord`), from `~/proxmox-bot` |
| `claude-discord-health.timer` + `.service` (user units) | `~/.config/systemd/user/` | Runs the health check 5 minutes after boot, then every 5 minutes |
| `claude-discord-health` | `~/.local/bin/` | The health check, below |
| `~/.claude/.credentials.json` | | The Claude login. It expires after about 4 weeks and needs a browser to renew |
| `~/.claude/channels/discord/` | | Discord bot token (`.env`) and sender allowlist (`access.json`) |
| `~/.config/proxmox-mcp/config.json` | | Proxmox targets and token |

Files: [`scripts/discord-bot/`](../../scripts/discord-bot/). Lingering is on for `demarzo`, so the units run with no one logged in.

## Why `active (running)` doesn't mean healthy

`systemctl` only sees the tmux server. Claude keeps running inside it even when the bot can't work, and `Restart=on-failure` never fires. Two failures look identical from systemd, and both happened at once on 2026-11-05, after the bot had been silent for 19 days:

- **MCP servers don't retry.** They get one attempt at startup. On 2026-10-17 `ragnar` rebooted, and the bot started at 22:38:22, before the network was online at 22:38:55. Both servers failed on DNS and never came back. The old `After=network-online.target` did nothing, because that target only exists in the system manager. The unit now waits for DNS in `ExecStartPre`.
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

Run these on `bots`:

```bash
journalctl --user -u claude-discord-health -n 20      # what the check last found
~/.npm-global/bin/claude auth status                  # login state and expiry
tmux -L claude-discord capture-pane -p -t claude-discord    # the bot's screen
pstree -a $(tmux -L claude-discord list-panes -F '#{pane_pid}')    # expect bun server.ts and proxmox-mcp-plus
ls -t ~/.cache/claude-cli-nodejs/-home-demarzo-proxmox-bot/mcp-logs-plugin-discord-discord | head -1    # newest plugin log
```

**Renew the login,** from `ops`:

```bash
ssh -t bots '~/.npm-global/bin/claude auth login'
ssh bots 'systemctl --user restart claude-discord'
```

To work on the bot without the check restarting it, stop the service: `systemctl --user stop claude-discord`. To see the screen live, use `tmux -L claude-discord attach`, and detach with `Ctrl-b d`.

## Rebuild

From `scripts/discord-bot/`, after Claude Code, Bun and uv are installed and the plugin is configured:

```bash
scp claude-discord.service claude-discord-health.service claude-discord-health.timer bots:.config/systemd/user/
scp health.py bots:.local/bin/claude-discord-health
ssh bots 'chmod 755 ~/.local/bin/claude-discord-health && sudo loginctl enable-linger demarzo && systemctl --user daemon-reload && systemctl --user enable --now claude-discord.service claude-discord-health.timer'
```

Check: send the bot a message, then `systemctl --user start claude-discord-health` and look for `healthy` in the journal.
