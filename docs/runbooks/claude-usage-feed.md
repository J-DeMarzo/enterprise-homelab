# Runbook: AI usage feed (ops → homepage)

**What:** the **AI Usage** row at the top of homepage, with cards for Claude (session % and weekly %), Codex (ChatGPT plan window %), Copilot (premium requests) and OpenCode (7-day sessions, tokens and cost). Each card shows reset times and its last update.
**When:** rebuilding `ops` or `homepage`, or the card's **Updated** value keeps getting older.

## How it works

Homepage (Servers, VLAN 30) can't open connections into Management ([firewall rules](../architecture/firewall-rules.md); [ADR 0008](../adr/0008-agent-workstation-in-management-bots-scoped.md)). So the card's data comes from `ops`, pushed out on a timer, rather than homepage polling `ops`.

| Piece | Host | What it does |
|---|---|---|
| `claude-usage-push.timer` (user unit, every 60 s) | ops | Runs `~/claude/claude-usage/push.py` |
| `push.py` + `server.py` | ops | `fetch()` (in `server.py`) reads the OAuth token from `~/.claude/.credentials.json` and calls `api.anthropic.com/api/oauth/usage`. `push.py` adds an `updated` timestamp, and on failure re-sends the last good data (`last.json`) with `ok: false` |
| `providers.py` | ops | Codex: `~/.codex/auth.json` → `chatgpt.com/backend-api/wham/usage`. Copilot: `~/.copilot/config.json` → `api.github.com/copilot_internal/user`. OpenCode: read-only query of `~/.local/share/opencode/opencode.db`. Each result goes under its own key in `usage.json`, with its own `updated`/`ok`, and falls back to the last good value independently. Claude's fields stay top-level |
| Key `~/.ssh/claude-usage-push` | ops | Used only for this job. `push.py` runs ssh with `-F none`, so the admin key `demarzo@ops` is never offered |
| Forced-command entry in `~demarzo/.ssh/authorized_keys` | homepage | The key can only write `usage.json`. `restrict` disables shells, PTYs and forwarding. Empty input is rejected |
| `claude-usage-web.service` (system unit) | homepage | `python3 -m http.server` on **127.0.0.1:8787** only, serving `/var/lib/claude-usage/` |
| `AI Usage` group (Claude, Codex, Copilot, OpenCode cards) | homepage | customapi widgets → `http://127.0.0.1:8787/usage.json`; the non-Claude cards map nested fields, e.g. `field: { codex: used_pct }` |

Token freshness: each CLI on `ops` refreshes its own token whenever it runs (the feed only reads tokens; it never refreshes or rewrites them). If a tool isn't used for long enough that the token expires, pushes report `ok: false` and the card's **Updated** shows how old the data is.

Files: [`scripts/claude-usage/`](../../scripts/claude-usage/).

## Rebuild: homepage side
```bash
sudo install -d -o demarzo -g demarzo -m 755 /var/lib/claude-usage
sudo cp claude-usage-web.service /etc/systemd/system/
sudo systemctl daemon-reload && sudo systemctl enable --now claude-usage-web
```
Append this line to `~demarzo/.ssh/authorized_keys`, as one line, with the contents of `ops:~/.ssh/claude-usage-push.pub` at the end:
```
restrict,from="10.12.5.10",command="cat > /var/lib/claude-usage/usage.json.tmp && test -s /var/lib/claude-usage/usage.json.tmp && mv /var/lib/claude-usage/usage.json.tmp /var/lib/claude-usage/usage.json" ssh-ed25519 AAAA… claude-usage-push@ops
```
After a homepage rebuild, its host key changes. Update `ops:~/.ssh/known_hosts` for `10.12.30.100` (check the fingerprint from the console first), or the pushes fail with *Host key verification failed*.

## Rebuild: ops side
```bash
mkdir -p ~/claude/claude-usage ~/.config/systemd/user
cp server.py push.py providers.py ~/claude/claude-usage/
cp claude-usage-push.service claude-usage-push.timer ~/.config/systemd/user/
ssh-keygen -t ed25519 -N "" -C claude-usage-push@ops -f ~/.ssh/claude-usage-push   # then update homepage's authorized_keys
sudo loginctl enable-linger demarzo          # timers keep running with no one logged in
systemctl --user daemon-reload && systemctl --user enable --now claude-usage-push.timer
```
Claude Code must be signed in on `ops` (`~/.claude/.credentials.json`). For the other cards, Codex, Copilot CLI and OpenCode must be signed in too. A tool that isn't signed in only marks its own card `ok: false`.

## Troubleshooting

| Symptom | Check |
|---|---|
| **Updated** keeps getting older | On ops: `journalctl --user -u claude-usage-push -n 20` |
| `"ok": false` with a 401 error | Token expired. Run that tool (Claude Code / `codex` / `copilot`) on ops once to refresh it. Check which key failed with `jq . ~/claude/claude-usage/last.json` |
| *Permission denied (publickey)* | Key or `from=` mismatch in homepage's `authorized_keys` |
| Card shows an API error | On homepage: `systemctl status claude-usage-web`; `curl -s 127.0.0.1:8787/usage.json` |
